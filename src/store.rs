use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{Key, XChaCha20Poly1305, XNonce};
use zeroize::{Zeroize, Zeroizing};

use crate::{Error, Result};

const MAGIC: &[u8; 8] = b"BUBL\x01\0\0\0";
const NONCE_LEN: usize = 24;
const HEADER_LEN: usize = MAGIC.len() + 8 + NONCE_LEN;
const TTL: Duration = Duration::from_secs(60 * 60);
const CAPABILITY_PREFIX: &str = "b1_";
const CAPABILITY_BYTES: usize = 16;

#[derive(Clone, Debug)]
pub struct Store {
    root: PathBuf,
}

impl Store {
    pub fn temporary() -> Self {
        Self::new(std::env::temp_dir().join("bubl").join("v1"))
    }

    pub fn new(root: PathBuf) -> Self {
        Self { root }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn seal(&self, secret: &[u8]) -> Result<String> {
        let expires = unix_seconds(SystemTime::now() + TTL)?;
        self.seal_until(secret, expires)
    }

    pub fn seal_batch<'a>(
        &self,
        secrets: impl IntoIterator<Item = &'a [u8]>,
    ) -> Result<Vec<String>> {
        let mut tokens = Vec::new();
        for secret in secrets {
            match self.seal(secret) {
                Ok(token) => tokens.push(token),
                Err(error) => {
                    for token in &tokens {
                        self.discard(token);
                    }
                    return Err(error);
                }
            }
        }
        Ok(tokens)
    }

    fn seal_until(&self, secret: &[u8], expires: u64) -> Result<String> {
        validate_secret(secret)?;
        self.ensure_root()?;
        self.cleanup();

        for _ in 0..4 {
            let mut capability = [0_u8; CAPABILITY_BYTES];
            getrandom::fill(&mut capability).map_err(|_| Error::Crypto)?;
            let token = format!("{CAPABILITY_PREFIX}{}", URL_SAFE_NO_PAD.encode(capability));
            let paths = self.paths(&capability);

            if paths.ready.exists() || paths.claimed.exists() {
                capability.zeroize();
                continue;
            }

            let mut key = derive_key("bubbl v1 encryption key", &capability);
            let mut nonce = [0_u8; NONCE_LEN];
            getrandom::fill(&mut nonce).map_err(|_| Error::Crypto)?;
            let aad = aad(expires);
            let cipher = XChaCha20Poly1305::new(Key::from_slice(&key));
            let ciphertext = cipher
                .encrypt(
                    XNonce::from_slice(&nonce),
                    Payload {
                        msg: secret,
                        aad: &aad,
                    },
                )
                .map_err(|_| Error::Crypto)?;
            key.zeroize();
            capability.zeroize();

            let mut blob = Vec::with_capacity(HEADER_LEN + ciphertext.len());
            blob.extend_from_slice(MAGIC);
            blob.extend_from_slice(&expires.to_le_bytes());
            blob.extend_from_slice(&nonce);
            blob.extend_from_slice(&ciphertext);
            self.write_atomic(&paths.ready, &blob)?;
            blob.zeroize();
            return Ok(token);
        }

        Err(Error::Crypto)
    }

    pub fn claim(&self, token: &str) -> Result<ClaimedBubble> {
        self.ensure_root().map_err(|_| Error::Unavailable)?;
        self.cleanup();
        let mut capability = decode_capability(token).ok_or(Error::Unavailable)?;
        let paths = self.paths(&capability);

        fs::hard_link(&paths.ready, &paths.claimed).map_err(|_| Error::Unavailable)?;
        if fs::remove_file(&paths.ready).is_err() {
            let _ = fs::remove_file(&paths.claimed);
            return Err(Error::Unavailable);
        }
        let result = self.read_claimed(&paths.claimed, &capability);
        capability.zeroize();

        match result {
            Ok(secret) => Ok(ClaimedBubble {
                secret,
                ready: paths.ready,
                claimed: paths.claimed,
                popped: false,
            }),
            Err(_) => {
                let _ = fs::remove_file(paths.claimed);
                Err(Error::Unavailable)
            }
        }
    }

    pub fn discard(&self, token: &str) {
        if let Some(mut capability) = decode_capability(token) {
            let paths = self.paths(&capability);
            let _ = fs::remove_file(paths.ready);
            let _ = fs::remove_file(paths.claimed);
            capability.zeroize();
        }
    }

    fn read_claimed(
        &self,
        path: &Path,
        capability: &[u8; CAPABILITY_BYTES],
    ) -> Result<Zeroizing<Vec<u8>>> {
        let mut blob = Vec::new();
        File::open(path)
            .and_then(|mut file| file.read_to_end(&mut blob))
            .map_err(Error::Storage)?;
        if blob.len() <= HEADER_LEN || &blob[..MAGIC.len()] != MAGIC {
            blob.zeroize();
            return Err(Error::Unavailable);
        }

        let expires = u64::from_le_bytes(
            blob[MAGIC.len()..MAGIC.len() + 8]
                .try_into()
                .map_err(|_| Error::Unavailable)?,
        );
        if unix_seconds(SystemTime::now())? >= expires {
            blob.zeroize();
            return Err(Error::Unavailable);
        }

        let nonce_start = MAGIC.len() + 8;
        let nonce_end = nonce_start + NONCE_LEN;
        let mut key = derive_key("bubbl v1 encryption key", capability);
        let cipher = XChaCha20Poly1305::new(Key::from_slice(&key));
        let plaintext = cipher
            .decrypt(
                XNonce::from_slice(&blob[nonce_start..nonce_end]),
                Payload {
                    msg: &blob[nonce_end..],
                    aad: &aad(expires),
                },
            )
            .map_err(|_| Error::Unavailable);
        key.zeroize();
        blob.zeroize();
        plaintext.map(Zeroizing::new)
    }

    fn ensure_root(&self) -> Result<()> {
        fs::create_dir_all(&self.root).map_err(Error::Storage)?;
        set_directory_permissions(&self.root).map_err(Error::Storage)
    }

    fn write_atomic(&self, ready: &Path, bytes: &[u8]) -> Result<()> {
        let mut suffix = [0_u8; 8];
        getrandom::fill(&mut suffix).map_err(|_| Error::Crypto)?;
        let temp = self
            .root
            .join(format!(".{}.tmp", URL_SAFE_NO_PAD.encode(suffix)));
        let result = (|| {
            let mut file = secure_create(&temp)?;
            file.write_all(bytes).map_err(Error::Storage)?;
            file.sync_all().map_err(Error::Storage)?;
            drop(file);
            fs::rename(&temp, ready).map_err(Error::Storage)
        })();
        if result.is_err() {
            let _ = fs::remove_file(temp);
        }
        result
    }

    fn paths(&self, capability: &[u8; CAPABILITY_BYTES]) -> Paths {
        let name = blake3::derive_key("bubbl v1 storage name", capability);
        let stem = name
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        Paths {
            ready: self.root.join(format!("{stem}.ready")),
            claimed: self.root.join(format!("{stem}.claimed")),
        }
    }

    fn cleanup(&self) {
        let Ok(entries) = fs::read_dir(&self.root) else {
            return;
        };
        let now = SystemTime::now();
        for entry in entries.flatten() {
            let path = entry.path();
            let extension = path.extension().and_then(|value| value.to_str());
            if !matches!(extension, Some("ready" | "claimed" | "tmp")) {
                continue;
            }
            let expired = match extension {
                Some("ready" | "claimed") => read_expiration(&path)
                    .ok()
                    .and_then(|expires| unix_seconds(now).ok().map(|now| now >= expires))
                    .unwrap_or(true),
                Some("tmp") => entry
                    .metadata()
                    .and_then(|metadata| metadata.modified())
                    .ok()
                    .and_then(|modified| now.duration_since(modified).ok())
                    .is_some_and(|age| age >= TTL),
                _ => false,
            };
            if expired {
                let _ = fs::remove_file(path);
            }
        }
    }
}

pub struct ClaimedBubble {
    secret: Zeroizing<Vec<u8>>,
    ready: PathBuf,
    claimed: PathBuf,
    popped: bool,
}

impl ClaimedBubble {
    pub fn secret(&self) -> &[u8] {
        &self.secret
    }

    pub fn pop(&mut self) -> Result<()> {
        fs::remove_file(&self.claimed).map_err(Error::Storage)?;
        self.popped = true;
        Ok(())
    }

    pub fn restore(mut self) -> Result<()> {
        fs::hard_link(&self.claimed, &self.ready).map_err(Error::Storage)?;
        fs::remove_file(&self.claimed).map_err(Error::Storage)?;
        self.popped = true;
        Ok(())
    }
}

struct Paths {
    ready: PathBuf,
    claimed: PathBuf,
}

fn validate_secret(secret: &[u8]) -> Result<()> {
    if secret.is_empty()
        || secret.contains(&b'\n')
        || secret.contains(&b'\r')
        || secret.contains(&0)
        || std::str::from_utf8(secret).is_err()
    {
        return Err(Error::InvalidInput(
            "secret must be non-empty, single-line UTF-8 without NUL".to_string(),
        ));
    }
    Ok(())
}

fn decode_capability(token: &str) -> Option<[u8; CAPABILITY_BYTES]> {
    let encoded = token.strip_prefix(CAPABILITY_PREFIX)?;
    if encoded.len() != 22 {
        return None;
    }
    let decoded = URL_SAFE_NO_PAD.decode(encoded).ok()?;
    decoded.try_into().ok()
}

fn derive_key(context: &str, capability: &[u8]) -> [u8; 32] {
    blake3::derive_key(context, capability)
}

fn aad(expires: u64) -> Vec<u8> {
    let mut value = Vec::with_capacity(MAGIC.len() + 8);
    value.extend_from_slice(MAGIC);
    value.extend_from_slice(&expires.to_le_bytes());
    value
}

fn unix_seconds(time: SystemTime) -> Result<u64> {
    time.duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .map_err(|_| Error::Crypto)
}

fn read_expiration(path: &Path) -> std::io::Result<u64> {
    let mut header = [0_u8; MAGIC.len() + 8];
    let mut file = File::open(path)?;
    file.read_exact(&mut header)?;
    if &header[..MAGIC.len()] != MAGIC {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "invalid bubble header",
        ));
    }
    Ok(u64::from_le_bytes(
        header[MAGIC.len()..].try_into().expect("fixed header"),
    ))
}

fn secure_create(path: &Path) -> Result<File> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(path).map_err(Error::Storage)
}

#[cfg(unix)]
fn set_directory_permissions(path: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))
}

#[cfg(not(unix))]
fn set_directory_permissions(_path: &Path) -> std::io::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Barrier};

    use super::*;

    fn store() -> (tempfile::TempDir, Store) {
        let temp = tempfile::tempdir().unwrap();
        let store = Store::new(temp.path().join("store"));
        (temp, store)
    }

    #[test]
    fn round_trip_and_pop_are_one_use() {
        let (_temp, store) = store();
        let token = store.seal(b"canary-secret").unwrap();
        let mut claim = store.claim(&token).unwrap();
        assert_eq!(claim.secret(), b"canary-secret");
        claim.pop().unwrap();
        assert!(matches!(store.claim(&token), Err(Error::Unavailable)));
    }

    #[test]
    fn ciphertext_and_filename_do_not_contain_plaintext() {
        let (_temp, store) = store();
        let token = store.seal(b"needle-secret").unwrap();
        let entries = fs::read_dir(store.root()).unwrap().collect::<Vec<_>>();
        assert_eq!(entries.len(), 1);
        let entry = entries[0].as_ref().unwrap();
        assert!(!entry.file_name().to_string_lossy().contains("needle"));
        let bytes = fs::read(entry.path()).unwrap();
        assert!(
            !bytes
                .windows(b"needle-secret".len())
                .any(|w| w == b"needle-secret")
        );
        store.discard(&token);
    }

    #[test]
    fn tampering_and_expiry_have_same_public_error() {
        let (_temp, store) = store();
        let token = store.seal(b"secret").unwrap();
        let mut capability = decode_capability(&token).unwrap();
        let path = store.paths(&capability).ready;
        capability.zeroize();
        let mut bytes = fs::read(&path).unwrap();
        *bytes.last_mut().unwrap() ^= 1;
        fs::write(path, bytes).unwrap();
        assert_eq!(
            store.claim(&token).err().unwrap().public_message(),
            "bubl: bubble unavailable"
        );

        let expired = store.seal_until(b"secret", 1).unwrap();
        assert_eq!(
            store.claim(&expired).err().unwrap().public_message(),
            "bubl: bubble unavailable"
        );
    }

    #[test]
    fn failed_claim_can_be_restored() {
        let (_temp, store) = store();
        let token = store.seal(b"secret").unwrap();
        store.claim(&token).unwrap().restore().unwrap();
        assert!(store.claim(&token).is_ok());
    }

    #[test]
    fn only_one_concurrent_claim_succeeds() {
        let (_temp, store) = store();
        let token = store.seal(b"secret").unwrap();
        let store = Arc::new(store);
        let barrier = Arc::new(Barrier::new(3));
        let handles = (0..2)
            .map(|_| {
                let store = Arc::clone(&store);
                let barrier = Arc::clone(&barrier);
                let token = token.clone();
                std::thread::spawn(move || {
                    barrier.wait();
                    store.claim(&token).is_ok()
                })
            })
            .collect::<Vec<_>>();
        barrier.wait();
        assert_eq!(
            handles
                .into_iter()
                .map(|handle| handle.join().unwrap())
                .filter(|claimed| *claimed)
                .count(),
            1
        );
    }
}
