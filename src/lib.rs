pub mod codex;
pub mod marker;
pub mod runner;
pub mod store;

use std::fmt;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("bubble unavailable")]
    Unavailable,
    #[error("{0}")]
    InvalidInput(String),
    #[error("storage operation failed")]
    Storage(#[source] std::io::Error),
    #[error("cryptographic operation failed")]
    Crypto,
    #[error("could not start child process")]
    Spawn(#[source] std::io::Error),
    #[error("could not deliver secret to child stdin")]
    Delivery(#[source] std::io::Error),
    #[error("invalid hook input")]
    HookInput(#[source] serde_json::Error),
    #[error("could not encode hook output")]
    HookOutput(#[source] serde_json::Error),
}

impl Error {
    pub fn public_message(&self) -> String {
        match self {
            Self::Unavailable => "bubl: bubble unavailable".to_string(),
            other => format!("bubl: {other}"),
        }
    }
}

pub type Result<T> = std::result::Result<T, Error>;

pub struct ExitStatus(pub i32);

impl fmt::Display for ExitStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}
