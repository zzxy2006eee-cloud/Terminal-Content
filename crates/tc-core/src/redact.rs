const SENSITIVE_FLAGS: &[&str] = &[
    "--token",
    "--password",
    "--passwd",
    "--secret",
    "--api-key",
    "--apikey",
    "--access-key",
    "--auth",
    "-p",
];

pub fn redact_command(args: &[String]) -> String {
    let mut output = Vec::with_capacity(args.len());
    let mut hide_next = false;

    for arg in args {
        if hide_next {
            output.push("***".to_string());
            hide_next = false;
            continue;
        }

        let lower = arg.to_ascii_lowercase();
        if SENSITIVE_FLAGS.contains(&lower.as_str()) {
            output.push(arg.clone());
            hide_next = true;
            continue;
        }

        if let Some((key, _)) = arg.split_once('=') {
            let key_lower = key.to_ascii_lowercase();
            if SENSITIVE_FLAGS
                .iter()
                .any(|flag| key_lower == flag.trim_start_matches('-'))
                || key_lower.contains("token")
                || key_lower.contains("password")
                || key_lower.contains("secret")
                || key_lower.contains("api_key")
            {
                output.push(format!("{key}=***"));
                continue;
            }
        }

        output.push(arg.clone());
    }

    output.join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_flag_and_environment_secret_values() {
        let args = vec![
            "deploy".to_string(),
            "--token".to_string(),
            "abc".to_string(),
            "DATABASE_PASSWORD=hunter2".to_string(),
        ];
        assert_eq!(
            redact_command(&args),
            "deploy --token *** DATABASE_PASSWORD=***"
        );
    }
}
