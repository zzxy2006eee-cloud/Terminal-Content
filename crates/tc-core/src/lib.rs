mod model;
mod platform;
mod redact;
mod storage;
mod title;

pub use model::{NewSession, Session, SessionStatus, SessionUpdate};
pub use platform::{
    current_host, current_platform, detect_git, detect_shell, detect_terminal, process_is_alive,
};
pub use redact::redact_command;
pub use storage::Store;
pub use title::{render_title, sanitize_text, truncate_chars};
