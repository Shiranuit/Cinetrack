//! Row types returned by the catalog domain (mapped subset of the mirrored
//! TheTVDB records; the full payload is retained in each table's `raw` column).
//!
//! `language` marks which language the returned `name`/`overview` are in after
//! translation overlay (see `catalog::translation`). It is not a stored column —
//! `#[sqlx(default)]` lets it default to `None` and we set it in code.

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct SeriesRow {
    pub id: i64,
    pub name: Option<String>,
    pub slug: Option<String>,
    pub overview: Option<String>,
    pub status: Option<String>,
    pub year: Option<i32>,
    pub runtime: Option<i32>,
    pub image_url: Option<String>,
    pub original_language: Option<String>,
    pub score: Option<f64>,
    #[sqlx(default)]
    pub language: Option<String>,
}

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct MovieRow {
    pub id: i64,
    pub name: Option<String>,
    pub slug: Option<String>,
    pub overview: Option<String>,
    pub status: Option<String>,
    pub year: Option<i32>,
    pub runtime: Option<i32>,
    pub image_url: Option<String>,
    pub original_language: Option<String>,
    pub score: Option<f64>,
    #[sqlx(default)]
    pub language: Option<String>,
}

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct EpisodeRow {
    pub id: i64,
    pub series_id: Option<i64>,
    pub season_number: Option<i32>,
    pub number: Option<i32>,
    pub absolute_number: Option<i32>,
    pub name: Option<String>,
    pub overview: Option<String>,
    pub aired: Option<String>,
    pub runtime: Option<i32>,
    pub image_url: Option<String>,
    #[sqlx(default)]
    pub language: Option<String>,
}

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct SeasonRow {
    pub id: i64,
    pub series_id: Option<i64>,
    pub number: Option<i32>,
    pub season_type: Option<String>,
    pub name: Option<String>,
    pub image_url: Option<String>,
    pub year: Option<i32>,
    #[sqlx(default)]
    pub language: Option<String>,
}

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct ArtworkRow {
    pub id: i64,
    pub series_id: Option<i64>,
    pub movie_id: Option<i64>,
    pub season_id: Option<i64>,
    pub episode_id: Option<i64>,
    pub art_type: Option<i32>,
    pub language: Option<String>,
    pub image_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub score: Option<f64>,
}
