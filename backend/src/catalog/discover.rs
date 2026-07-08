//! Advanced browse/filter over our mirrored catalog — shared by Discover and the
//! Library filter. Filters run on the normalized facet tables (genres, tags,
//! companies) + indexed scalar columns (year, runtime, score, status, season/
//! episode counts) rather than scanning `raw` JSONB. Set `library_user` to scope
//! the results to one user's tracked shows.

use uuid::Uuid;
use std::collections::HashSet;

use serde_json::Value;
use sqlx::{Postgres, QueryBuilder};

use crate::{
    catalog::{as_i32, as_i64, image_url, store_stub, SearchResult},
    error::AppResult,
    state::AppState,
};

/// Enough local browse hits before hybrid mode bothers TheTVDB.
const MIN_LOCAL: usize = 20;

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct Genre {
    pub id: i64,
    pub name: String,
}

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct Tag {
    pub id: i64,
    pub name: String,
    pub category: Option<String>,
}

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct Company {
    pub id: i64,
    pub name: String,
}

/// Advanced filters. Empty vecs / `None` mean "no constraint".
#[derive(Debug, Default)]
pub struct Filters {
    /// Optional name substring (title/aliases); combined with the facet filters.
    pub query: Option<String>,
    pub kind: String, // "series" | "movie" | "anime"
    pub genres_include: Vec<i64>,
    pub genres_exclude: Vec<i64>,
    pub tags_include: Vec<i64>,
    pub tags_exclude: Vec<i64>,
    pub networks: Vec<i64>, // any-of
    pub studios: Vec<i64>,  // any-of
    pub statuses: Vec<String>, // any-of, e.g. Continuing / Ended / Upcoming
    pub year_min: Option<i32>,
    pub year_max: Option<i32>,
    pub runtime_min: Option<i32>,
    pub runtime_max: Option<i32>,
    pub seasons_min: Option<i32>,
    pub seasons_max: Option<i32>,
    pub episodes_min: Option<i32>,
    pub episodes_max: Option<i32>,
    pub score_min: Option<f64>,
    pub original_languages: Vec<String>, // any-of (e.g. "jpn", "eng")
    pub original_countries: Vec<String>, // any-of (e.g. "jpn", "usa")
    pub sort: String,                    // popularity | year | name | runtime | seasons | episodes
    pub sort_desc: bool,                 // sort direction (false = ascending)
    pub limit: i64,
    pub offset: i64,
    /// When set, restrict to this user's tracked (non-unavailable) shows.
    pub library_user: Option<Uuid>,
    /// When set, EXCLUDE this user's tracked shows (Discover: show new shows only).
    pub exclude_user: Option<Uuid>,
    /// The current viewer, used by the "my_rating" sort to order by THEIR own rating
    /// (as opposed to the cross-user average used by the "rating" sort).
    pub viewer: Option<Uuid>,
    /// Library-only: restrict to favorited shows.
    pub favorites_only: bool,
}

pub async fn search_db(state: &AppState, f: &Filters, langs: &[String]) -> AppResult<Vec<SearchResult>> {
    let is_movie = f.kind == "movie";
    let is_anime = f.kind == "anime";
    let (table, etype, result_kind) =
        if is_movie { ("catalog.movie", "movie", "movie") } else { ("catalog.series", "series", "series") };

    let mut qb: QueryBuilder<Postgres> = QueryBuilder::new("SELECT x.id, ");
    qb.push("COALESCE((SELECT tr.name FROM catalog.translation tr WHERE tr.entity_type = ");
    qb.push_bind(etype);
    qb.push(" AND tr.entity_id = x.id AND tr.name IS NOT NULL AND tr.language = ANY(");
    qb.push_bind(langs.to_vec());
    qb.push(") ORDER BY array_position(");
    qb.push_bind(langs.to_vec());
    qb.push(", tr.language) LIMIT 1), x.name) AS name, x.year, x.image_url, x.overview");
    // Does the viewer already track this title? Lets Discover mark library shows.
    match f.viewer {
        Some(viewer) if is_movie => {
            qb.push(", EXISTS (SELECT 1 FROM app.user_movie um WHERE um.movie_id = x.id AND um.user_id = ");
            qb.push_bind(viewer);
            qb.push(") AS in_library");
        }
        Some(viewer) => {
            qb.push(", EXISTS (SELECT 1 FROM app.user_show us WHERE us.series_id = x.id AND us.user_id = ");
            qb.push_bind(viewer);
            qb.push(" AND NOT us.unavailable) AS in_library");
        }
        None => {
            qb.push(", false AS in_library");
        }
    }
    qb.push(format!(" FROM {table} x"));

    // Library scope: only shows this user tracks.
    if let Some(uid) = f.library_user {
        qb.push(" JOIN app.user_show us ON us.series_id = x.id AND NOT us.unavailable AND us.user_id = ");
        qb.push_bind(uid);
    }
    qb.push(" WHERE NOT x.deleted");

    // Library-only: favorites.
    if f.library_user.is_some() && f.favorites_only {
        qb.push(" AND us.is_favorited");
    }

    // Discover: hide shows the user already tracks (the "In my library" toggle off).
    // Mirror the `in_library` flag exactly, so what gets hidden is precisely what
    // would otherwise show the marker: movies use user_movie, series use user_show
    // (excluding unavailable ones).
    if let Some(uid) = f.exclude_user {
        if is_movie {
            qb.push(" AND NOT EXISTS (SELECT 1 FROM app.user_movie ux WHERE ux.user_id = ");
            qb.push_bind(uid);
            qb.push(" AND ux.movie_id = x.id)");
        } else {
            qb.push(" AND NOT EXISTS (SELECT 1 FROM app.user_show ux WHERE ux.user_id = ");
            qb.push_bind(uid);
            qb.push(" AND ux.series_id = x.id AND NOT ux.unavailable)");
        }
    }

    // Facet filters apply to series/anime only (movies have no facet tables yet).
    if !is_movie {
        if is_anime {
            qb.push(" AND x.original_language IN ('jpn','ja')");
        }
        // genres: must have ALL included, NONE excluded.
        if !f.genres_include.is_empty() {
            qb.push(" AND NOT EXISTS (SELECT 1 FROM unnest(");
            qb.push_bind(f.genres_include.clone());
            qb.push("::bigint[]) gid WHERE NOT EXISTS (SELECT 1 FROM catalog.series_genre sg WHERE sg.series_id = x.id AND sg.genre_id = gid))");
        }
        if !f.genres_exclude.is_empty() {
            qb.push(" AND NOT EXISTS (SELECT 1 FROM catalog.series_genre sg WHERE sg.series_id = x.id AND sg.genre_id = ANY(");
            qb.push_bind(f.genres_exclude.clone());
            qb.push("::bigint[]))");
        }
        // tags (themes): same ALL/NONE semantics.
        if !f.tags_include.is_empty() {
            qb.push(" AND NOT EXISTS (SELECT 1 FROM unnest(");
            qb.push_bind(f.tags_include.clone());
            qb.push("::bigint[]) tid WHERE NOT EXISTS (SELECT 1 FROM catalog.series_tag st WHERE st.series_id = x.id AND st.tag_id = tid))");
        }
        if !f.tags_exclude.is_empty() {
            qb.push(" AND NOT EXISTS (SELECT 1 FROM catalog.series_tag st WHERE st.series_id = x.id AND st.tag_id = ANY(");
            qb.push_bind(f.tags_exclude.clone());
            qb.push("::bigint[]))");
        }
        // networks / studios: any-of.
        if !f.networks.is_empty() {
            qb.push(" AND EXISTS (SELECT 1 FROM catalog.series_company sc WHERE sc.series_id = x.id AND sc.kind = 'Network' AND sc.company_id = ANY(");
            qb.push_bind(f.networks.clone());
            qb.push("::bigint[]))");
        }
        if !f.studios.is_empty() {
            qb.push(" AND EXISTS (SELECT 1 FROM catalog.series_company sc WHERE sc.series_id = x.id AND sc.kind = 'Studio' AND sc.company_id = ANY(");
            qb.push_bind(f.studios.clone());
            qb.push("::bigint[]))");
        }
        if let Some(v) = f.seasons_min {
            qb.push(" AND x.season_count >= ").push_bind(v);
        }
        if let Some(v) = f.seasons_max {
            qb.push(" AND x.season_count <= ").push_bind(v);
        }
        if let Some(v) = f.episodes_min {
            qb.push(" AND x.episode_count >= ").push_bind(v);
        }
        if let Some(v) = f.episodes_max {
            qb.push(" AND x.episode_count <= ").push_bind(v);
        }
    }

    // Scalar filters (series + movies).
    if !f.statuses.is_empty() {
        qb.push(" AND x.status = ANY(").push_bind(f.statuses.clone()).push(")");
    }
    if let Some(v) = f.year_min {
        qb.push(" AND x.year >= ").push_bind(v);
    }
    if let Some(v) = f.year_max {
        qb.push(" AND x.year <= ").push_bind(v);
    }
    if let Some(v) = f.runtime_min {
        qb.push(" AND x.runtime >= ").push_bind(v);
    }
    if let Some(v) = f.runtime_max {
        qb.push(" AND x.runtime <= ").push_bind(v);
    }
    if let Some(v) = f.score_min {
        qb.push(" AND x.score >= ").push_bind(v);
    }
    // Origin facets (series + movies both carry these columns).
    if !f.original_languages.is_empty() {
        qb.push(" AND x.original_language = ANY(").push_bind(f.original_languages.clone()).push(")");
    }
    if !f.original_countries.is_empty() {
        qb.push(" AND x.original_country = ANY(").push_bind(f.original_countries.clone()).push(")");
    }

    // Name search: substring match on the base name OR any TRANSLATED name / alias, so
    // a show is found by the localized title the user actually sees, not only its
    // original-language form (e.g. a show shown as "Hanamonogatari" whose base name is
    // Japanese with no aliases). Translations/aliases are matched only in the languages
    // that matter to this user: their OWN languages PLUS the show's own original
    // language (so a Japanese show is still findable by its Japanese title even when the
    // user only reads eng/fra), never all ~113. Both sides hit their pg_trgm GIN index
    // (series/movie _name_trgm / translation_search_idx); a UNION of indexed lookups
    // stays fast, whereas an OR couldn't use them.
    if let Some(query) = f.query.as_deref() {
        let like = format!("%{query}%");
        if f.library_user.is_some() {
            // Library: `x` is already restricted to the user's (few hundred) shows by
            // the JOIN above, so OR EXISTS on their translations/aliases is cheap
            // (single-digit ms) even for common substrings that would match huge slices
            // of the catalog-wide translation/alias tables. `x.original_language` is on
            // the base row already, so the original-language branch needs no extra join.
            qb.push(" AND (x.name ILIKE ").push_bind(like.clone());
            qb.push(" OR EXISTS (SELECT 1 FROM catalog.translation tr WHERE tr.entity_type = ");
            qb.push_bind(etype);
            qb.push(" AND tr.entity_id = x.id AND (tr.language = ANY(").push_bind(langs.to_vec());
            qb.push(") OR tr.language = x.original_language) AND tr.name ILIKE ").push_bind(like.clone());
            qb.push(") OR EXISTS (SELECT 1 FROM catalog.entity_alias ea WHERE ea.entity_type = ");
            qb.push_bind(etype);
            qb.push(" AND ea.entity_id = x.id AND (ea.language = ANY(").push_bind(langs.to_vec());
            qb.push(") OR ea.language = x.original_language) AND ea.name ILIKE ").push_bind(like);
            qb.push("))");
        } else {
            // Discover (catalog-wide): a UNION of pg_trgm GIN-indexed lookups over the
            // base name, translated titles, and aliases. The translation/alias branches
            // join back to the base table for its `original_language`, so a match counts
            // when the row's language is one of the user's OR the show's own original.
            qb.push(" AND x.id IN (SELECT id FROM ");
            qb.push(table);
            qb.push(" WHERE name ILIKE ").push_bind(like.clone());
            qb.push(" UNION SELECT t.entity_id FROM catalog.translation t JOIN ");
            qb.push(table);
            qb.push(" s ON s.id = t.entity_id WHERE t.entity_type = ");
            qb.push_bind(etype);
            qb.push(" AND (t.language = ANY(").push_bind(langs.to_vec());
            qb.push(") OR t.language = s.original_language) AND t.name ILIKE ").push_bind(like.clone());
            qb.push(" UNION SELECT a.entity_id FROM catalog.entity_alias a JOIN ");
            qb.push(table);
            qb.push(" s2 ON s2.id = a.entity_id WHERE a.entity_type = ");
            qb.push_bind(etype);
            qb.push(" AND (a.language = ANY(").push_bind(langs.to_vec());
            qb.push(") OR a.language = s2.original_language) AND a.name ILIKE ").push_bind(like);
            qb.push(")");
        }
    }

    let dir = if f.sort_desc { "DESC" } else { "ASC" };
    // "my_rating" orders by the viewer's OWN note (a bound uuid, so it can't be a
    // plain &str). Series-only, since movies have no per-user rating.
    if f.sort == "my_rating" && !is_movie && f.viewer.is_some() {
        qb.push(" ORDER BY (SELECT us2.rating FROM app.user_show us2 \
                   WHERE us2.series_id = x.id AND us2.user_id = ");
        qb.push_bind(f.viewer.unwrap());
        qb.push(format!(") {dir} NULLS LAST, x.name"));
    } else {
        // Column to sort by; the direction is applied uniformly below.
        let col = match f.sort.as_str() {
            "year" => "x.year",
            "name" => "x.name",
            "runtime" => "x.runtime",
            "updated" => "x.last_updated",
            "seasons" if !is_movie => "x.season_count",
            "episodes" if !is_movie => "x.episode_count",
            // "rating" is the cross-user average everywhere ("my_rating" is yours).
            "rating" if !is_movie => {
                "(SELECT avg(rating) FROM app.user_show WHERE series_id = x.id AND rating IS NOT NULL)"
            }
            _ => "x.score",
        };
        qb.push(format!(" ORDER BY {col} {dir} NULLS LAST, x.name"));
    }
    // `id` as a final tiebreaker → a total, stable order so offset paging can't
    // repeat or skip rows across pages.
    qb.push(", x.id DESC");
    qb.push(" LIMIT ").push_bind(f.limit.clamp(1, 200));
    if f.offset > 0 {
        qb.push(" OFFSET ").push_bind(f.offset);
    }

    let rows = qb
        .build_query_as::<(i64, Option<String>, Option<i32>, Option<String>, Option<String>, bool)>()
        .fetch_all(&state.db)
        .await?;

    Ok(rows
        .into_iter()
        .map(|(id, name, year, image_url, overview, in_library)| SearchResult {
            tvdb_id: Some(id),
            kind: Some(result_kind.to_string()),
            name,
            year,
            image_url,
            overview,
            in_library,
        })
        .collect())
}

// ---- lookups for the filter UI (only facets present in the mirror) -----------

/// Genres actually used by mirrored series (optionally only within one user's
/// library). Falls back to TheTVDB's full list when the mirror is empty.
pub async fn genres_in_catalog(state: &AppState, library_user: Option<Uuid>) -> AppResult<Vec<Genre>> {
    let rows: Vec<(i64, String)> = match library_user {
        Some(uid) => sqlx::query_as(
            "SELECT DISTINCT g.id, g.name FROM catalog.genre g \
             JOIN catalog.series_genre sg ON sg.genre_id = g.id \
             JOIN app.user_show us ON us.series_id = sg.series_id AND us.user_id = $1 AND NOT us.unavailable \
             ORDER BY g.name",
        )
        .bind(uid)
        .fetch_all(&state.db)
        .await?,
        None => sqlx::query_as(
            "SELECT DISTINCT g.id, g.name FROM catalog.genre g \
             JOIN catalog.series_genre sg ON sg.genre_id = g.id ORDER BY g.name",
        )
        .fetch_all(&state.db)
        .await?,
    };
    if !rows.is_empty() {
        return Ok(rows.into_iter().map(|(id, name)| Genre { id, name }).collect());
    }
    genres(state).await
}

/// Themes/keywords present in the mirror (optionally scoped to a user's library).
pub async fn tags_in_catalog(state: &AppState, library_user: Option<Uuid>) -> AppResult<Vec<Tag>> {
    let rows = match library_user {
        Some(uid) => sqlx::query_as::<_, Tag>(
            "SELECT DISTINCT t.id, t.name, t.category FROM catalog.tag t \
             JOIN catalog.series_tag st ON st.tag_id = t.id \
             JOIN app.user_show us ON us.series_id = st.series_id AND us.user_id = $1 AND NOT us.unavailable \
             ORDER BY t.category NULLS LAST, t.name",
        )
        .bind(uid)
        .fetch_all(&state.db)
        .await?,
        None => sqlx::query_as::<_, Tag>(
            "SELECT DISTINCT t.id, t.name, t.category FROM catalog.tag t \
             JOIN catalog.series_tag st ON st.tag_id = t.id ORDER BY t.category NULLS LAST, t.name",
        )
        .fetch_all(&state.db)
        .await?,
    };
    Ok(rows)
}

/// Companies of a `kind` (`Network` | `Studio`) present in the mirror.
pub async fn companies_in_catalog(
    state: &AppState,
    kind: &str,
    library_user: Option<Uuid>,
) -> AppResult<Vec<Company>> {
    let rows = match library_user {
        Some(uid) => sqlx::query_as::<_, Company>(
            "SELECT DISTINCT c.id, c.name FROM catalog.company c \
             JOIN catalog.series_company sc ON sc.company_id = c.id AND sc.kind = $2 \
             JOIN app.user_show us ON us.series_id = sc.series_id AND us.user_id = $1 AND NOT us.unavailable \
             ORDER BY c.name",
        )
        .bind(uid)
        .bind(kind)
        .fetch_all(&state.db)
        .await?,
        None => sqlx::query_as::<_, Company>(
            "SELECT DISTINCT c.id, c.name FROM catalog.company c \
             JOIN catalog.series_company sc ON sc.company_id = c.id AND sc.kind = $1 ORDER BY c.name",
        )
        .bind(kind)
        .fetch_all(&state.db)
        .await?,
    };
    Ok(rows)
}

/// Series statuses for the filter — the canonical TheTVDB set (so "Upcoming" is
/// always offered for discovering not-yet-started shows) unioned with any others
/// actually present in the mirror.
/// Distinct origin values (language or country) across series + movies, most
/// common first, optionally scoped to a user's library. `column` is a fixed
/// allow-listed identifier.
async fn origin_values(state: &AppState, column: &str, library_user: Option<Uuid>) -> AppResult<Vec<String>> {
    let sql = match library_user {
        Some(_) => format!(
            "SELECT v, count(*) c FROM ( \
               SELECT s.{column} v FROM catalog.series s JOIN app.user_show us ON us.series_id = s.id \
                 AND us.user_id = $1 AND NOT us.unavailable WHERE s.{column} IS NOT NULL \
               UNION ALL \
               SELECT m.{column} FROM catalog.movie m JOIN app.user_movie um ON um.movie_id = m.id \
                 AND um.user_id = $1 WHERE m.{column} IS NOT NULL \
             ) t GROUP BY v ORDER BY c DESC, v LIMIT 100"
        ),
        None => format!(
            "SELECT v, count(*) c FROM ( \
               SELECT {column} v FROM catalog.series WHERE {column} IS NOT NULL AND NOT deleted \
               UNION ALL SELECT {column} FROM catalog.movie WHERE {column} IS NOT NULL AND NOT deleted \
             ) t GROUP BY v ORDER BY c DESC, v LIMIT 100"
        ),
    };
    let mut q = sqlx::query_as::<_, (String, i64)>(&sql);
    if let Some(uid) = library_user {
        q = q.bind(uid);
    }
    Ok(q.fetch_all(&state.db).await?.into_iter().map(|(v, _)| v).collect())
}

pub async fn languages_in_catalog(state: &AppState, library_user: Option<Uuid>) -> AppResult<Vec<String>> {
    origin_values(state, "original_language", library_user).await
}

pub async fn countries_in_catalog(state: &AppState, library_user: Option<Uuid>) -> AppResult<Vec<String>> {
    origin_values(state, "original_country", library_user).await
}

pub async fn statuses_in_catalog(state: &AppState) -> AppResult<Vec<String>> {
    let rows: Vec<(String,)> =
        sqlx::query_as("SELECT DISTINCT status FROM catalog.series WHERE status IS NOT NULL")
            .fetch_all(&state.db)
            .await?;
    let mut set: std::collections::BTreeSet<String> =
        ["Continuing", "Upcoming", "Ended"].iter().map(|s| s.to_string()).collect();
    set.extend(rows.into_iter().map(|(s,)| s));
    Ok(set.into_iter().collect())
}

// ---- popular browse (local-first, mode-aware) --------------------------------

/// Browse popular titles. Local-first over the mirror, honoring `CATALOG_MODE`:
/// mirror = local only; proxy = TheTVDB (results stored); hybrid = local, topped
/// up from TheTVDB when thin (results stored so the mirror self-heals).
pub async fn popular(
    state: &AppState,
    kind: &str,
    genre: Option<i64>,
    sort: &str,
    year: Option<i32>,
) -> AppResult<Vec<SearchResult>> {
    let mode = state.config.catalog_mode;

    if mode == crate::config::CatalogMode::Proxy {
        return popular_remote(state, kind, genre, sort, year).await;
    }

    let local = popular_local(state, kind, genre, sort, year).await?;
    if mode == crate::config::CatalogMode::Mirror || local.len() >= MIN_LOCAL {
        return Ok(local);
    }

    // Hybrid + thin local → top up from TheTVDB (which stores what it returns).
    match popular_remote(state, kind, genre, sort, year).await {
        Ok(remote) => {
            let seen: HashSet<i64> = local.iter().filter_map(|r| r.tvdb_id).collect();
            let mut merged = local;
            for r in remote {
                if r.tvdb_id.is_none_or(|id| !seen.contains(&id)) {
                    merged.push(r);
                }
            }
            Ok(merged)
        }
        Err(e) => {
            tracing::warn!("hybrid popular: remote unavailable, serving local only: {e}");
            Ok(local)
        }
    }
}

/// Popular browse straight from the mirror (score / recency / name ordered).
async fn popular_local(
    state: &AppState,
    kind: &str,
    genre: Option<i64>,
    sort: &str,
    year: Option<i32>,
) -> AppResult<Vec<SearchResult>> {
    let is_movie = kind == "movie";
    let (table, result_kind) = if is_movie { ("catalog.movie", "movie") } else { ("catalog.series", "series") };

    let mut qb: QueryBuilder<Postgres> = QueryBuilder::new("SELECT x.id, x.name, x.year, x.image_url, x.overview FROM ");
    qb.push(table);
    qb.push(" x WHERE NOT x.deleted");
    if let Some(y) = year {
        qb.push(" AND x.year = ").push_bind(y);
    }
    // Genre facets exist for series only (movies have no facet tables yet).
    if let Some(g) = genre.filter(|_| !is_movie) {
        qb.push(" AND EXISTS (SELECT 1 FROM catalog.series_genre sg WHERE sg.series_id = x.id AND sg.genre_id = ")
            .push_bind(g)
            .push(")");
    }
    qb.push(match sort {
        "name" => " ORDER BY x.name ASC NULLS LAST",
        "firstAired" => " ORDER BY x.year DESC NULLS LAST, x.name",
        _ => " ORDER BY x.score DESC NULLS LAST, x.name",
    });
    qb.push(" LIMIT 50");

    let rows = qb
        .build_query_as::<(i64, Option<String>, Option<i32>, Option<String>, Option<String>)>()
        .fetch_all(&state.db)
        .await?;
    Ok(rows
        .into_iter()
        .map(|(id, name, year, image_url, overview)| SearchResult {
            tvdb_id: Some(id),
            kind: Some(result_kind.to_string()),
            name,
            year,
            image_url,
            overview,
            in_library: false,
        })
        .collect())
}

/// Browse via TheTVDB's live filter, storing every hit as a mirror stub.
async fn popular_remote(
    state: &AppState,
    kind: &str,
    genre: Option<i64>,
    sort: &str,
    year: Option<i32>,
) -> AppResult<Vec<SearchResult>> {
    let sort = match sort {
        "firstAired" | "name" => sort,
        _ => "score",
    };
    let genre_s = genre.map(|g| g.to_string());
    let year_s = year.map(|y| y.to_string());
    let mut params = vec![("sort", sort), ("sortType", "desc"), ("lang", "eng")];
    if let Some(g) = genre_s.as_deref() {
        params.push(("genre", g));
    }
    if let Some(y) = year_s.as_deref() {
        params.push(("year", y));
    }

    let is_movie = kind == "movie";
    let data = if is_movie {
        state.tvdb.movies_filter(&params).await?
    } else {
        state.tvdb.series_filter(&params).await?
    };
    let (table, result_kind) = if is_movie { ("catalog.movie", "movie") } else { ("catalog.series", "series") };

    let mut out = Vec::new();
    for r in data.as_array().into_iter().flatten() {
        let Some(id) = as_i64(&r["id"]) else { continue };
        let year = as_i32(&r["year"]);
        let img = image_url(&r["image"]);
        // Persist so the title is locally browsable next time (full-local goal).
        let _ = store_stub(state, table, id, r["name"].as_str(), img.as_deref(), year, r["originalLanguage"].as_str(), &crate::catalog::alias_names(r)).await;
        out.push(SearchResult {
            tvdb_id: Some(id),
            kind: Some(result_kind.to_string()),
            name: r["name"].as_str().map(str::to_string),
            year,
            image_url: img,
            overview: r["overview"].as_str().map(str::to_string),
            in_library: false,
        });
    }
    Ok(out)
}

/// The full genre list. Local-first: in a remote-capable mode we (re)fetch from
/// TheTVDB and persist into `catalog.genre`; then always serve from the mirror,
/// so mirror mode has the full list once seeded.
pub async fn genres(state: &AppState) -> AppResult<Vec<Genre>> {
    if state.config.catalog_mode.allow_remote()
        && let Ok(data) = state.tvdb.genres().await
    {
        store_genres(state, &data).await?;
    }
    let rows = sqlx::query_as::<_, Genre>("SELECT id, name FROM catalog.genre ORDER BY name")
        .fetch_all(&state.db)
        .await?;
    Ok(rows)
}

async fn store_genres(state: &AppState, data: &Value) -> AppResult<()> {
    for g in data.as_array().into_iter().flatten() {
        if let (Some(id), Some(name)) = (as_i64(&g["id"]), g["name"].as_str()) {
            sqlx::query("INSERT INTO catalog.genre (id, name, slug) VALUES ($1,$2,$3) ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name")
                .bind(id)
                .bind(name)
                .bind(g["slug"].as_str())
                .execute(&state.db)
                .await?;
        }
    }
    Ok(())
}
