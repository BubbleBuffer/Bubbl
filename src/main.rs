use std::ffi::OsString;
use std::io::Read;
use std::path::PathBuf;

use bubl::runner::{self, Delivery};
use bubl::store::Store;
use bubl::{Error, Result};
use zeroize::{Zeroize, Zeroizing};

const USAGE: &str = "Usage:\n  bubl seal\n  bubl run TOKEN --stdin -- PROGRAM [ARGS...]\n  bubl run TOKEN --env NAME -- PROGRAM [ARGS...]\n  bubl codex-hook\n  bubl --version";

fn main() {
    let code = match execute() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("{}", error.public_message());
            1
        }
    };
    std::process::exit(code);
}

fn execute() -> Result<i32> {
    let mut args = std::env::args_os();
    let _program = args.next();
    let Some(command) = args.next() else {
        return Err(Error::InvalidInput(USAGE.to_string()));
    };
    let rest = args.collect::<Vec<_>>();
    let store = Store::temporary();

    match command.to_string_lossy().as_ref() {
        "--version" | "-V" if rest.is_empty() => {
            println!("bubl {}", env!("CARGO_PKG_VERSION"));
            Ok(0)
        }
        "--help" | "-h" if rest.is_empty() => {
            println!("{USAGE}");
            Ok(0)
        }
        "seal" if rest.is_empty() => seal(&store),
        "run" => run(&store, rest),
        "codex-hook" if rest.is_empty() => codex_hook(&store),
        _ => Err(Error::InvalidInput(USAGE.to_string())),
    }
}

fn seal(store: &Store) -> Result<i32> {
    let mut secret = Zeroizing::new(Vec::new());
    std::io::stdin()
        .read_to_end(&mut secret)
        .map_err(Error::Storage)?;
    let token = store.seal(&secret)?;
    println!("{token}");
    Ok(0)
}

fn run(store: &Store, args: Vec<OsString>) -> Result<i32> {
    if args.len() < 4 {
        return Err(Error::InvalidInput(USAGE.to_string()));
    }
    let token = args[0]
        .to_str()
        .ok_or_else(|| Error::InvalidInput("capability must be UTF-8".to_string()))?;
    let (delivery, separator) = match args[1].to_string_lossy().as_ref() {
        "--stdin" => (Delivery::Stdin, 2),
        "--env" if args.len() >= 5 => (Delivery::Env(args[2].clone()), 3),
        _ => return Err(Error::InvalidInput(USAGE.to_string())),
    };
    if args.get(separator).and_then(|value| value.to_str()) != Some("--") {
        return Err(Error::InvalidInput(USAGE.to_string()));
    }
    runner::run(store, token, delivery, &args[separator + 1..])
}

fn codex_hook(store: &Store) -> Result<i32> {
    let mut raw = Zeroizing::new(String::new());
    std::io::stdin()
        .read_to_string(&mut raw)
        .map_err(Error::Storage)?;
    let executable = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("bubl"));
    match bubl::codex::handle_json(&mut raw, &executable, store) {
        Ok(Some(output)) => println!("{output}"),
        Ok(None) => {}
        Err(error) => {
            raw.zeroize();
            let reason = match error {
                Error::InvalidInput(_) => "Bubbl blocked a malformed secret marker.",
                _ => "Bubbl could not seal this prompt.",
            };
            let output = serde_json::json!({ "decision": "block", "reason": reason });
            println!("{output}");
        }
    }
    Ok(0)
}
