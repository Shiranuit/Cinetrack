//! Short-lived JWT (HS256) ACCESS tokens. They carry the session id (`sid`); the
//! extractor checks the session is still active, so revocation is immediate. The
//! long-lived refresh token lives in `auth::session`, not here.

use std::time::{SystemTime, UNIX_EPOCH};

use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation, decode, encode};
use serde::{Deserialize, Serialize};

use crate::error::{AppError, AppResult};

#[derive(Serialize, Deserialize)]
pub struct Claims {
    pub sub: String, // user id
    pub sid: String, // session id
    pub exp: usize,
}

pub fn issue(secret: &str, user_id: i64, sid: &str, ttl_secs: i64) -> AppResult<String> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as i64;
    let claims = Claims {
        sub: user_id.to_string(),
        sid: sid.to_string(),
        exp: (now + ttl_secs) as usize,
    };
    encode(&Header::default(), &claims, &EncodingKey::from_secret(secret.as_bytes()))
        .map_err(|e| AppError::Other(anyhow::anyhow!("jwt encode failed: {e}")))
}

/// Returns `(user_id, session_id)` on a valid, unexpired signature.
pub fn verify(secret: &str, token: &str) -> AppResult<(i64, String)> {
    let data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )
    .map_err(|_| AppError::Unauthorized("invalid or expired token".into()))?;
    let user_id = data
        .claims
        .sub
        .parse()
        .map_err(|_| AppError::Unauthorized("invalid token subject".into()))?;
    Ok((user_id, data.claims.sid))
}
