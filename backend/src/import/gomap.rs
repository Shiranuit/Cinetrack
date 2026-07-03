//! Minimal parser for the Go `fmt`-formatted blobs in the TV Time export.
//!
//! These are NOT JSON — they are Go's default formatting of `map[string]any`:
//! `map[k1:v1 k2:v2]`, slices as `[a b c]`, `<nil>` for null, and numbers as
//! float64 in scientific notation (`1.66e+09`). We only need the `favorite-series`
//! `objects` array, whose maps are flat with space-free scalar values, e.g.:
//!   `[map[created_at:1.660769713e+09 id:371028 type:series] map[... id:74796 ...]]`

/// A single member of a favorites list.
#[derive(Debug)]
pub struct FavItem {
    pub id: i64,
    pub kind: String, // "series" | "movie"
}

/// Extract the inner text of every top-level `map[...]` block, honoring nested
/// brackets so we don't stop early on slice values.
fn map_blocks(s: &str) -> Vec<&str> {
    let bytes = s.as_bytes();
    let mut blocks = Vec::new();
    let mut i = 0;
    while let Some(rel) = s[i..].find("map[") {
        let start = i + rel + 4; // just past "map["
        let mut depth = 1;
        let mut j = start;
        while j < bytes.len() {
            match bytes[j] {
                b'[' => depth += 1,
                b']' => {
                    depth -= 1;
                    if depth == 0 {
                        break;
                    }
                }
                _ => {}
            }
            j += 1;
        }
        blocks.push(&s[start..j.min(bytes.len())]);
        i = j + 1;
    }
    blocks
}

/// Parse the `objects` blob of a favorites row into its members.
pub fn parse_favorite_objects(s: &str) -> Vec<FavItem> {
    map_blocks(s)
        .into_iter()
        .filter_map(|block| {
            let mut id = None;
            let mut kind = None;
            for tok in block.split_whitespace() {
                if let Some((k, v)) = tok.split_once(':') {
                    match k {
                        "id" => id = v.parse::<i64>().ok(),
                        "type" => kind = Some(v.to_string()),
                        _ => {}
                    }
                }
            }
            Some(FavItem {
                id: id?,
                kind: kind.unwrap_or_else(|| "series".to_string()),
            })
        })
        .collect()
}
