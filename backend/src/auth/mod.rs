//! Authentication: Argon2id password hashing + JWT sessions.

mod extractor;
pub mod password;
pub mod ratelimit;
pub mod session;
pub mod token;

#[cfg(test)]
mod tests;

pub use extractor::{AuthSession, AuthUser};

use rand_core::{OsRng, RngCore};
use sha2::{Digest, Sha256};

/// A cryptographically-random 256-bit secret as hex (password-reset / invite codes).
pub fn random_token() -> String {
    let mut buf = [0u8; 32];
    OsRng.fill_bytes(&mut buf);
    hex::encode(buf)
}

/// SHA-256 hex of a token — what we STORE (never the token itself), so a DB leak
/// can't be used to reset a password or redeem an invite.
pub fn token_hash(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}
