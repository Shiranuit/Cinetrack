//! Authentication: Argon2id password hashing + JWT sessions.

mod extractor;
pub mod password;
pub mod token;

#[cfg(test)]
mod tests;

pub use extractor::AuthUser;
