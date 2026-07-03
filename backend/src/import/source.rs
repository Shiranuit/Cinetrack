//! Reads CSVs out of the GDPR export `.zip` into simple header→value rows.

use std::{collections::HashMap, io::{Cursor, Read}};

use anyhow::Context;
use zip::ZipArchive;

pub type Row = HashMap<String, String>;

pub struct ZipSource {
    archive: ZipArchive<Cursor<Vec<u8>>>,
}

impl ZipSource {
    pub fn open(path: &str) -> anyhow::Result<Self> {
        let bytes = std::fs::read(path).with_context(|| format!("opening {path}"))?;
        Self::open_bytes(bytes)
    }

    pub fn open_bytes(bytes: Vec<u8>) -> anyhow::Result<Self> {
        let archive = ZipArchive::new(Cursor::new(bytes)).context("reading zip")?;
        Ok(Self { archive })
    }

    /// Read a CSV whose entry name ends with `name` (ignores any folder prefix
    /// inside the zip). Returns rows as header→value maps. Missing file → empty.
    pub fn read_csv(&mut self, name: &str) -> anyhow::Result<Vec<Row>> {
        let idx = (0..self.archive.len()).find(|&i| {
            self.archive
                .by_index(i)
                .ok()
                .filter(|f| f.is_file())
                .is_some_and(|f| f.name().ends_with(name))
        });
        let Some(idx) = idx else {
            tracing::warn!("{name} not found in zip — skipping");
            return Ok(vec![]);
        };

        let mut bytes = Vec::new();
        self.archive.by_index(idx)?.read_to_end(&mut bytes)?;

        // `Trim::All` strips the heavy header/value padding TV Time pads its CSV
        // columns with (e.g. `tv_show_name                 `), so header→value keys
        // and values are clean for exact lookups.
        let mut rdr = csv::ReaderBuilder::new()
            .flexible(true)
            .trim(csv::Trim::All)
            .from_reader(&bytes[..]);
        let headers = rdr.headers().context("reading CSV headers")?.clone();
        let mut rows = Vec::new();
        for rec in rdr.records() {
            let rec = rec?;
            let row: Row = headers
                .iter()
                .zip(rec.iter())
                .map(|(h, v)| (h.to_string(), v.to_string()))
                .collect();
            rows.push(row);
        }
        Ok(rows)
    }
}

/// Trimmed, non-empty string value for a column.
pub fn s<'a>(row: &'a Row, key: &str) -> Option<&'a str> {
    row.get(key).map(|v| v.trim()).filter(|v| !v.is_empty())
}

pub fn i64v(row: &Row, key: &str) -> Option<i64> {
    s(row, key).and_then(|v| v.parse().ok())
}

pub fn i32v(row: &Row, key: &str) -> Option<i32> {
    s(row, key).and_then(|v| v.parse().ok())
}

/// TV Time stores booleans as "0"/"1".
pub fn boolv(row: &Row, key: &str) -> Option<bool> {
    s(row, key).map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
}

/// A naive "YYYY-MM-DD HH:MM:SS" timestamp → an ISO string pinned to UTC, ready
/// to bind with a `::timestamptz` cast.
pub fn ts_utc(row: &Row, key: &str) -> Option<String> {
    s(row, key).map(|v| format!("{v}+00"))
}
