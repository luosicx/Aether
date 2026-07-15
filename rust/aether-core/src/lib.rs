//! Aether 共享核心：安全、内存、性能敏感逻辑的 Rust 实现。
#![forbid(unsafe_code)]

pub mod sse;

pub use sse::{
    extract_content, parse_chunk, parse_with_tool_accumulation, AccumulatedToolCall, ParsedChunk,
};
