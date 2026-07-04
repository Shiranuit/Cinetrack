//! Create a user account from the command line — for bootstrapping accounts when
//! self-serve sign-up is disabled (invite-only). Runs inside the backend container
//! (the DB isn't exposed to the network), reusing the app's Argon2id + `PASSWORD_PEPPER`
//! hashing, so a raw SQL insert can't substitute for it.
//!
//!   docker compose -f production.docker-compose.yaml --env-file .env.production \
//!     exec backend create_user <email> <password> [screen_name]
//!   BIN=create_user scripts/run-local.sh <email> <password> [screen_name]   # host-run (dev)
//!
//! Validates the password against the same policy as sign-up, hashes it, and inserts
//! the user with an app-generated UUIDv7 id. Reads config from env / `.env.local`.

use tracing_subscriber::EnvFilter;
use uuid::Uuid;

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
        _ => anyhow::bail!("usage: create_user <email> <password> [screen_name]"),
    };
    let email = email.trim().to_ascii_lowercase();
    if !email.contains('@') {
        anyhow::bail!("invalid email");
    }
    let screen_name = args
        .next()
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| email.split('@').next().unwrap_or("user"))
        .to_string();

    auth::password::validate(&password).map_err(|e| anyhow::anyhow!("{e}"))?;
    let hash = auth::password::hash(&password).map_err(|e| anyhow::anyhow!("{e}"))?;
    let id = Uuid::now_v7();

    let state = AppState::bootstrap(Config::from_env()?).await?;
    let res = sqlx::query(
        "INSERT INTO app.users (id, email, password_hash, screen_name) VALUES ($1, $2, $3, $4)",
    )
    .bind(id)
    .bind(&email)
    .bind(&hash)
    .bind(&screen_name)
    .execute(&state.db)
    .await;

    match res {
        Ok(_) => {
            println!("created user {email} (screen_name: {screen_name}, id: {id})");
            Ok(())
        }
        Err(sqlx::Error::Database(e)) if e.is_unique_violation() => {
            anyhow::bail!("a user with that email or screen_name already exists")
        }
        Err(e) => Err(e.into()),
    }
}
