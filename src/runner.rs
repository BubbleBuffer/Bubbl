use std::ffi::OsString;
use std::io::Write;
use std::process::{Command, Stdio};

use zeroize::{Zeroize, Zeroizing};

use crate::store::Store;
use crate::{Error, Result};

#[derive(Debug)]
pub enum Delivery {
    Stdin,
    Env(OsString),
}

pub fn run(store: &Store, token: &str, delivery: Delivery, command: &[OsString]) -> Result<i32> {
    if command.is_empty() {
        return Err(Error::InvalidInput("missing child program".to_string()));
    }

    if let Delivery::Env(name) = &delivery {
        validate_env_name(name)?;
    }

    let mut bubble = store.claim(token)?;
    let mut child_command = Command::new(&command[0]);
    child_command.args(&command[1..]);
    child_command
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());

    match &delivery {
        Delivery::Stdin => {
            child_command.stdin(Stdio::piped());
        }
        Delivery::Env(name) => {
            let value = std::str::from_utf8(bubble.secret()).map_err(|_| Error::Unavailable)?;
            child_command.env(name, value);
            child_command.stdin(Stdio::inherit());
        }
    }

    let mut child = match child_command.spawn() {
        Ok(child) => child,
        Err(error) => {
            let _ = bubble.restore();
            return Err(Error::Spawn(error));
        }
    };
    drop(child_command);

    if let Err(error) = bubble.pop() {
        let _ = child.kill();
        let _ = child.wait();
        return Err(error);
    }

    let delivery_error = if matches!(delivery, Delivery::Stdin) {
        let mut bytes = Zeroizing::new(bubble.secret().to_vec());
        let result = child
            .stdin
            .take()
            .ok_or_else(|| Error::Delivery(std::io::Error::other("child stdin was not piped")))
            .and_then(|mut stdin| stdin.write_all(&bytes).map_err(Error::Delivery));
        bytes.zeroize();
        result.err()
    } else {
        None
    };

    let status = child.wait().map_err(Error::Spawn)?;
    if let Some(error) = delivery_error {
        return Err(error);
    }
    Ok(status.code().unwrap_or(1))
}

fn validate_env_name(name: &OsString) -> Result<()> {
    let text = name.to_string_lossy();
    if text.is_empty() || text.contains('=') || text.contains('\0') {
        return Err(Error::InvalidInput(
            "environment variable name is invalid".to_string(),
        ));
    }
    Ok(())
}
