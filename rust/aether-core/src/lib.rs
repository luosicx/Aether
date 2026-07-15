//! Aether 共享核心：安全、内存、性能敏感逻辑的 Rust 实现。
#![forbid(unsafe_code)]

pub mod chunk;
pub mod ratelimit;
pub mod redact;
pub mod sha;
pub mod sse;
pub mod token;
pub mod vector;

pub use chunk::chunk_document;
pub use ratelimit::TokenBucket;
pub use redact::redact;
pub use sha::{sha256_hex, Sha256};
pub use sse::{
    extract_content, parse_chunk, parse_with_tool_accumulation, AccumulatedToolCall, ParsedChunk,
};
pub use token::estimate_tokens;
pub use vector::{cosine_similarity_f32, cosine_similarity_f64, top_k_f32};
