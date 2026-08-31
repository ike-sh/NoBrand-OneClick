# SSH Tunnel contract for NoBrand-OneClick 3.1

Status: v3.1.0 security and operations contract, qualified 2026-08-31.

## Ownership boundary

SSH Tunnel reuses the machine's existing OpenSSH sshd. NoBrand does not install a second SSH daemon and does not own or rewrite the system listener, SSH firewall, host keys, administrator authorized keys, `PermitRootLogin`, port, or global authentication policy.

NoBrand owns only:

- the exact managed Match Group policy block/drop-in;
- the dedicated `nobrand-ssh-tunnel` group;
- system users recorded by account ID, username, UID, group, GECOS marker and local ownership marker;
- centralized authorized-key files and per-account Ed25519 public/private keys;
- schema-v3 SSH module state and watchdog snapshots.

An existing group or username is never adopted by name alone. Restore requires the current local ownership marker for an already-existing identity and refuses a username/UID conflict.

## Effective forwarding-only policy

The generated policy has this effective contract:

```sshconfig
Match Group nobrand-ssh-tunnel
    AuthenticationMethods publickey
    PubkeyAuthentication yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AuthorizedKeysFile /etc/nobrand-oneclick/ssh-tunnel/authorized_keys/%u
    AllowTcpForwarding yes
    AllowStreamLocalForwarding no
    GatewayPorts no
    PermitTTY no
    X11Forwarding no
    AllowAgentForwarding no
    PermitTunnel no
    PermitUserRC no
    MaxSessions 0
    ForceCommand /usr/sbin/nologin
Match all
```

The actual nologin path is selected from the target system. The block is never trusted by text inspection alone: a complete candidate must pass `sshd -t`, and `sshd -T -C user=...,host=...,addr=...` must return every required effective value.

`MaxSessions 0` denies shell, exec and subsystem channels while retaining TCP forwarding. `ForceCommand nologin`, no-PTY key options, and the other Match directives are defense in depth rather than substitutes for `MaxSessions` and explicit forwarding controls.

## Allowed and denied capabilities

Allowed:

- `ssh -N`
- `ssh -L` LocalForward over TCP
- `ssh -D` dynamic SOCKS5 CONNECT over TCP
- `ssh -R` RemoteForward over TCP

Denied:

- shell, arbitrary command execution, TTY and interactive sessions;
- SFTP, SCP and other SSH subsystems;
- X11 and agent forwarding;
- Unix stream-local forwarding;
- SSH TUN/TAP and user rc;
- password and keyboard-interactive authentication.

SSH Tunnel has no native UDP forwarding. A nested protocol must be able to operate through TCP forwarding.

## `AllowTcpForwarding=yes` tradeoff

The product deliberately uses `AllowTcpForwarding yes`, not `local`, because both local/dynamic and remote forwarding are required. A valid Tunnel account can therefore ask sshd to connect to TCP destinations reachable from the server. The module is not a destination ACL, network namespace, application firewall, or tenant sandbox. Operators must use host/network policy if users should not reach particular server-side TCP networks.

`GatewayPorts no` constrains the listening side of RemoteForward: even if a client requests `0.0.0.0` or `[::]`, sshd binds only loopback. It does not constrain the destination side of a forwarding request.

## Accounts and key handling

Each display user maps to a collision-resistant `nbt-*` Linux username with an independent UID, password lock, no normal home, nologin shell, account-ID GECOS, ownership marker, and Ed25519 keypair. Tunnel users are not added to sudo, wheel, docker, adm, or unrelated system groups.

Private keys are 0600 under root-only state and appear only through an explicit `nobrand ssh export` action. `status`, `doctor`, `nodes`, menu and normal logs do not print private keys. Authorized keys are centrally managed and include no-agent-forwarding, no-X11-forwarding and no-pty key options plus the nologin command.

The shared config root and SSH module root are 0711 so sshd can traverse them after switching to the target UID without listing directory contents. The authorized-key directory is 0755 and contains public material; account markers remain 0700/0600, and private keys remain under 0700/0600 state.

## Config strategy and reload

If the native main config includes `/etc/ssh/sshd_config.d/*.conf`, NoBrand uses the exact `90-nobrand-ssh-tunnel.conf` drop-in. Otherwise it appends one delimited marker block to the main config and preserves the rest byte-for-byte. Removal validates a complete candidate before changing either strategy.

Reload uses a live systemd service, OpenRC sshd service, or a validated `/run/sshd.pid` SIGHUP fallback. Merely finding a `systemctl` binary in a chroot is not enough to select systemd.

## Lockout watchdog and uninstall

Every install/update/restore/removal snapshots the managed target and SSH module state, validates the candidate, applies it atomically, reloads sshd, re-runs syntax/effective-policy acceptance, and arms a rollback script. Policy apply/reload failure rolls back immediately.

After a successful reload, keep the existing administrator session open. From a brand-new administrator SSH connection, run the exact command printed by NoBrand:

```text
nobrand ssh confirm-admin --token <one-time-token>
```

Confirmation from a local shell is rejected while a real watchdog is active; reusing the original `SSH_CONNECTION` is also rejected. If confirmation does not happen in time, the snapshot is restored and sshd is reloaded.

Module uninstall first removes only the managed policy and waits for new-session confirmation. Only then does it kill sessions owned by the Tunnel UIDs, delete verified users/group/keys/state, and preserve sshd/admin access. Unified uninstall follows the same first phase and does not touch any other protocol until confirmation succeeds.

## Qualification requirements

Local and real-machine acceptance must prove real `sshd -t/-T`, administrator access before/after every policy change, distinct UID/key isolation, `-L/-D/-R` data planes, loopback-only RemoteForward, shell/exec/TTY/SFTP/SCP/TUN denial, key rotation/revocation, backup/restore, watchdog rollback, two-phase uninstall, and continued system sshd/admin access.
