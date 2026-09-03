use serde::{Deserialize, Serialize};
use std::fmt::{Display, Formatter};
use std::str::FromStr;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionStatus {
    Idle,
    Running,
    Failed,
    Done,
    Stale,
}

impl Display for SessionStatus {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        let value = match self {
            Self::Idle => "idle",
            Self::Running => "running",
            Self::Failed => "failed",
            Self::Done => "done",
            Self::Stale => "stale",
        };
        f.write_str(value)
    }
}

impl FromStr for SessionStatus {
    type Err = anyhow::Error;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "idle" => Ok(Self::Idle),
            "running" => Ok(Self::Running),
            "failed" => Ok(Self::Failed),
            "done" => Ok(Self::Done),
            "stale" => Ok(Self::Stale),
            _ => Err(anyhow::anyhow!("unknown session status: {value}")),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: String,
    pub short_id: String,
    pub name: String,
    pub description: String,
    pub platform: String,
    pub shell: String,
    pub terminal: String,
    pub host: String,
    pub distro: Option<String>,
    pub cwd: String,
    pub git_root: Option<String>,
    pub git_branch: Option<String>,
    pub pid: i64,
    pub parent_pid: Option<i64>,
    pub status: SessionStatus,
    pub current_command: Option<String>,
    pub exit_code: Option<i32>,
    pub created_at: String,
    pub last_seen_at: String,
    pub ended_at: Option<String>,
}

#[derive(Debug, Clone)]
pub struct NewSession {
    pub name: String,
    pub description: String,
    pub platform: String,
    pub shell: String,
    pub terminal: String,
    pub host: String,
    pub distro: Option<String>,
    pub cwd: String,
    pub git_root: Option<String>,
    pub git_branch: Option<String>,
    pub pid: i64,
    pub parent_pid: Option<i64>,
}

#[derive(Debug, Default)]
pub struct SessionUpdate<'a> {
    pub name: Option<&'a str>,
    pub description: Option<&'a str>,
    pub cwd: Option<&'a str>,
    pub git_root: Option<Option<&'a str>>,
    pub git_branch: Option<Option<&'a str>>,
    pub status: Option<SessionStatus>,
    pub current_command: Option<Option<&'a str>>,
    pub exit_code: Option<Option<i32>>,
    pub ended: Option<bool>,
}
