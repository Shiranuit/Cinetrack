//! Password hashing per the OWASP Password Storage Cheat Sheet.
//!
//! `Argon2::default()` is **Argon2id** (v0x13) with OWASP's recommended baseline
//! parameters — 19 MiB memory (m=19456 KiB), 2 iterations (t=2), 1 lane (p=1).
//! Argon2id is the variant OWASP recommends as it resists both GPU cracking and
//! side-channel attacks. Hashes are stored as PHC strings (salt + params embedded).

use argon2::{
    Algorithm, Argon2, Params, PasswordHash, PasswordHasher, PasswordVerifier, Version,
    password_hash::SaltString,
};
use rand_core::OsRng;

use crate::error::{AppError, AppResult};

/// Optional server-side **pepper** (a secret Argon2 key, kept OUT of the DB in
/// `PASSWORD_PEPPER`). Combined with the per-hash random salt already embedded in
/// every PHC string, a leaked `app.users` table can't be brute-forced without also
/// stealing this env secret. Unset = salt-only (backward compatible). Both hashing
/// and verification must use the same pepper.
fn pepper() -> Vec<u8> {
    std::env::var("PASSWORD_PEPPER").ok().filter(|s| !s.is_empty()).map(String::into_bytes).unwrap_or_default()
}

fn argon2(pepper: &[u8]) -> Argon2<'_> {
    if pepper.is_empty() {
        Argon2::default()
    } else {
        Argon2::new_with_secret(pepper, Algorithm::Argon2id, Version::V0x13, Params::default())
            .expect("valid Argon2 params")
    }
}

/// Minimum password length (OWASP recommends allowing long passphrases; we set a
/// firm floor and, per the product requirement, also enforce character classes).
const MIN_LEN: usize = 12;
/// Minimum estimated entropy in bits (len × log2(charset pool size)).
const MIN_ENTROPY_BITS: f64 = 60.0;

/// Validate a password against our policy. Returns `BadRequest` describing the
/// first unmet requirement.
pub fn validate(password: &str) -> AppResult<()> {
    let mut problems: Vec<&str> = Vec::new();
    if password.chars().count() < MIN_LEN {
        problems.push("at least 12 characters");
    }
    if !password.chars().any(|c| c.is_lowercase()) {
        problems.push("a lowercase letter");
    }
    if !password.chars().any(|c| c.is_uppercase()) {
        problems.push("an uppercase letter");
    }
    if !password.chars().any(|c| c.is_ascii_digit()) {
        problems.push("a number");
    }
    if !password.chars().any(|c| !c.is_alphanumeric()) {
        problems.push("a special character");
    }
    if estimated_entropy_bits(password) < MIN_ENTROPY_BITS {
        problems.push("more overall complexity");
    }

    if problems.is_empty() {
        Ok(())
    } else {
        Err(AppError::BadRequest(format!(
            "password must contain {}",
            problems.join(", ")
        )))
    }
}

/// Rough entropy estimate: `len × log2(pool)` where `pool` is the size of the
/// character classes actually used.
fn estimated_entropy_bits(password: &str) -> f64 {
    let mut pool = 0u32;
    if password.chars().any(|c| c.is_ascii_lowercase()) { pool += 26; }
    if password.chars().any(|c| c.is_ascii_uppercase()) { pool += 26; }
    if password.chars().any(|c| c.is_ascii_digit()) { pool += 10; }
    if password.chars().any(|c| c.is_ascii_punctuation() || c == ' ') { pool += 33; }
    if password.chars().any(|c| !c.is_ascii()) { pool += 100; } // unicode
    if pool == 0 { return 0.0; }
    password.chars().count() as f64 * (pool as f64).log2()
}

pub fn hash(password: &str) -> AppResult<String> {
    let pepper = pepper();
    let salt = SaltString::generate(&mut OsRng);
    argon2(&pepper)
        .hash_password(password.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| AppError::Other(anyhow::anyhow!("password hash failed: {e}")))
}

/// Constant-time verification. Returns false on any parse/verify failure.
pub fn verify(password: &str, phc_hash: &str) -> bool {
    let pepper = pepper();
    match PasswordHash::new(phc_hash) {
        Ok(parsed) => argon2(&pepper)
            .verify_password(password.as_bytes(), &parsed)
            .is_ok(),
        Err(_) => false,
    }
}
