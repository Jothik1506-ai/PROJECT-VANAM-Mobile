# packages/e2ee

End-to-end encryption logic: key generation, encrypt/decrypt, secure key
storage bindings (Keychain/Keystore).

Owner: Codex.

Hard rule from ARCHITECTURE.md: private keys never leave the device, never
touch plain SQLite, and the server never sees plaintext or private keys.
