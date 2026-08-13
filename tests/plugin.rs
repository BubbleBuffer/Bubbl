use std::fs;
use std::path::PathBuf;

fn plugin_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("plugins/bubbl")
}

#[test]
fn manifest_is_minimal_and_points_to_the_skill() {
    let root = plugin_root();
    let manifest: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(root.join(".codex-plugin/plugin.json")).unwrap())
            .unwrap();
    assert_eq!(manifest["name"], "bubbl");
    assert_eq!(manifest["version"], "0.1.0");
    assert_eq!(manifest["license"], "MIT");
    assert_eq!(manifest["skills"], "./skills/");
    assert!(manifest.get("mcpServers").is_none());
    assert!(manifest.get("apps").is_none());
    assert!(manifest.get("hooks").is_none());
}

#[test]
fn hook_invokes_only_the_bundled_binary() {
    let hooks = fs::read_to_string(plugin_root().join("hooks/hooks.json")).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&hooks).unwrap();
    let handler = &parsed["hooks"]["UserPromptSubmit"][0]["hooks"][0];
    assert_eq!(handler["type"], "command");
    assert!(
        handler["command"]
            .as_str()
            .unwrap()
            .contains("${PLUGIN_ROOT}/bin/bubl")
    );
    assert!(
        handler["commandWindows"]
            .as_str()
            .unwrap()
            .contains("${PLUGIN_ROOT}\\bin\\bubl.exe")
    );
    assert!(
        handler["command"]
            .as_str()
            .unwrap()
            .ends_with(" codex-hook")
    );
}

#[test]
fn skill_is_short_and_contains_no_placeholders() {
    let root = plugin_root();
    let skill = fs::read_to_string(root.join("skills/bubl-ref/SKILL.md")).unwrap();
    let metadata = fs::read_to_string(root.join("skills/bubl-ref/agents/openai.yaml")).unwrap();
    assert!(skill.starts_with("---\nname: bubl-ref\n"));
    assert!(skill.contains("[@bubl-ref …]"));
    assert!(skill.lines().count() < 30);
    assert!(!skill.contains("TODO"));
    assert!(metadata.contains("$bubl-ref"));
}

#[test]
fn plugin_has_no_mcp_or_app_configuration() {
    let root = plugin_root();
    assert!(!root.join(".mcp.json").exists());
    assert!(!root.join(".app.json").exists());
}
