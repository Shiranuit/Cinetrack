//! JWT (HS256) session tokens.

use std::time::{SystemTime, UNIX_EPOCH};

use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation, decode, encode};
use serde::{Deserialize, Serialize};

use crate::error::{AppError, AppResult};

/// Token lifetime: 30 days.
const TTL_SECS: u64 = 30 * 24 * 3600;

#[derive(Serialize, Deserialize)]
pub struct Claims {
    pub sub: String, // user id
    pub exp: usize,
}

pub fn issue(secret: &str, user_id: i64) -> AppResult<String> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    let claims = Claims {
        sub: user_id.to_string(),
        exp: (now + TTL_SECS) as usize,
    };
    encode(&Header::default(), &claims, &EncodingKey::from_secret(secret.as_bytes()))
        .map_err(|e| AppError::Other(anyhow::anyhow!("jwt encode failed: {e}")))
}

pub fn verify(secret: &str, token: &str) -> AppResult<i64> {
    let data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )
    .map_err(|_| AppError::Unauthorized("invalid or expired token".into()))?;
    data.claims
        .sub
        .parse()
        .map_err(|_| AppError::Unauthorized("invalid token subject".into()))
}
