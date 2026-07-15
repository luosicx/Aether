//! 端侧推理：基于 candle 的模型加载与流式生成（纯逻辑，无 unsafe）。
//!
//! 将 `MLXInferenceEngine.swift`（Apple MLX，仅 Apple 端）迁移为 candle，
//! 赋能 Android/Windows。复用相同的 safetensors 模型格式，跨端共享。
//!
//! 设计要点：
//! - 仅 host target（wasm32 不编译，Workers 无端侧推理需求）
//! - 纯逻辑层：模型加载（mmap）的 unsafe 在 FFI 层完成，传入已构造的 VarBuilder
//! - CPU 默认；Metal 通过 candle-core feature 开启（iOS 真机构建时）
//! - safetensors 模型（与 MLX 共享格式），支持 Qwen2 系列
//! - 流式生成：逐 token 产出，通过 FFI 返回 Vec 实现
//!
//! 架构：
//! - aether-core/inference.rs（本文件）：推理逻辑（纯 safe Rust）
//! - aether-core-ffi：unsafe mmap 加载 safetensors，构造 VarBuilder，调用本模块

#![cfg(not(target_arch = "wasm32"))]

use std::sync::Mutex;

use candle_core::{Device, Tensor};
use candle_nn::VarBuilder;
use candle_transformers::generation::LogitsProcessor;
use candle_transformers::models::qwen2::{Config, Model as Qwen2Model};
use tokenizers::Tokenizer;

/// 推理配置。对应 MLXInferenceEngine 的加载参数。
pub struct InferenceConfig {
    /// 采样温度（0.0-1.0，0 表示贪婪）。
    pub temperature: f64,
    /// 单次生成最大 token 数。
    pub max_tokens: usize,
    /// 重复惩罚（1.0-1.5，默认 1.1）。
    pub repeat_penalty: f32,
    /// 重复惩罚窗口（默认 64）。
    pub repeat_last_n: usize,
    /// top-p 采样阈值（默认 0.9）。
    pub top_p: f64,
    /// 随机种子（None 表示随机）。
    pub seed: Option<u64>,
    /// EOS token id（从 config.json 读取，None 时跳过 EOS 检测）。
    pub eos_token_id: Option<u32>,
}

impl Default for InferenceConfig {
    fn default() -> Self {
        Self {
            temperature: 0.7,
            max_tokens: 1024,
            repeat_penalty: 1.1,
            repeat_last_n: 64,
            top_p: 0.9,
            seed: None,
            eos_token_id: None,
        }
    }
}

/// 推理错误。
#[derive(Debug, thiserror::Error)]
pub enum InferenceError {
    #[error("模型加载失败: {0}")]
    Load(String),
    #[error("tokenizer 加载失败: {0}")]
    Tokenizer(String),
    #[error("推理失败: {0}")]
    Inference(String),
    #[error("模型未加载")]
    NotLoaded,
    #[error("文件未找到: {0}")]
    NotFound(String),
    #[error("不支持的操作: {0}")]
    Unsupported(String),
}

impl From<candle_core::Error> for InferenceError {
    fn from(e: candle_core::Error) -> Self {
        InferenceError::Inference(e.to_string())
    }
}

/// 已加载的模型（持有 model + tokenizer + device）。
pub struct LoadedModel {
    model: Qwen2Model,
    tokenizer: Tokenizer,
    device: Device,
    config: InferenceConfig,
}

/// 端侧推理引擎。
pub struct InferenceEngine {
    inner: Mutex<Option<LoadedModel>>,
}

/// 生成结果（单 token）。
#[derive(Debug, Clone)]
pub struct GeneratedToken {
    /// token 对应的文本片段。
    pub text: String,
    /// 是否为生成结束 token（EOS）。
    pub is_end: bool,
}

impl InferenceEngine {
    /// 创建引擎（未加载模型）。
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(None),
        }
    }

    /// 从已构造的组件加载模型（纯 safe，mmap 在 FFI 层完成）。
    ///
    /// 参数：
    /// - `vb`：由 FFI 层 mmap safetensors 构造的 VarBuilder
    /// - `tokenizer`：已加载的 tokenizer
    /// - `model_config`：从 config.json 解析的模型配置
    /// - `device`：设备（CPU/Metal/CUDA）
    /// - `config`：推理参数
    pub fn load_from_components(
        &self,
        vb: VarBuilder,
        tokenizer: Tokenizer,
        model_config: &Config,
        device: Device,
        config: InferenceConfig,
    ) -> Result<(), InferenceError> {
        let model =
            Qwen2Model::new(model_config, vb).map_err(|e| InferenceError::Load(e.to_string()))?;

        let loaded = LoadedModel {
            model,
            tokenizer,
            device,
            config,
        };

        *self.inner.lock().unwrap() = Some(loaded);
        Ok(())
    }

    /// 卸载模型，释放内存。
    pub fn unload(&self) {
        *self.inner.lock().unwrap() = None;
    }

    /// 模型是否已加载。
    pub fn is_loaded(&self) -> bool {
        self.inner.lock().unwrap().is_some()
    }

    /// 流式生成文本，返回所有 token（一次性返回，FFI 友好）。
    ///
    /// 由于 FFI 不便传递迭代器，这里返回 `Vec<GeneratedToken>`，
    /// Swift 侧逐个 yield 实现流式效果。
    ///
    /// 对应 MLXInferenceEngine.generate 的流式生成。
    pub fn generate(&self, prompt: &str) -> Result<Vec<GeneratedToken>, InferenceError> {
        let mut guard = self.inner.lock().unwrap();
        let loaded = guard.as_mut().ok_or(InferenceError::NotLoaded)?;

        // tokenize prompt
        let tokens = loaded
            .tokenizer
            .encode(prompt, true)
            .map_err(|e| InferenceError::Inference(e.to_string()))?;
        let mut input_ids: Vec<u32> = tokens.get_ids().to_vec();

        let seed = loaded.config.seed.unwrap_or_else(|| {
            use std::time::{SystemTime, UNIX_EPOCH};
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_nanos() as u64)
                .unwrap_or(42)
        });
        let mut logits_processor = LogitsProcessor::new(
            seed,
            Some(loaded.config.temperature),
            Some(loaded.config.top_p),
        );

        let mut result = Vec::new();
        let mut generated_tokens: Vec<u32> = Vec::new();

        // 逐 token 生成
        for _ in 0..loaded.config.max_tokens {
            let seqlen_offset = input_ids.len().saturating_sub(1);

            // 构造输入 tensor
            let input_tensor = Tensor::new(input_ids.as_slice(), &loaded.device)?.unsqueeze(0)?;

            // 前向传播（无 KV cache，每次全量；简化实现，正确但较慢）
            let logits = loaded.model.forward(&input_tensor, seqlen_offset, None)?;

            // 取最后一个 token 的 logits
            let logits = logits.squeeze(0)?;
            let last_row = logits.get(logits.dim(0)? - 1)?;

            // 应用重复惩罚
            let last_n = loaded.config.repeat_last_n.min(generated_tokens.len());
            let penalty_tokens = &generated_tokens[generated_tokens.len() - last_n..];
            let logits = candle_transformers::utils::apply_repeat_penalty(
                &last_row,
                loaded.config.repeat_penalty,
                penalty_tokens,
            )?;

            // 采样
            let next_token = logits_processor.sample(&logits)?;

            // 检查 EOS
            let is_end = loaded.config.eos_token_id == Some(next_token);
            if is_end {
                result.push(GeneratedToken {
                    text: String::new(),
                    is_end: true,
                });
                break;
            }

            // decode token to text
            let text = loaded
                .tokenizer
                .decode(&[next_token], false)
                .map_err(|e| InferenceError::Inference(e.to_string()))?;

            result.push(GeneratedToken {
                text,
                is_end: false,
            });

            generated_tokens.push(next_token);
            input_ids.push(next_token);
        }

        Ok(result)
    }

    /// 一次性生成完整文本（非流式，便于 FFI 简化调用）。
    pub fn generate_text(&self, prompt: &str) -> Result<String, InferenceError> {
        let tokens = self.generate(prompt)?;
        let text: String = tokens
            .into_iter()
            .filter(|t| !t.is_end)
            .map(|t| t.text)
            .collect();
        Ok(text)
    }
}

impl Default for InferenceEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_creation() {
        let engine = InferenceEngine::new();
        assert!(!engine.is_loaded());
    }

    #[test]
    fn unload_without_load_is_noop() {
        let engine = InferenceEngine::new();
        engine.unload();
        assert!(!engine.is_loaded());
    }

    #[test]
    fn generate_without_load_errors() {
        let engine = InferenceEngine::new();
        let result = engine.generate("hello");
        assert!(matches!(result, Err(InferenceError::NotLoaded)));
    }

    #[test]
    fn default_config_values() {
        let config = InferenceConfig::default();
        assert_eq!(config.temperature, 0.7);
        assert_eq!(config.max_tokens, 1024);
        assert_eq!(config.repeat_penalty, 1.1);
        assert_eq!(config.repeat_last_n, 64);
        assert!(config.seed.is_none());
        assert!(config.eos_token_id.is_none());
    }

    #[test]
    fn generated_token_clone() {
        let t = GeneratedToken {
            text: "hello".into(),
            is_end: false,
        };
        let t2 = t.clone();
        assert_eq!(t.text, t2.text);
        assert_eq!(t.is_end, t2.is_end);
    }

    #[test]
    fn from_candle_error_impl() {
        let err = InferenceError::from(candle_core::Error::Msg("test".into()));
        assert!(matches!(err, InferenceError::Inference(_)));
    }
}
