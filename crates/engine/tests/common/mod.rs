//! Common test utilities for integration tests
//!
//! These helper functions are used by all integration test files.
//! They replicate the test utilities from engine::utils (which are
//! behind #[cfg(test)] and only available for unit tests).

#![allow(dead_code)]
#![allow(unused_imports)]

use data::keys;
use engine::engine::{Action, Engine};

// KEY CONVERSION

/// Convert character to key code
pub fn char_to_key(c: char) -> u16 {
    match c.to_ascii_lowercase() {
        'a' => keys::A,
        'b' => keys::B,
        'c' => keys::C,
        'd' => keys::D,
        'e' => keys::E,
        'f' => keys::F,
        'g' => keys::G,
        'h' => keys::H,
        'i' => keys::I,
        'j' => keys::J,
        'k' => keys::K,
        'l' => keys::L,
        'm' => keys::M,
        'n' => keys::N,
        'o' => keys::O,
        'p' => keys::P,
        'q' => keys::Q,
        'r' => keys::R,
        's' => keys::S,
        't' => keys::T,
        'u' => keys::U,
        'v' => keys::V,
        'w' => keys::W,
        'x' => keys::X,
        'y' => keys::Y,
        'z' => keys::Z,
        '0' => keys::N0,
        '1' => keys::N1,
        '2' => keys::N2,
        '3' => keys::N3,
        '4' => keys::N4,
        '5' => keys::N5,
        '6' => keys::N6,
        '7' => keys::N7,
        '8' => keys::N8,
        '9' => keys::N9,
        '.' => keys::DOT,
        ',' => keys::COMMA,
        ';' => keys::SEMICOLON,
        ':' => keys::SEMICOLON,
        '\'' => keys::QUOTE,
        '"' => keys::QUOTE,
        '-' => keys::MINUS,
        '=' => keys::EQUAL,
        '[' => keys::LBRACKET,
        ']' => keys::RBRACKET,
        '\\' => keys::BACKSLASH,
        '/' => keys::SLASH,
        '`' => keys::BACKQUOTE,
        '<' => keys::DELETE,
        ' ' => keys::SPACE,
        '\x1b' => keys::ESC,
        '@' => keys::N2,
        '!' => keys::N1,
        '#' => keys::N3,
        '$' => keys::N4,
        '%' => keys::N5,
        '^' => keys::N6,
        '&' => keys::N7,
        '*' => keys::N8,
        '(' => keys::N9,
        ')' => keys::N0,
        '_' => keys::MINUS,
        '+' => keys::EQUAL,
        _ => 255,
    }
}

/// Convert string to key codes
pub fn keys_from_str(s: &str) -> Vec<u16> {
    s.chars().map(char_to_key).filter(|&k| k != 255).collect()
}

/// Simulate typing, returns screen output
pub fn type_word(e: &mut Engine, input: &str) -> String {
    let mut screen = String::new();
    for c in input.chars() {
        let (key, shift) = match c {
            '@' => (keys::N2, true),
            '!' => (keys::N1, true),
            '#' => (keys::N3, true),
            '$' => (keys::N4, true),
            '%' => (keys::N5, true),
            '^' => (keys::N6, true),
            '&' => (keys::N7, true),
            '*' => (keys::N8, true),
            '(' => (keys::N9, true),
            ')' => (keys::N0, true),
            '_' => (keys::MINUS, true),
            '+' => (keys::EQUAL, true),
            ':' => (keys::SEMICOLON, true),
            '"' => (keys::QUOTE, true),
            '>' => (keys::DOT, true),
            '?' => (keys::SLASH, true),
            '|' => (keys::BACKSLASH, true),
            '{' => (keys::LBRACKET, true),
            '}' => (keys::RBRACKET, true),
            '~' => (keys::BACKQUOTE, true),
            _ => (char_to_key(c), false),
        };
        let is_caps = c.is_uppercase();

        if key == keys::DELETE {
            let r = e.on_key_ext(key, false, false, false);
            if r.action == Action::Send as u8 {
                for _ in 0..r.backspace {
                    screen.pop();
                }
                for i in 0..r.count as usize {
                    if let Some(ch) = char::from_u32(r.chars[i]) {
                        screen.push(ch);
                    }
                }
            } else {
                screen.pop();
            }
            continue;
        }

        if key == keys::ESC {
            let r = e.on_key_ext(key, false, false, false);
            if r.action == Action::Send as u8 {
                for _ in 0..r.backspace {
                    screen.pop();
                }
                for i in 0..r.count as usize {
                    if let Some(ch) = char::from_u32(r.chars[i]) {
                        screen.push(ch);
                    }
                }
            }
            continue;
        }

        if key == keys::SPACE {
            let r = e.on_key_ext(key, false, false, false);
            if r.action == Action::Send as u8 {
                for _ in 0..r.backspace {
                    screen.pop();
                }
                for i in 0..r.count as usize {
                    if let Some(ch) = char::from_u32(r.chars[i]) {
                        screen.push(ch);
                    }
                }
            } else {
                screen.push(' ');
            }
            continue;
        }

        let r = e.on_key_ext(key, is_caps, false, shift);
        if r.action == Action::Send as u8 {
            for _ in 0..r.backspace {
                screen.pop();
            }
            for i in 0..r.count as usize {
                if let Some(ch) = char::from_u32(r.chars[i]) {
                    screen.push(ch);
                }
            }
            if keys::is_break_ext(key, shift) && !r.key_consumed() {
                screen.push(c);
            }
        } else {
            screen.push(c);
        }
    }
    screen
}

/// Run Telex test cases
pub fn telex(cases: &[(&str, &str)]) {
    for (input, expected) in cases {
        let mut e = Engine::new();
        let result = type_word(&mut e, input);
        assert_eq!(result, *expected, "[Telex] '{}' → '{}'", input, result);
    }
}

/// Run Telex test cases with English auto-restore enabled
pub fn telex_auto_restore(cases: &[(&str, &str)]) {
    for (input, expected) in cases {
        let mut e = Engine::new();
        e.set_english_auto_restore(true);
        let result = type_word(&mut e, input);
        assert_eq!(
            result, *expected,
            "[Telex AutoRestore] '{}' → '{}'",
            input, result
        );
    }
}

/// Run Telex test cases with auto-capitalize enabled
pub fn telex_auto_capitalize(cases: &[(&str, &str)]) {
    for (input, expected) in cases {
        let mut e = Engine::new();
        e.set_auto_capitalize(true);
        let result = type_word(&mut e, input);
        assert_eq!(
            result, *expected,
            "[Telex AutoCapitalize] '{}' → '{}'",
            input, result
        );
    }
}

/// Run VNI test cases
pub fn vni(cases: &[(&str, &str)]) {
    for (input, expected) in cases {
        let mut e = Engine::new();
        e.set_method(1);
        let result = type_word(&mut e, input);
        assert_eq!(result, *expected, "[VNI] '{}' → '{}'", input, result);
    }
}

/// Run Telex test cases with traditional tone placement (hòa, thúy style)
pub fn telex_traditional(cases: &[(&str, &str)]) {
    for (input, expected) in cases {
        let mut e = Engine::new();
        e.set_modern_tone(false);
        let result = type_word(&mut e, input);
        assert_eq!(
            result, *expected,
            "[Telex Traditional] '{}' → '{}'",
            input, result
        );
    }
}

/// Run VNI test cases with traditional tone placement (hòa, thúy style)
pub fn vni_traditional(cases: &[(&str, &str)]) {
    for (input, expected) in cases {
        let mut e = Engine::new();
        e.set_method(1);
        e.set_modern_tone(false);
        let result = type_word(&mut e, input);
        assert_eq!(
            result, *expected,
            "[VNI Traditional] '{}' → '{}'",
            input, result
        );
    }
}

// TEST RUNNERS - Extended helpers for integration tests

/// Input method type
#[derive(Clone, Copy, Debug)]
pub enum Method {
    Telex,
    Vni,
}

/// Run test cases with method
pub fn run(method: Method, cases: &[(&str, &str)]) {
    match method {
        Method::Telex => telex(cases),
        Method::Vni => vni(cases),
    }
}

/// Run same cases for both methods (with different inputs)
pub fn both(telex_cases: &[(&str, &str)], vni_cases: &[(&str, &str)]) {
    telex(telex_cases);
    vni(vni_cases);
}

// ENGINE STATE HELPERS

pub fn engine_telex() -> Engine {
    Engine::new()
}

pub fn engine_vni() -> Engine {
    let mut e = Engine::new();
    e.set_method(1);
    e
}

// ASSERTION HELPERS

/// Assert engine action
pub fn assert_action(e: &mut Engine, key: u16, caps: bool, ctrl: bool, expected: Action) {
    let r = e.on_key(key, caps, ctrl);
    assert_eq!(
        r.action, expected as u8,
        "Expected {:?} for key {}",
        expected, key
    );
}

/// Assert pass-through (no transformation)
pub fn assert_passthrough(e: &mut Engine, key: u16) {
    assert_action(e, key, false, false, Action::None);
}

/// Assert transformation happens
pub fn assert_transforms(e: &mut Engine, key: u16) {
    assert_action(e, key, false, false, Action::Send);
}
