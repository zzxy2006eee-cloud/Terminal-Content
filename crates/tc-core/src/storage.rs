use crate::{NewSession, Session, SessionStatus, SessionUpdate, process_is_alive, sanitize_text};
use anyhow::{Context, Result, bail};
use chrono::Utc;
use rusqlite::{Connection, OptionalExtension, params};
use std::path::{Path, PathBuf};
use std::str::FromStr;
use uuid::Uuid;

pub struct Store {
    connection: Connection,
    path: PathBuf,
}

impl Store {
    pub fn open_default() -> Result<Self> {
        let data_dir = data_dir()?;
        std::fs::create_dir_all(&data_dir)
            .with_context(|| format!("failed to create data directory {}", data_dir.display()))?;
        Self::open(data_dir.join("term-context.db"))
    }

    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let connection = Connection::open(&path)
            .with_context(|| format!("failed to open database {}", path.display()))?;
        connection.busy_timeout(std::time::Duration::from_secs(5))?;
        connection.pragma_update(None, "journal_mode", "WAL")?;
        let store = Self { connection, path };
        store.migrate()?;
        Ok(store)
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    fn migrate(&self) -> Result<()> {
        self.connection.execute_batch(
            "CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                short_id TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL,
                description TEXT NOT NULL,
                platform TEXT NOT NULL,
                shell TEXT NOT NULL,
                terminal TEXT NOT NULL,
                host TEXT NOT NULL,
                distro TEXT,
                cwd TEXT NOT NULL,
                git_root TEXT,
                git_branch TEXT,
                pid INTEGER NOT NULL,
                parent_pid INTEGER,
                status TEXT NOT NULL,
                current_command TEXT,
                exit_code INTEGER,
                created_at TEXT NOT NULL,
                last_seen_at TEXT NOT NULL,
                ended_at TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status);
            CREATE INDEX IF NOT EXISTS idx_sessions_last_seen ON sessions(last_seen_at);",
        )?;
        Ok(())
    }

    pub fn create(&self, new: NewSession) -> Result<Session> {
        let id = Uuid::new_v4().to_string();
        let short_id = id
            .chars()
            .filter(|ch| *ch != '-')
            .take(6)
            .collect::<String>()
            .to_uppercase();
        let now = Utc::now().to_rfc3339();
        let name = sanitize_text(&new.name);
        if name.is_empty() {
            bail!("session name cannot be empty");
        }
        let description = sanitize_text(&new.description);
        self.connection.execute(
            "INSERT INTO sessions (
                id, short_id, name, description, platform, shell, terminal, host, distro,
                cwd, git_root, git_branch, pid, parent_pid, status, current_command,
                exit_code, created_at, last_seen_at, ended_at
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14,
                       'idle', NULL, NULL, ?15, ?15, NULL)",
            params![
                id,
                short_id,
                name,
                description,
                new.platform,
                new.shell,
                new.terminal,
                new.host,
                new.distro,
                new.cwd,
                new.git_root,
                new.git_branch,
                new.pid,
                new.parent_pid,
                now,
            ],
        )?;
        self.get(&id)?.context("created session was not found")
    }

    pub fn get(&self, id_or_short: &str) -> Result<Option<Session>> {
        self.connection
            .query_row(
                "SELECT id, short_id, name, description, platform, shell, terminal, host,
                        distro, cwd, git_root, git_branch, pid, parent_pid, status,
                        current_command, exit_code, created_at, last_seen_at, ended_at
                 FROM sessions
                 WHERE id = ?1 OR short_id = UPPER(?1)",
                [id_or_short],
                row_to_session,
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn list(&self, include_done: bool) -> Result<Vec<Session>> {
        let sql = if include_done {
            "SELECT id, short_id, name, description, platform, shell, terminal, host,
                    distro, cwd, git_root, git_branch, pid, parent_pid, status,
                    current_command, exit_code, created_at, last_seen_at, ended_at
             FROM sessions ORDER BY ended_at IS NOT NULL, last_seen_at DESC"
        } else {
            "SELECT id, short_id, name, description, platform, shell, terminal, host,
                    distro, cwd, git_root, git_branch, pid, parent_pid, status,
                    current_command, exit_code, created_at, last_seen_at, ended_at
             FROM sessions WHERE status != 'done' ORDER BY last_seen_at DESC"
        };
        let mut statement = self.connection.prepare(sql)?;
        let sessions = statement
            .query_map([], row_to_session)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(sessions)
    }

    pub fn update(&self, id: &str, update: SessionUpdate<'_>) -> Result<Session> {
        let mut session = self
            .get(id)?
            .with_context(|| format!("session not found: {id}"))?;
        if let Some(value) = update.name {
            session.name = sanitize_text(value);
            if session.name.is_empty() {
                bail!("session name cannot be empty");
            }
        }
        if let Some(value) = update.description {
            session.description = sanitize_text(value);
        }
        if let Some(value) = update.cwd {
            session.cwd = value.to_string();
        }
        if let Some(value) = update.git_root {
            session.git_root = value.map(str::to_string);
        }
        if let Some(value) = update.git_branch {
            session.git_branch = value.map(str::to_string);
        }
        if let Some(value) = update.status {
            session.status = value;
        }
        if let Some(value) = update.current_command {
            session.current_command = value.map(str::to_string);
        }
        if let Some(value) = update.exit_code {
            session.exit_code = value;
        }
        let now = Utc::now().to_rfc3339();
        if update.ended == Some(true) {
            session.ended_at = Some(now.clone());
            session.status = SessionStatus::Done;
            session.current_command = None;
        } else if update.ended == Some(false) {
            session.ended_at = None;
        }
        session.last_seen_at = now;

        self.connection.execute(
            "UPDATE sessions SET name=?2, description=?3, cwd=?4, git_root=?5,
                    git_branch=?6, status=?7, current_command=?8, exit_code=?9,
                    last_seen_at=?10, ended_at=?11 WHERE id=?1",
            params![
                session.id,
                session.name,
                session.description,
                session.cwd,
                session.git_root,
                session.git_branch,
                session.status.to_string(),
                session.current_command,
                session.exit_code,
                session.last_seen_at,
                session.ended_at,
            ],
        )?;
        Ok(session)
    }

    pub fn mark_stale_local_processes(&self, host: &str) -> Result<usize> {
        let sessions = self.list(false)?;
        let mut changed = 0;
        for session in sessions {
            if session.host == host
                && session.platform != "wsl"
                && !matches!(session.status, SessionStatus::Done | SessionStatus::Stale)
                && !process_is_alive(session.pid)
            {
                self.update(
                    &session.id,
                    SessionUpdate {
                        status: Some(SessionStatus::Stale),
                        current_command: Some(None),
                        ..Default::default()
                    },
                )?;
                changed += 1;
            }
        }
        Ok(changed)
    }
}

fn row_to_session(row: &rusqlite::Row<'_>) -> rusqlite::Result<Session> {
    let status: String = row.get(14)?;
    Ok(Session {
        id: row.get(0)?,
        short_id: row.get(1)?,
        name: row.get(2)?,
        description: row.get(3)?,
        platform: row.get(4)?,
        shell: row.get(5)?,
        terminal: row.get(6)?,
        host: row.get(7)?,
        distro: row.get(8)?,
        cwd: row.get(9)?,
        git_root: row.get(10)?,
        git_branch: row.get(11)?,
        pid: row.get(12)?,
        parent_pid: row.get(13)?,
        status: SessionStatus::from_str(&status).map_err(|error| {
            rusqlite::Error::FromSqlConversionFailure(
                14,
                rusqlite::types::Type::Text,
                Box::new(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    error.to_string(),
                )),
            )
        })?,
        current_command: row.get(15)?,
        exit_code: row.get(16)?,
        created_at: row.get(17)?,
        last_seen_at: row.get(18)?,
        ended_at: row.get(19)?,
    })
}

fn data_dir() -> Result<PathBuf> {
    if let Some(path) = std::env::var_os("TERM_CONTEXT_DATA_DIR") {
        return Ok(PathBuf::from(path));
    }
    dirs::data_local_dir()
        .map(|path| path.join("term-context"))
        .context("could not determine a local data directory; set TERM_CONTEXT_DATA_DIR")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> NewSession {
        NewSession {
            name: "API".into(),
            description: "login debugging".into(),
            platform: "test".into(),
            shell: "test-shell".into(),
            terminal: "test-terminal".into(),
            host: "test-host".into(),
            distro: None,
            cwd: ".".into(),
            git_root: None,
            git_branch: None,
            pid: std::process::id() as i64,
            parent_pid: None,
        }
    }

    #[test]
    fn creates_and_updates_a_session() {
        let store = Store::open(":memory:").unwrap();
        let created = store.create(sample()).unwrap();
        assert_eq!(created.status, SessionStatus::Idle);
        let updated = store
            .update(
                &created.id,
                SessionUpdate {
                    name: Some("API server"),
                    status: Some(SessionStatus::Running),
                    ..Default::default()
                },
            )
            .unwrap();
        assert_eq!(updated.name, "API server");
        assert_eq!(updated.status, SessionStatus::Running);
    }
}
