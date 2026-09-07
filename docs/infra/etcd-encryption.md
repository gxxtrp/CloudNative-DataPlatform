# Kubernetes Secrets Encryption at Rest (k3s)

## Default Behaviour

k3s does **NOT** encrypt Kubernetes Secrets at rest by default.
Without encryption, `vault-unseal-keys` and any other `kind: Secret` objects are stored
plaintext in the SQLite datastore at `/var/lib/rancher/k3s/server/db/state.db`.

## What `--secrets-encryption` Does

When the flag is passed at server start, k3s:
1. Generates an AES-GCM encryption key and writes it to:
   `/var/lib/rancher/k3s/server/cred/encryption-config.json`
2. Configures the `kube-apiserver` with an `EncryptionConfiguration` that uses
   `aescbc` (or `aesgcm` in newer k3s) for all `secrets` resources.
3. All new Secrets written after this point are encrypted before reaching the datastore.

> [!IMPORTANT]
> Existing Secrets written *before* enabling encryption remain plaintext until
> you run a rewrite (Step 3 of the migration below).

---

## Fresh Cluster (default path)

The bootstrap script (`infra/bootstrap/host-bootstrap.sh`) passes `--secrets-encryption`
during install. No manual steps needed.

Verify:
```bash
sudo test -f /var/lib/rancher/k3s/server/cred/encryption-config.json && echo "ENCRYPTED" || echo "NOT ENCRYPTED"
```

---

## Enabling on an Existing Cluster (migration runbook)

> [!CAUTION]
> This restarts the k3s server process. Plan for ~30s downtime on the control plane.
> Worker nodes continue running existing workloads during the restart.

### Step 1 — Add the flag to the k3s service

```bash
# Edit the k3s ExecStart line
sudo systemctl edit k3s --force
```

Add an override:
```ini
[Service]
ExecStart=
ExecStart=/usr/local/bin/k3s server \
  --disable=traefik \
  --disable=local-storage \
  --node-name=k3s-control-plane \
  --secrets-encryption
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart k3s
```

### Step 2 — Verify encryption config was generated

```bash
sudo cat /var/lib/rancher/k3s/server/cred/encryption-config.json | python3 -m json.tool
# Should show: "name": "aescbc" or "aesgcm" provider
```

### Step 3 — Rewrite all existing Secrets so they get encrypted

Without this step, previously-written Secrets remain plaintext.

```bash
# Rewrite all Secrets across all namespaces
sudo k3s kubectl get secrets --all-namespaces -o json | \
  sudo k3s kubectl replace -f -
```

Verify a specific Secret is now encrypted (value should be base64-encoded ciphertext, not plaintext JSON):
```bash
sudo sqlite3 /var/lib/rancher/k3s/server/db/state.db \
  "SELECT hex(value) FROM kine WHERE name LIKE '%secrets%vault-unseal-keys%' LIMIT 1;" | head -c 100
# If encrypted, output starts with 'k8s:enc:aescbc:' (hex encoded)
```

### Step 4 — Key rotation (periodic ops task)

k3s provides a built-in key rotation command:
```bash
# Rotate to a new encryption key
sudo k3s secrets-encrypt rotate

# Then restart and rewrite
sudo systemctl restart k3s
sudo k3s kubectl get secrets --all-namespaces -o json | sudo k3s kubectl replace -f -

# Verify status
sudo k3s secrets-encrypt status
```

---

## Key File Location & Backup

| File | Purpose |
| --- | --- |
| `/var/lib/rancher/k3s/server/cred/encryption-config.json` | Active AES key — **back this up** |
| `/var/lib/rancher/k3s/server/db/state.db` | SQLite datastore (encrypted content) |

> [!CAUTION]
> If you lose `encryption-config.json`, all encrypted Secrets are permanently unrecoverable.
> Back up this file to a secure location (e.g., HCP Vault, offline storage) after each key rotation.

---

## Relationship to bank-vaults

bank-vaults stores the Vault unseal key in a K8s `Secret` (`vault-unseal-keys`).
`--secrets-encryption` ensures that Secret is encrypted at the datastore layer.

**Both layers are needed:**

```
vault-unseal-keys (K8s Secret)
  └─ encrypted at rest by k3s --secrets-encryption (AES-GCM)
       └─ stored in /var/lib/rancher/k3s/server/db/state.db
```
