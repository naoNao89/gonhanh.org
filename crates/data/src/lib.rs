//! Gõ Nhanh Data Library
//!
//! This crate provides Vietnamese language data, dictionaries, and
//! data structures for the input method engine.

pub mod chars;
pub mod constants;
pub mod english_dict;
pub mod keys;
pub mod telex_doubles;
pub mod vietnamese_spellcheck;
pub mod vowel;

// Re-export commonly used items for convenience
pub use chars::{get_d, mark, to_char, tone};
pub use constants::*;
pub use keys::{is_break, is_letter, is_vowel};
pub use vowel::{Modifier, Phonology, Role, Vowel};
