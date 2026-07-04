//! TV Show Tracker backend library. Shared by the server (`main.rs`) and the
//! GDPR import CLI (`bin/import.rs`).

pub mod audit;
pub mod auth;
pub mod catalog;
pub mod config;
pub mod db;
pub mod email;
pub mod email_templates;
pub mod error;
pub mod import;
pub mod state;
pub mod storage;
pub mod sync;
pub mod thetvdb;
pub mod tracking;
pub mod web;
