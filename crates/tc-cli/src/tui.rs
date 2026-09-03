use anyhow::{Context, Result};
use crossterm::{
    cursor::{Hide, MoveTo, Show},
    event::{self, Event, KeyCode, KeyEventKind},
    execute, queue,
    style::{Attribute, Print, SetAttribute},
    terminal::{
        Clear, ClearType, EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode,
        enable_raw_mode,
    },
};
use std::io::{self, Write};
use std::time::Duration;
use tc_core::{Session, SessionUpdate, Store, render_title};

pub fn run(store: &Store) -> Result<()> {
    let mut terminal = TerminalGuard::enter()?;
    let mut selected = 0usize;
    let mut message = "↑/↓ select  Enter details  r rename  d describe  x done  q quit".to_string();

    loop {
        let sessions = store.list(false)?;
        if !sessions.is_empty() {
            selected = selected.min(sessions.len() - 1);
        } else {
            selected = 0;
        }
        draw(&mut terminal.stdout, &sessions, selected, &message)?;

        if !event::poll(Duration::from_millis(500))? {
            continue;
        }
        let Event::Key(key) = event::read()? else {
            continue;
        };
        if key.kind != KeyEventKind::Press {
            continue;
        }
        match key.code {
            KeyCode::Char('q') => break,
            KeyCode::Up | KeyCode::Char('k') => selected = selected.saturating_sub(1),
            KeyCode::Down | KeyCode::Char('j') => {
                if selected + 1 < sessions.len() {
                    selected += 1;
                }
            }
            KeyCode::Enter => {
                if let Some(session) = sessions.get(selected) {
                    message = format!(
                        "{} | {} | {}",
                        render_title(session, 70),
                        session.current_command.as_deref().unwrap_or("idle"),
                        session.cwd
                    );
                }
            }
            KeyCode::Char('x') => {
                if let Some(session) = sessions.get(selected) {
                    store.update(
                        &session.id,
                        SessionUpdate {
                            ended: Some(true),
                            ..Default::default()
                        },
                    )?;
                    message = format!("Completed {}", session.name);
                }
            }
            KeyCode::Char('r') => {
                if let Some(session) = sessions.get(selected) {
                    let value = terminal.prompt(&format!("New name [{}]", session.name))?;
                    if !value.is_empty() {
                        store.update(
                            &session.id,
                            SessionUpdate {
                                name: Some(&value),
                                ..Default::default()
                            },
                        )?;
                        message = "Name updated".into();
                    }
                }
            }
            KeyCode::Char('d') => {
                if let Some(session) = sessions.get(selected) {
                    let value =
                        terminal.prompt(&format!("Description [{}]", session.description))?;
                    if !value.is_empty() {
                        store.update(
                            &session.id,
                            SessionUpdate {
                                description: Some(&value),
                                ..Default::default()
                            },
                        )?;
                        message = "Description updated".into();
                    }
                }
            }
            _ => {}
        }
    }
    Ok(())
}

fn draw(
    stdout: &mut io::Stdout,
    sessions: &[Session],
    selected: usize,
    message: &str,
) -> Result<()> {
    queue!(stdout, MoveTo(0, 0), Clear(ClearType::All))?;
    queue!(
        stdout,
        SetAttribute(Attribute::Bold),
        Print("Terminal Context\r\n\r\n"),
        SetAttribute(Attribute::Reset)
    )?;
    if sessions.is_empty() {
        queue!(
            stdout,
            Print("No active sessions. Run tc-start in a shell.\r\n")
        )?;
    } else {
        for (index, session) in sessions.iter().enumerate() {
            if index == selected {
                queue!(stdout, SetAttribute(Attribute::Reverse))?;
            }
            queue!(
                stdout,
                Print(format!(
                    " {:<6} {:<12} {:<22} {:<18} {} \r\n",
                    session.short_id,
                    session.status,
                    clip(&session.name, 22),
                    clip(&session.description, 18),
                    session.cwd
                )),
                SetAttribute(Attribute::Reset)
            )?;
        }
    }
    queue!(stdout, Print(format!("\r\n{message}\r\n")))?;
    stdout.flush()?;
    Ok(())
}

struct TerminalGuard {
    stdout: io::Stdout,
    active: bool,
}

impl TerminalGuard {
    fn enter() -> Result<Self> {
        enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen, Hide)?;
        Ok(Self {
            stdout,
            active: true,
        })
    }

    fn suspend(&mut self) -> Result<()> {
        if self.active {
            disable_raw_mode()?;
            execute!(self.stdout, Show, LeaveAlternateScreen)?;
            self.active = false;
        }
        Ok(())
    }

    fn resume(&mut self) -> Result<()> {
        if !self.active {
            enable_raw_mode()?;
            execute!(self.stdout, EnterAlternateScreen, Hide)?;
            self.active = true;
        }
        Ok(())
    }

    fn prompt(&mut self, label: &str) -> Result<String> {
        self.suspend()?;
        print!("{label}: ");
        io::stdout().flush()?;
        let mut input = String::new();
        io::stdin()
            .read_line(&mut input)
            .context("failed to read input")?;
        self.resume()?;
        Ok(input.trim().to_string())
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        if self.active {
            let _ = disable_raw_mode();
            let _ = execute!(self.stdout, Show, LeaveAlternateScreen);
        }
    }
}

fn clip(value: &str, max: usize) -> String {
    if value.chars().count() <= max {
        return value.to_string();
    }
    let mut result = value
        .chars()
        .take(max.saturating_sub(1))
        .collect::<String>();
    result.push('…');
    result
}
