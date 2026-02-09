//! Gõ Nhanh Engine Library
//!
//! This crate provides the core transformation engine for Vietnamese
//! text input processing, including syllable parsing and validation.

pub mod buffer;
pub mod engine;
pub mod input;
pub mod shortcut;
pub mod syllable;
pub mod transform;
pub mod utils;
pub mod validation;

// Re-export main types for convenience
pub use buffer::MAX as BUFFER_MAX;
pub use buffer::{Buffer, Char, MAX};
pub use engine::{Action, Engine, Result, FLAG_KEY_CONSUMED};
pub use input::{get, Method, Telex, ToneType, Vni};
pub use shortcut::{CaseMode, InputMethod, Shortcut, ShortcutTable, TriggerCondition};
pub use syllable::{parse, Syllable};
pub use transform::{ModifierType, TransformResult};
pub use utils::{
    char_to_key, collect_vowels, has_final_consonant, has_gi_initial, has_qu_initial, key_to_char,
    key_to_char_ext,
};
pub use validation::{
    is_foreign_word_pattern, is_valid, is_valid_with_foreign, is_valid_with_tones, ValidationResult,
};
