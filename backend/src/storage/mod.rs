//! Object storage (Garage / S3) integration.
//!
//! Wraps an S3 bucket used to lazily mirror TheTVDB artwork into Garage for
//! latency + resiliency (see `docs/storage.md`). Optional: when no S3 credentials
//! are configured, `from_config` returns `None` and artwork mirroring is disabled
//! (the API still serves TheTVDB CDN URLs in metadata).

use s3::{Bucket, Region, creds::Credentials};

use crate::{config::Config, error::AppError};

pub struct Storage {
    bucket: Box<Bucket>,
}

impl Storage {
    /// Build a client from config, or `None` if S3 is not configured.
    pub fn from_config(cfg: &Config) -> Option<Storage> {
        if cfg.s3_access_key.is_empty() || cfg.s3_endpoint.is_empty() {
            return None;
        }
        let region = Region::Custom {
            region: cfg.s3_region.clone(),
            endpoint: cfg.s3_endpoint.clone(),
        };
        let creds = Credentials::new(
            Some(&cfg.s3_access_key),
            Some(&cfg.s3_secret_key),
            None,
            None,
            None,
        )
        .ok()?;
        // Path-style addressing (http://endpoint/bucket/key) — simplest for Garage.
        let bucket = Bucket::new(&cfg.s3_bucket, region, creds).ok()?.with_path_style();
        Some(Storage { bucket })
    }

    pub async fn put(&self, key: &str, bytes: &[u8], content_type: &str) -> Result<(), AppError> {
        self.bucket
            .put_object_with_content_type(key, bytes, content_type)
            .await
            .map_err(|e| AppError::Storage(format!("put {key}: {e}")))?;
        Ok(())
    }

    pub async fn get(&self, key: &str) -> Result<Vec<u8>, AppError> {
        Ok(self.get_with_type(key).await?.0)
    }

    /// Fetch bytes + content-type (from the stored object's headers).
    pub async fn get_with_type(&self, key: &str) -> Result<(Vec<u8>, String), AppError> {
        let resp = self
            .bucket
            .get_object(key)
            .await
            .map_err(|e| AppError::Storage(format!("get {key}: {e}")))?;
        // Any non-2xx (missing key, access denied, …) → treat as not found so we
        // never serve a Garage error XML as if it were image bytes.
        if !(200..300).contains(&resp.status_code()) {
            return Err(AppError::NotFound);
        }
        let ct = resp
            .headers()
            .get("content-type")
            .cloned()
            .unwrap_or_else(|| "application/octet-stream".to_string());
        Ok((resp.bytes().to_vec(), ct))
    }
}
