use std::fs;
use std::path::PathBuf;

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
    assert!(
        release.find("actions/attest@").unwrap() < release.find("environment: release").unwrap()
    );
    assert!(!release.contains("@v4"));
    assert!(!release.contains("@stable"));

    let ci = fs::read_to_string(root().join(".github/workflows/ci.yml")).unwrap();
    assert!(!ci.contains("actions/attest@"));
    assert!(!ci.contains("gh release create"));
}
