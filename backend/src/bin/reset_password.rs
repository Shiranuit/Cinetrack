//! Reset a user's password from the command line (recovery when locked out — there
//! is no self-serve email reset yet).
//!
//!   cargo run --bin reset_password -- <email> <new-password>
//!   BIN=reset_password scripts/run-local.sh <email> <new-password>   # host-run
//!
//! Validates the new password against the same policy as signup, hashes it
//! (Argon2id, salted, + `PASSWORD_PEPPER` if set), and updates the user. Reads
//! config from env / `.env.local` like the server.

use tracing_subscriber::EnvFilter;

use backend::{auth, config::Config, state::AppState};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::from_filename(".env.local");
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let mut args = std::env::args().skip(1);
    let (email, password) = match (args.next(), args.next()) {
        (Some(e), Some(p)) => (e, p),
        _ => anyhow::bail!("usage: reset-password <email> <new-password>"),
    };
    let email = email.trim().to_ascii_lowercase();

    auth::password::validate(&password).map_err(|e| anyhow::anyhow!("{e}"))?;
    let hash = auth::password::hash(&password).map_err(|e| anyhow::anyhow!("{e}"))?;

    let state = AppState::bootstrap(Config::from_env()?).await?;
    let rows = sqlx::query("UPDATE app.users SET password_hash = $1, updated_at = now() WHERE email = $2")
        .bind(&hash)
        .bind(&email)
        .execute(&state.db)
        .await?
        .rows_affected();

    if rows == 0 {
        anyhow::bail!("no user with email {email}");
    }
    println!("Password reset for {email}.");
    Ok(())
}
