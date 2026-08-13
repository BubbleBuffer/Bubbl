use std::io::{Read, Write};
use std::process::{Command, Stdio};

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
        "bubl 0.1.0"
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
fn codex_hook_never_emits_secret() {
    let input = r#"{"prompt":"deploy [@bubl hook-canary]","hook_event_name":"UserPromptSubmit"}"#;
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
    let output = child.wait_with_output().unwrap();
    let stdout = String::from_utf8(output.stdout).unwrap();
    assert!(output.status.success());
    assert!(!stdout.contains("hook-canary"));
    assert!(stdout.contains("[@bubl-ref b1_"));
}
