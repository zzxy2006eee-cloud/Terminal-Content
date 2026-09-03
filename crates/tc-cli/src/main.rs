mod tui;

use anyhow::{Context, Result, bail};
use clap::{Args, Parser, Subcommand};
use serde_json::json;
use std::io::{self, IsTerminal, Write};
use std::path::PathBuf;
use std::process::{Command, ExitCode};
use tc_core::{
    NewSession, Session, SessionStatus, SessionUpdate, Store, current_host, current_platform,
    detect_git, detect_shell, detect_terminal, redact_command, render_title,
};

#[derive(Parser)]
#[command(name = "tc", version, about = "Name and manage terminal work sessions")]
struct Cli {
    #[arg(
        long,
        global = true,
        value_name = "PATH",
        env = "TERM_CONTEXT_DATABASE"
    )]
    database: Option<PathBuf>,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Register the current shell as a managed terminal session.
    Start(StartArgs),
    /// List managed terminal sessions.
    List {
        #[arg(long)]
        json: bool,
        #[arg(long)]
        all: bool,
    },
    /// Show one session. Defaults to TERMCTX_ID.
    Show {
        #[arg(long)]
        id: Option<String>,
        #[arg(long)]
        json: bool,
    },
    /// Print the terminal title for one session.
    Title {
        #[arg(long)]
        id: Option<String>,
        #[arg(long, default_value_t = 64)]
        max_length: usize,
    },
    /// Rename a session.
    Rename {
        name: String,
        #[arg(long)]
        id: Option<String>,
    },
    /// Update a session description.
    Describe {
        description: String,
        #[arg(long)]
        id: Option<String>,
    },
    /// Refresh session metadata and last-seen time.
    Heartbeat(HeartbeatArgs),
    /// Mark a session as complete without terminating its shell.
    Done {
        #[arg(long)]
        id: Option<String>,
    },
    /// Run a command while tracking status and exit code.
    Run {
        #[arg(long)]
        id: Option<String>,
        #[arg(required = true, trailing_var_arg = true, allow_hyphen_values = true)]
        command: Vec<String>,
    },
    /// Open the interactive terminal session manager.
    Tui,
    /// Print environment and storage diagnostics.
    Doctor,
}

#[derive(Args)]
struct StartArgs {
    #[arg(long)]
    name: Option<String>,
    #[arg(long)]
    description: Option<String>,
    #[arg(long)]
    cwd: Option<PathBuf>,
    #[arg(long)]
    platform: Option<String>,
    #[arg(long)]
    shell: Option<String>,
    #[arg(long)]
    terminal: Option<String>,
    #[arg(long)]
    distro: Option<String>,
    #[arg(long)]
    pid: Option<i64>,
    #[arg(long)]
    parent_pid: Option<i64>,
    /// Print only the full session ID for shell integration.
    #[arg(long)]
    print_id: bool,
    #[arg(long)]
    json: bool,
}

#[derive(Args)]
struct HeartbeatArgs {
    #[arg(long)]
    id: Option<String>,
    #[arg(long)]
    cwd: Option<PathBuf>,
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("error: {error:#}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<u8> {
    let cli = Cli::parse();
    let store = match cli.database {
        Some(path) => Store::open(path)?,
        None => Store::open_default()?,
    };

    match cli.command {
        Commands::Start(args) => start(&store, args)?,
        Commands::List { json, all } => list(&store, json, all)?,
        Commands::Show { id, json } => show(&store, id, json)?,
        Commands::Title { id, max_length } => {
            let session = resolve_session(&store, id)?;
            println!("{}", render_title(&session, max_length));
        }
        Commands::Rename { name, id } => {
            let id = resolve_id(id)?;
            let session = store.update(
                &id,
                SessionUpdate {
                    name: Some(&name),
                    ..Default::default()
                },
            )?;
            println!("Renamed {} to {}", session.short_id, session.name);
        }
        Commands::Describe { description, id } => {
            let id = resolve_id(id)?;
            let session = store.update(
                &id,
                SessionUpdate {
                    description: Some(&description),
                    ..Default::default()
                },
            )?;
            println!("Updated description for {}", session.short_id);
        }
        Commands::Heartbeat(args) => heartbeat(&store, args)?,
        Commands::Done { id } => {
            let id = resolve_id(id)?;
            let session = store.update(
                &id,
                SessionUpdate {
                    ended: Some(true),
                    ..Default::default()
                },
            )?;
            println!("Completed {} ({})", session.name, session.short_id);
        }
        Commands::Run { id, command } => return run_command(&store, id, command),
        Commands::Tui => tui::run(&store)?,
        Commands::Doctor => doctor(&store),
    }
    Ok(0)
}

fn start(store: &Store, args: StartArgs) -> Result<()> {
    let cwd = args
        .cwd
        .unwrap_or(std::env::current_dir().context("failed to read current directory")?);
    let cwd_string = cwd.to_string_lossy().to_string();
    let default_name = cwd
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("terminal")
        .to_string();

    let name = match args.name {
        Some(value) => value,
        None if io::stdin().is_terminal() => prompt("Work name", Some(&default_name))?,
        None => default_name,
    };
    let description = match args.description {
        Some(value) => value,
        None if io::stdin().is_terminal() => prompt("Description", Some(""))?,
        None => String::new(),
    };
    let (git_root, git_branch) = detect_git(&cwd_string);
    let process_pid = args.pid.unwrap_or_else(parent_process_id);

    let session = store.create(NewSession {
        name,
        description,
        platform: args.platform.unwrap_or_else(current_platform),
        shell: args.shell.unwrap_or_else(detect_shell),
        terminal: args.terminal.unwrap_or_else(detect_terminal),
        host: current_host(),
        distro: args
            .distro
            .or_else(|| std::env::var("WSL_DISTRO_NAME").ok()),
        cwd: cwd_string,
        git_root,
        git_branch,
        pid: process_pid,
        parent_pid: args.parent_pid,
    })?;

    if args.json {
        println!("{}", serde_json::to_string_pretty(&session)?);
    } else if args.print_id {
        println!("{}", session.id);
    } else {
        println!("Registered {}", render_title(&session, 64));
        println!(
            "Set TERMCTX_ID={} in the current shell through its shell integration.",
            session.id
        );
    }
    Ok(())
}

fn list(store: &Store, as_json: bool, include_done: bool) -> Result<()> {
    let _ = store.mark_stale_local_processes(&current_host());
    let sessions = store.list(include_done)?;
    if as_json {
        println!("{}", serde_json::to_string_pretty(&sessions)?);
        return Ok(());
    }
    if sessions.is_empty() {
        println!("No terminal sessions.");
        return Ok(());
    }

    println!(
        "{:<2} {:<6} {:<18} {:<26} {:<14} CWD",
        "S", "ID", "NAME", "DESCRIPTION", "BRANCH"
    );
    for session in sessions {
        println!(
            "{:<2} {:<6} {:<18} {:<26} {:<14} {}",
            status_symbol(session.status),
            session.short_id,
            clip(&session.name, 18),
            clip(&session.description, 26),
            clip(session.git_branch.as_deref().unwrap_or("-"), 14),
            session.cwd
        );
    }
    Ok(())
}

fn show(store: &Store, id: Option<String>, as_json: bool) -> Result<()> {
    let session = resolve_session(store, id)?;
    if as_json {
        println!(
            "{}",
            serde_json::to_string_pretty(&json!({
                "session": session,
                "title": render_title(&session, 64)
            }))?
        );
    } else {
        println!("{}", render_title(&session, 64));
        println!("Description: {}", session.description);
        println!("Status:      {}", session.status);
        println!("Directory:   {}", session.cwd);
        println!(
            "Git branch:  {}",
            session.git_branch.as_deref().unwrap_or("-")
        );
        println!(
            "Command:     {}",
            session.current_command.as_deref().unwrap_or("-")
        );
        println!(
            "Platform:    {} / {} / {}",
            session.platform, session.shell, session.terminal
        );
    }
    Ok(())
}

fn heartbeat(store: &Store, args: HeartbeatArgs) -> Result<()> {
    let id = resolve_id(args.id)?;
    let cwd = args
        .cwd
        .unwrap_or(std::env::current_dir().context("failed to read current directory")?);
    let cwd_string = cwd.to_string_lossy().to_string();
    let (git_root, git_branch) = detect_git(&cwd_string);
    store.update(
        &id,
        SessionUpdate {
            cwd: Some(&cwd_string),
            git_root: Some(git_root.as_deref()),
            git_branch: Some(git_branch.as_deref()),
            ..Default::default()
        },
    )?;
    Ok(())
}

fn run_command(store: &Store, id: Option<String>, command: Vec<String>) -> Result<u8> {
    let id = resolve_id(id)?;
    if command.is_empty() {
        bail!("a command is required");
    }
    let redacted = redact_command(&command);
    store.update(
        &id,
        SessionUpdate {
            status: Some(SessionStatus::Running),
            current_command: Some(Some(&redacted)),
            exit_code: Some(None),
            ..Default::default()
        },
    )?;

    let result = Command::new(&command[0]).args(&command[1..]).status();
    match result {
        Ok(status) => {
            let code = status.code().unwrap_or(1);
            let next_status = if status.success() {
                SessionStatus::Idle
            } else {
                SessionStatus::Failed
            };
            store.update(
                &id,
                SessionUpdate {
                    status: Some(next_status),
                    current_command: Some(None),
                    exit_code: Some(Some(code)),
                    ..Default::default()
                },
            )?;
            Ok(code.clamp(0, 255) as u8)
        }
        Err(error) => {
            store.update(
                &id,
                SessionUpdate {
                    status: Some(SessionStatus::Failed),
                    current_command: Some(None),
                    exit_code: Some(Some(127)),
                    ..Default::default()
                },
            )?;
            Err(error).with_context(|| format!("failed to start {}", command[0]))
        }
    }
}

fn doctor(store: &Store) {
    println!("Terminal Context diagnostics");
    println!("Database: {}", store.path().display());
    println!("Platform: {}", current_platform());
    println!("Shell:    {}", detect_shell());
    println!("Terminal: {}", detect_terminal());
    println!("Host:     {}", current_host());
    println!(
        "Session:  {}",
        std::env::var("TERMCTX_ID").unwrap_or_else(|_| "not attached".into())
    );
}

fn resolve_session(store: &Store, id: Option<String>) -> Result<Session> {
    let id = resolve_id(id)?;
    store
        .get(&id)?
        .with_context(|| format!("session not found: {id}"))
}

fn resolve_id(id: Option<String>) -> Result<String> {
    id.or_else(|| std::env::var("TERMCTX_ID").ok())
        .context("no session selected; pass --id or set TERMCTX_ID using tc-start")
}

fn prompt(label: &str, default: Option<&str>) -> Result<String> {
    match default {
        Some(value) if !value.is_empty() => eprint!("{label} [{value}]: "),
        _ => eprint!("{label}: "),
    }
    io::stderr().flush()?;
    let mut input = String::new();
    io::stdin().read_line(&mut input)?;
    let value = input.trim();
    Ok(if value.is_empty() {
        default.unwrap_or_default().to_string()
    } else {
        value.to_string()
    })
}

fn parent_process_id() -> i64 {
    let system = sysinfo::System::new_all();
    sysinfo::get_current_pid()
        .ok()
        .and_then(|pid| system.process(pid))
        .and_then(|process| process.parent())
        .map(|pid| pid.as_u32() as i64)
        .unwrap_or(std::process::id() as i64)
}

fn status_symbol(status: SessionStatus) -> &'static str {
    match status {
        SessionStatus::Idle => "○",
        SessionStatus::Running => "●",
        SessionStatus::Failed => "!",
        SessionStatus::Done => "✓",
        SessionStatus::Stale => "?",
    }
}

fn clip(value: &str, max: usize) -> String {
    let mut value = value.to_string();
    if value.chars().count() > max {
        value = value
            .chars()
            .take(max.saturating_sub(1))
            .collect::<String>();
        value.push('…');
    }
    value
}
