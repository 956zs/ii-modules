//! Stable exit-code contract (SPEC 1.0 §13). Skills and scripts rely on these.

pub const OK: i32 = 0;
pub const INTERNAL: i32 = 1;
pub const USAGE: i32 = 2;
pub const VALIDATION: i32 = 3;
pub const PROBE: i32 = 4;
pub const DEPENDENCY: i32 = 5;
pub const INTEGRITY: i32 = 6;
pub const STATE: i32 = 7;
pub const ANCHOR: i32 = 8;
pub const NEEDS_ALLOW_PATCHES: i32 = 9;
pub const PROTOCOL: i32 = 10;

/// Error carrying a specific exit code through the anyhow chain.
#[derive(Debug)]
pub struct ExitError {
    pub code: i32,
    pub message: String,
}

impl std::fmt::Display for ExitError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for ExitError {}

pub fn bail(code: i32, message: impl Into<String>) -> anyhow::Error {
    anyhow::Error::new(ExitError {
        code,
        message: message.into(),
    })
}

/// Map an anyhow error to its exit code (INTERNAL if untagged).
pub fn code_of(err: &anyhow::Error) -> i32 {
    err.downcast_ref::<ExitError>()
        .map(|e| e.code)
        .unwrap_or(INTERNAL)
}
