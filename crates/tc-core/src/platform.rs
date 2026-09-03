use std::path::Path;
use std::process::Command;

pub fn current_host() -> String {
    hostname::get()
        .ok()
        .and_then(|value| value.into_string().ok())
        .unwrap_or_else(|| "unknown".to_string())
}

pub fn current_platform() -> String {
    if std::env::var_os("WSL_DISTRO_NAME").is_some() {
        "wsl".to_string()
    } else if cfg!(windows) {
        "windows".to_string()
    } else if cfg!(target_os = "linux") {
        "linux".to_string()
    } else {
        std::env::consts::OS.to_string()
    }
}

pub fn detect_shell() -> String {
    if let Ok(shell) = std::env::var("TERM_CONTEXT_SHELL") {
        return shell;
    }
    if let Ok(shell) = std::env::var("SHELL") {
        return Path::new(&shell)
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or("shell")
            .to_string();
    }
    if std::env::var_os("PSModulePath").is_some() {
        return "powershell".to_string();
    }
    std::env::var("COMSPEC")
        .ok()
        .and_then(|value| Path::new(&value).file_stem()?.to_str().map(str::to_string))
        .unwrap_or_else(|| "shell".to_string())
}

pub fn detect_terminal() -> String {
    if std::env::var_os("WT_SESSION").is_some() {
        "windows-terminal".to_string()
    } else if let Ok(program) = std::env::var("TERM_PROGRAM") {
        program.to_lowercase()
    } else if std::env::var_os("WEZTERM_PANE").is_some() {
        "wezterm".to_string()
    } else if std::env::var_os("VTE_VERSION").is_some() {
        "vte-terminal".to_string()
    } else {
        "unknown".to_string()
    }
}

pub fn detect_git(cwd: &str) -> (Option<String>, Option<String>) {
    let root = run_git(cwd, &["rev-parse", "--show-toplevel"]);
    let branch = run_git(cwd, &["branch", "--show-current"])
        .filter(|value| !value.is_empty())
        .or_else(|| {
            run_git(cwd, &["rev-parse", "--short", "HEAD"]).map(|v| format!("detached:{v}"))
        });
    (root, branch)
}

fn run_git(cwd: &str, args: &[&str]) -> Option<String> {
    let output = Command::new("git")
        .args(args)
        .current_dir(cwd)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

pub fn process_is_alive(pid: i64) -> bool {
    if pid <= 0 {
        return false;
    }
    let system = sysinfo::System::new_all();
    system.process(sysinfo::Pid::from_u32(pid as u32)).is_some()
}
