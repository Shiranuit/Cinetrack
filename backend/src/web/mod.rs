//! HTTP transport layer: router wiring. Handler logic lives in `handlers`.

mod handlers;
mod query;

#[cfg(test)]
mod tests;

use std::time::Instant;

use axum::{
    Router,
    extract::{DefaultBodyLimit, Request},
    http::{HeaderName, HeaderValue, Method, header},
    middleware::{self, Next},
    response::Response,
    routing::{get, post, put},
};
use tower_http::cors::{AllowOrigin, CorsLayer};

/// Global request body cap (covers avatar/cover + GDPR import uploads). Prevents
/// a handful of huge POSTs from exhausting memory. Avatars are further capped to
/// 5 MB in the handler.
const MAX_BODY_BYTES: usize = 16 * 1024 * 1024;

use crate::{config::Config, state::AppState};

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/health", get(handlers::health::health))
        // ---- auth ----
        .route("/api/auth/register", post(handlers::auth::register))
        .route("/api/auth/login", post(handlers::auth::login))
        .route("/api/auth/forgot", post(handlers::auth::forgot_password))
        .route("/api/auth/reset", post(handlers::auth::reset_password))
        .route("/api/auth/refresh", post(handlers::auth::refresh))
        .route("/api/auth/logout", post(handlers::auth::logout))
        .route("/api/invites", post(handlers::invites::create_invite).get(handlers::invites::list_invites))
        .route("/api/me", get(handlers::auth::me).delete(handlers::auth::delete_me).put(handlers::auth::update_profile))
        .route("/api/me/password", put(handlers::auth::update_password))
        .route("/api/me/security-log", get(handlers::auth::security_log))
        .route("/api/me/avatar", post(handlers::media::upload_avatar))
        .route("/api/me/cover", post(handlers::media::upload_cover))
        .route("/api/users/{id}/avatar", get(handlers::media::serve_avatar))
        .route("/api/users/{id}/cover", get(handlers::media::serve_cover))
        .route("/api/import", post(handlers::media::import_upload))
        .route("/api/import/suggestions", get(handlers::media::import_suggestions))
        .route("/api/import/suggestions/{id}/confirm", post(handlers::media::confirm_suggestion))
        .route("/api/import/suggestions/{id}/reject", post(handlers::media::reject_suggestion))
        .route("/api/stats", get(handlers::stats::get_stats))
        // ---- catalog (read-through mirror) ----
        .route("/api/search", get(handlers::search::search))
        .route("/api/discover", get(handlers::discover::discover))
        .route("/api/library/filter", get(handlers::discover::library_filter))
        .route("/api/filters", get(handlers::discover::filter_options))
        .route("/api/genres", get(handlers::discover::genres))
        .route("/api/calendar", get(handlers::discover::calendar))
        .route("/api/series/{id}", get(handlers::series::get_series))
        .route("/api/series/{id}/translations", get(handlers::series::list_translations))
        .route("/api/series/{id}/episodes", get(handlers::series::list_episodes))
        .route("/api/series/{id}/seasons", get(handlers::series::list_seasons))
        .route(
            "/api/series/{id}/seasons/{season}/watch",
            post(handlers::shows::watch_season).delete(handlers::shows::unwatch_season),
        )
        .route("/api/movies", get(handlers::movie::list_movies))
        .route("/api/movies/{id}", get(handlers::movie::get_movie))
        .route("/api/movies/{id}/relation", get(handlers::movie::movie_relation))
        .route("/api/movies/{id}/watch", post(handlers::movie::watch_movie).delete(handlers::movie::unwatch_movie))
        .route("/api/movies/{id}/favorite", post(handlers::movie::favorite_movie).delete(handlers::movie::unfavorite_movie))
        .route("/api/episodes/{id}", get(handlers::episode::get_episode))
        .route("/api/seasons/{id}", get(handlers::season::get_season))
        .route("/api/artwork/{id}", get(handlers::artwork::get_artwork))
        // ---- tracking (auth required) ----
        .route("/api/library", get(handlers::shows::library))
        .route("/api/shows", get(handlers::shows::list))
        .route("/api/shows/{id}", get(handlers::shows::get_one).delete(handlers::shows::remove))
        .route("/api/shows/{id}/follow", post(handlers::shows::follow).delete(handlers::shows::unfollow))
        .route("/api/shows/{id}/favorite", post(handlers::shows::favorite).delete(handlers::shows::unfavorite))
        .route("/api/shows/{id}/status", put(handlers::shows::set_status))
        .route("/api/shows/{id}/rating", put(handlers::shows::set_rating))
        .route("/api/shows/{id}/seen", get(handlers::shows::seen))
        .route("/api/episodes/{id}/watch", post(handlers::watch::watch).delete(handlers::watch::unwatch))
        .route("/api/users/search", get(handlers::users::search))
        .route("/api/users/following", get(handlers::users::following))
        .route("/api/users/requests", get(handlers::users::requests))
        .route("/api/users/followers", get(handlers::users::followers))
        .route("/api/users/followers/{id}", axum::routing::delete(handlers::users::remove_follower))
        .route("/api/users/requests/{id}/accept", post(handlers::users::accept_request))
        .route("/api/users/requests/{id}/reject", post(handlers::users::reject_request))
        .route("/api/me/privacy", put(handlers::users::set_privacy))
        .route("/api/me/profile-blocks", put(handlers::users::set_profile_blocks))
        .route("/api/feed", get(handlers::users::feed))
        .route("/api/users/{id}", get(handlers::users::profile))
        .route("/api/users/{id}/shows", get(handlers::users::user_shows))
        .route("/api/users/{id}/library", get(handlers::users::user_library))
        .route("/api/users/{id}/filter", get(handlers::discover::user_filter))
        .route("/api/users/{id}/movies", get(handlers::users::user_movies))
        .route("/api/users/{id}/stats", get(handlers::users::user_stats))
        .route("/api/users/{id}/follow", post(handlers::users::follow).delete(handlers::users::unfollow))
        .layer(middleware::from_fn(log_requests))
        .layer(middleware::from_fn(security_headers))
        .layer(DefaultBodyLimit::max(MAX_BODY_BYTES))
        .layer(build_cors(&state.config))
        .with_state(state)
}

/// CORS for the web app. Credentialed (the web refresh token is an httpOnly
/// cookie), so the origin can't be `*`: pin it to WEB_BASE_URL in production; in
/// dev, reflect the caller (Flutter serves the web app on a random localhost port).
fn build_cors(config: &Config) -> CorsLayer {
    let origin = if config.public_base_url.starts_with("https") {
        config
            .web_base_url
            .parse::<HeaderValue>()
            .map(|v| AllowOrigin::list([v]))
            .unwrap_or_else(|_| AllowOrigin::mirror_request())
    } else {
        AllowOrigin::mirror_request()
    };
    CorsLayer::new()
        .allow_origin(origin)
        .allow_credentials(true)
        .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE, Method::OPTIONS])
        .allow_headers([
            header::AUTHORIZATION,
            header::CONTENT_TYPE,
            HeaderName::from_static("x-use-cookie"),
        ])
}

/// Baseline hardening headers on every response.
async fn security_headers(req: Request, next: Next) -> Response {
    let mut res = next.run(req).await;
    let h = res.headers_mut();
    h.insert(header::X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff"));
    h.insert(header::REFERRER_POLICY, HeaderValue::from_static("no-referrer"));
    h.insert(header::X_FRAME_OPTIONS, HeaderValue::from_static("DENY"));
    res
}

/// Logs each request's method, path, status and latency at INFO.
async fn log_requests(req: Request, next: Next) -> Response {
    let method = req.method().clone();
    let path = req.uri().path().to_string();
    let start = Instant::now();
    let res = next.run(req).await;
    tracing::info!(
        "{method} {path} -> {} ({} ms)",
        res.status().as_u16(),
        start.elapsed().as_millis()
    );
    res
}
