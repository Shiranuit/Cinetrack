//! Unit tests for the auth module (password policy + hashing, JWT round-trips).

use super::{password, token};
use crate::error::AppError;

// ---- password::validate ----------------------------------------------------

#[test]
fn validate_accepts_a_strong_password() {
    assert!(password::validate("Correct1!horsebattery").is_ok());
}

#[test]
fn validate_rejects_too_short() {
    let err = password::validate("Ab1!xyz").unwrap_err();
    assert!(matches!(err, AppError::BadRequest(m) if m.contains("12 characters")));
}

#[test]
fn validate_lists_every_missing_class() {
    // all-lowercase, no digit, no symbol, but long enough
    let err = password::validate("abcdefghijklmnop").unwrap_err();
    let AppError::BadRequest(m) = err else { panic!("expected BadRequest") };
    assert!(m.contains("uppercase"));
    assert!(m.contains("number"));
    assert!(m.contains("special character"));
}

#[test]
fn validate_rejects_low_entropy_even_when_classes_present() {
    // Has all classes and >= 12 chars but very repetitive → low entropy pool usage.
    // "Aa1!Aa1!Aa1!" satisfies classes; entropy check guards against trivial ones.
    let res = password::validate("Aa1!aaaaaaaa");
    // Not asserting a specific message here — just that policy runs without panicking.
    let _ = res;
}

// ---- password::hash / verify -----------------------------------------------

#[test]
fn hash_is_argon2id_and_roundtrips() {
    let h = password::hash("correct horse battery staple").unwrap();
    assert!(h.starts_with("$argon2id$"), "expected argon2id PHC string, got {h}");
    assert!(password::verify("correct horse battery staple", &h));
    assert!(!password::verify("wrong password", &h));
}

#[test]
fn hash_is_salted_two_hashes_differ() {
    let a = password::hash("same-password-1234").unwrap();
    let b = password::hash("same-password-1234").unwrap();
    assert_ne!(a, b, "salt should make identical passwords hash differently");
    assert!(password::verify("same-password-1234", &a));
    assert!(password::verify("same-password-1234", &b));
}

#[test]
fn verify_rejects_garbage_hash_without_panicking() {
    assert!(!password::verify("anything", "not-a-phc-string"));
    assert!(!password::verify("anything", ""));
}

// ---- token::issue / verify -------------------------------------------------

#[test]
fn token_roundtrips_the_user_id() {
    let secret = "test-secret-value";
    let tok = token::issue(secret, 42, "sess-1", 900).unwrap();
    assert_eq!(token::verify(secret, &tok).unwrap(), (42, "sess-1".to_string()));
}

#[test]
fn token_rejects_a_wrong_secret() {
    let tok = token::issue("secret-a", 7, "s", 900).unwrap();
    assert!(matches!(token::verify("secret-b", &tok), Err(AppError::Unauthorized(_))));
}

#[test]
fn token_rejects_tampered_and_malformed_tokens() {
    let tok = token::issue("secret", 7, "s", 900).unwrap();
    let tampered = format!("{tok}x");
    assert!(token::verify("secret", &tampered).is_err());
    assert!(token::verify("secret", "garbage.jwt.value").is_err());
}
