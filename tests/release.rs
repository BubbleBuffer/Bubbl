use std::fs;
use std::path::PathBuf;
use std::process::Command;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn release_marketplace_is_local_and_stable() {
    let marketplace: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(root().join("packaging/marketplace.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(marketplace["name"], "bubbl-release");
    assert_eq!(marketplace["plugins"].as_array().unwrap().len(), 1);
    assert_eq!(marketplace["plugins"][0]["name"], "bubbl");
    assert_eq!(
        marketplace["plugins"][0]["source"]["path"],
        "./plugins/bubbl"
    );
    assert_eq!(
        marketplace["plugins"][0]["policy"]["authentication"],
        "ON_INSTALL"
    );
}

#[test]
fn installers_accept_only_verified_official_releases() {
    for name in ["install.ps1", "install.sh"] {
        let installer = fs::read_to_string(root().join(name)).unwrap();
        for required in [
            "BubbleBuffer/Bubbl",
            "--signer-workflow",
            "--source-ref",
            "--source-digest",
            "--deny-self-hosted-runners",
            "SHA256SUMS.txt",
            "BUILD-INFO.json",
            "bubbl-release",
        ] {
            assert!(installer.contains(required), "{name} lacks {required}");
        }
        for forbidden in ["raw.githubusercontent", "git clone", "cargo build"] {
            assert!(
                !installer.contains(forbidden),
                "{name} contains forbidden route {forbidden}"
            );
        }
    }
}

#[test]
fn installers_expose_simple_default_and_strict_verification() {
    let powershell = Command::new("pwsh")
        .env_remove("LOCALAPPDATA")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-File",
            root().join("install.ps1").to_str().unwrap(),
            "-Help",
        ])
        .output()
        .unwrap();
    assert!(powershell.status.success());
    let powershell_help = String::from_utf8(powershell.stdout).unwrap();
    assert!(powershell_help.contains("-Strict"));
    assert!(powershell_help.contains("does not require GitHub CLI"));

    let mut shell_path = root()
        .join("install.sh")
        .to_str()
        .unwrap()
        .replace('\\', "/");
    if cfg!(windows) {
        let drive = shell_path[..1].to_ascii_lowercase();
        shell_path = format!("/mnt/{drive}/{}", &shell_path[3..]);
    }
    let shell = Command::new("bash")
        .args([shell_path.as_str(), "--help"])
        .output()
        .unwrap();
    assert!(shell.status.success());
    let shell_help = String::from_utf8(shell.stdout).unwrap();
    assert!(shell_help.contains("--strict"));
    assert!(shell_help.contains("does not require GitHub CLI"));
}

#[test]
fn release_workflow_is_tag_only_and_attests_assets() {
    let release = fs::read_to_string(root().join(".github/workflows/release.yml")).unwrap();
    assert!(release.contains("tags: ['v*']"));
    assert!(release.contains("actions/attest@"));
    assert!(release.contains("subject-path: dist/*"));
    assert!(release.contains("environment: release"));
    assert!(release.contains("gh release edit"));
    assert!(release.contains("assemble-draft:"));
    assert!(release.contains("needs: assemble-draft"));
    assert!(release.contains("test \"${actual[*]}\" = \"${wanted[*]}\""));
    assert!(release.contains("sudo apt-get update && sudo apt-get install --yes musl-tools"));
    assert!(
        release.find("actions/attest@").unwrap() < release.find("environment: release").unwrap()
    );
    assert!(!release.contains("@v4"));
    assert!(!release.contains("@stable"));

    let ci = fs::read_to_string(root().join(".github/workflows/ci.yml")).unwrap();
    assert!(!ci.contains("actions/attest@"));
    assert!(!ci.contains("gh release create"));
}

#[test]
fn release_automation_covers_native_and_public_installation() {
    let release = fs::read_to_string(root().join(".github/workflows/release.yml")).unwrap();
    assert!(release.contains("if: matrix.target != 'x86_64-pc-windows-msvc'"));

    let shell_harness = fs::read_to_string(root().join("scripts/test-install.sh")).unwrap();
    for target in [
        "x86_64-unknown-linux-musl",
        "x86_64-apple-darwin",
        "aarch64-apple-darwin",
    ] {
        assert!(shell_harness.contains(target), "missing {target} harness");
    }
    let shell_installer = fs::read_to_string(root().join("install.sh")).unwrap();
    assert!(!shell_installer.contains("-mindepth"));
    assert!(!shell_installer.contains("-maxdepth"));

    let smoke = fs::read_to_string(root().join(".github/workflows/release-smoke.yml")).unwrap();
    for required in [
        "workflow_run:",
        "workflows: [Release]",
        "types: [completed]",
        "github.event.workflow_run.conclusion == 'success'",
        "schedule:",
        "windows-2025",
        "ubuntu-24.04",
        "macos-15-intel",
        "macos-15",
        "npm install --global @openai/codex@latest",
        "releases/download/",
        "smoke-installed.ps1",
    ] {
        assert!(smoke.contains(required), "public smoke lacks {required}");
    }

    let smoke_script = fs::read_to_string(root().join("scripts/smoke-installed.ps1")).unwrap();
    for required in [
        "plugin marketplace list --json",
        "plugin list --marketplace bubbl-release --json",
        "codex-hook",
        "--stdin",
        "--env",
        "bubble reuse unexpectedly succeeded",
    ] {
        assert!(
            smoke_script.contains(required),
            "smoke script lacks {required}"
        );
    }
}
