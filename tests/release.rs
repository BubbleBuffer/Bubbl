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
