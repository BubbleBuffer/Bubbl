use std::io::{Read, Write};
use std::process::{Command, Output, Stdio};

fn bubl() -> Command {
    Command::new(env!("CARGO_BIN_EXE_bubl"))
}

fn seal(secret: &str) -> String {
    let mut child = bubl()
        .arg("seal")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(secret.as_bytes())
        .unwrap();
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    String::from_utf8(output.stdout).unwrap().trim().to_string()
}

fn fixture_command(mode: &str) -> Vec<String> {
    vec![
        std::env::current_exe()
            .unwrap()
            .to_string_lossy()
            .into_owned(),
        "--exact".to_string(),
        "cli_fixture".to_string(),
        "--nocapture".to_string(),
        "--test-threads=1".to_string(),
        mode.to_string(),
    ]
}

fn run_hook(input: &str) -> Output {
    let mut child = bubl()
        .arg("codex-hook")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(input.as_bytes())
        .unwrap();
    child.wait_with_output().unwrap()
}

fn hook_token(stdout: &str) -> String {
    let parsed: serde_json::Value = serde_json::from_str(stdout).unwrap();
    let context = parsed["hookSpecificOutput"]["additionalContext"]
        .as_str()
        .unwrap();
    context
        .split_once("[@bubl-ref ")
        .unwrap()
        .1
        .split_once(']')
        .unwrap()
        .0
        .to_string()
}

#[test]
fn cli_fixture() {
    let mode = std::env::args().next_back().unwrap_or_default();
    match mode.as_str() {
        "stdin" => {
            let mut value = String::new();
            std::io::stdin().read_to_string(&mut value).unwrap();
            println!("BUBL_FIXTURE:{}:{}", value.len(), value == "exact secret");
        }
        "stdin-length" => {
            let mut value = String::new();
            std::io::stdin().read_to_string(&mut value).unwrap();
            println!("BUBL_FIXTURE:{}", value.len());
        }
        "env-exit" => {
            let value = std::env::var("BUBL_TEST_VALUE").unwrap();
            println!("BUBL_FIXTURE:{}", value.len());
            std::process::exit(7);
        }
        _ => {}
    }
}

#[test]
fn version_has_expected_shape() {
    let output = bubl().arg("--version").output().unwrap();
    assert_eq!(
        String::from_utf8(output.stdout).unwrap().trim(),
        "bubl 1.0.4"
    );
}

#[test]
fn stdin_delivery_is_exact_and_one_use() {
    let token = seal("exact secret");
    let fixture = fixture_command("stdin");
    let output = bubl()
        .args(["run", &token, "--stdin", "--"])
        .args(&fixture)
        .output()
        .unwrap();
    assert!(output.status.success());
    assert!(
        String::from_utf8(output.stdout)
            .unwrap()
            .contains("BUBL_FIXTURE:12:true")
    );

    let fixture = fixture_command("stdin-length");
    let second = bubl()
        .args(["run", &token, "--stdin", "--"])
        .args(&fixture)
        .output()
        .unwrap();
    assert!(!second.status.success());
    assert_eq!(
        String::from_utf8(second.stderr).unwrap().trim(),
        "bubl: bubble unavailable"
    );
}

#[test]
fn environment_delivery_and_exit_status_work() {
    let token = seal("env secret");
    let fixture = fixture_command("env-exit");
    let output = bubl()
        .args(["run", &token, "--env", "BUBL_TEST_VALUE", "--"])
        .args(&fixture)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(7));
    assert!(
        String::from_utf8(output.stdout)
            .unwrap()
            .contains("BUBL_FIXTURE:10")
    );
}

#[test]
fn spawn_failure_restores_bubble() {
    let token = seal("retry secret");
    let failed = bubl()
        .args([
            "run",
            &token,
            "--stdin",
            "--",
            "definitely-not-a-real-bubl-program",
        ])
        .output()
        .unwrap();
    assert!(!failed.status.success());

    let fixture = fixture_command("stdin-length");
    let retry = bubl()
        .args(["run", &token, "--stdin", "--"])
        .args(&fixture)
        .output()
        .unwrap();
    assert!(retry.status.success());
    assert!(
        String::from_utf8(retry.stdout)
            .unwrap()
            .contains("BUBL_FIXTURE:12")
    );
}

#[test]
fn codex_hook_to_stdin_delivery_is_sanitized_and_one_use() {
    let input = serde_json::json!({
        "cwd": "/workspace",
        "hook_event_name": "UserPromptSubmit",
        "model": "gpt-5.6-sol",
        "permission_mode": "dontAsk",
        "prompt": "deploy [@bubl exact secret]",
        "session_id": "session",
        "transcript_path": null,
        "turn_id": "turn"
    })
    .to_string();
    let output = run_hook(&input);
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert!(output.status.success());
    assert!(output.stderr.is_empty());
    assert!(!stdout.contains("exact secret"));
    assert!(stdout.contains("[@bubl-ref b1_"));
    let parsed: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert_eq!(parsed["decision"], "block");

    let token = hook_token(&stdout);
    let fixture = fixture_command("stdin");
    let delivered = bubl()
        .args(["run", &token, "--stdin", "--"])
        .args(&fixture)
        .output()
        .unwrap();
    assert!(delivered.status.success());
    assert!(
        String::from_utf8(delivered.stdout)
            .unwrap()
            .contains("BUBL_FIXTURE:12:true")
    );

    let reused = bubl()
        .args(["run", &token, "--stdin", "--"])
        .args(fixture_command("stdin-length"))
        .output()
        .unwrap();
    assert!(!reused.status.success());
    assert_eq!(
        String::from_utf8(reused.stderr).unwrap().trim(),
        "bubl: bubble unavailable"
    );
}

#[test]
fn hook_is_quiet_for_ordinary_prompts_and_fails_closed_without_disclosure() {
    let ordinary = serde_json::json!({
        "prompt": "ordinary prompt",
        "hook_event_name": "UserPromptSubmit",
        "extra_future_field": true
    })
    .to_string();
    let output = run_hook(&ordinary);
    assert!(output.status.success());
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());

    for input in [
        serde_json::json!({"prompt": "bad [@bubl multi\nline]"}).to_string(),
        r#"{"prompt":"bad [@bubl invalid-json]""#.to_string(),
    ] {
        let output = run_hook(&input);
        let stdout = String::from_utf8(output.stdout).unwrap();
        assert!(output.status.success());
        assert!(output.stderr.is_empty());
        assert!(!stdout.contains("multi"));
        assert!(!stdout.contains("invalid-json"));
        let parsed: serde_json::Value = serde_json::from_str(&stdout).unwrap();
        assert_eq!(parsed["decision"], "block");
    }
}

#[test]
fn invalid_environment_name_does_not_consume_the_bubble() {
    let token = seal("retry secret");
    let rejected = bubl()
        .args(["run", &token, "--env", "BAD=NAME", "--"])
        .args(fixture_command("stdin-length"))
        .output()
        .unwrap();
    assert!(!rejected.status.success());
    assert_eq!(
        String::from_utf8(rejected.stderr).unwrap().trim(),
        "bubl: environment variable name is invalid"
    );

    let retry = bubl()
        .args(["run", &token, "--stdin", "--"])
        .args(fixture_command("stdin-length"))
        .output()
        .unwrap();
    assert!(retry.status.success());
    assert!(
        String::from_utf8(retry.stdout)
            .unwrap()
            .contains("BUBL_FIXTURE:12")
    );
}

#[test]
fn malformed_cli_shapes_return_only_usage() {
    for args in [
        vec!["run"],
        vec!["seal", "extra"],
        vec!["--version", "extra"],
        vec!["unknown"],
    ] {
        let output = bubl().args(args).output().unwrap();
        assert!(!output.status.success());
        assert!(output.stdout.is_empty());
        assert!(
            String::from_utf8(output.stderr)
                .unwrap()
                .starts_with("bubl: Usage:")
        );
    }
}
