use crate::{Session, SessionStatus};

pub fn sanitize_text(value: &str) -> String {
    value
        .chars()
        .filter(|ch| !ch.is_control())
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn truncate_chars(value: &str, max: usize) -> String {
    if value.chars().count() <= max {
        return value.to_string();
    }
    if max <= 1 {
        return "…".chars().take(max).collect();
    }
    let mut result = value.chars().take(max - 1).collect::<String>();
    result.push('…');
    result
}

pub fn render_title(session: &Session, max: usize) -> String {
    let symbol = match session.status {
        SessionStatus::Idle => "○",
        SessionStatus::Running => "●",
        SessionStatus::Failed => "!",
        SessionStatus::Done => "✓",
        SessionStatus::Stale => "?",
    };
    let description = if session.description.is_empty() {
        String::new()
    } else {
        format!("｜{}", sanitize_text(&session.description))
    };
    truncate_chars(
        &format!(
            "{symbol} {}{description}｜{}",
            sanitize_text(&session.name),
            session.short_id
        ),
        max,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_control_characters_and_collapses_space() {
        assert_eq!(sanitize_text("  api\n\t server\u{7}  "), "api server");
    }

    #[test]
    fn truncates_unicode_by_character() {
        assert_eq!(truncate_chars("终端管理工具", 5), "终端管理…");
    }
}
