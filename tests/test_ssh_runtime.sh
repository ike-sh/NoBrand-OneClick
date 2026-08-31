#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

prepare_sshd_runtime() {
  if command -v sshd >/dev/null 2>&1; then
    NOBRAND_TEST_SSHD="$(command -v sshd)"
    NOBRAND_TEST_SSHD_LIBS=""
    export NOBRAND_TEST_SSHD NOBRAND_TEST_SSHD_LIBS
    return
  fi
  command -v apt-get >/dev/null 2>&1 && command -v dpkg-deb >/dev/null 2>&1 \
    || fail 'real OpenSSH server unavailable and no apt/dpkg extraction fallback exists'
  local cache="${NOBRAND_RUNTIME_CACHE:-/tmp/nobrand-runtime-cache}/openssh-server"
  local lists="$cache/lists" archives="$cache/archives" packages="$cache/packages" root="$cache/root"
  mkdir -p "$lists/partial" "$archives/partial" "$packages" "$root"
  if [ ! -x "$root/usr/sbin/sshd" ]; then
    apt-get -o "Dir::State::Lists=$lists" -o "Dir::Cache=$archives" \
      -o APT::Sandbox::User=root update >/dev/null
    (
      cd "$packages"
      apt-get -o "Dir::State::Lists=$lists" -o "Dir::Cache=$archives" \
        -o APT::Sandbox::User=root download openssh-server libwrap0 >/dev/null
    )
    local package
    for package in "$packages"/*.deb; do
      dpkg-deb -x "$package" "$root"
    done
  fi
  NOBRAND_TEST_SSHD="$root/usr/sbin/sshd"
  NOBRAND_TEST_SSHD_LIBS="$root/lib/x86_64-linux-gnu:$root/usr/lib/x86_64-linux-gnu"
  LD_LIBRARY_PATH="${NOBRAND_TEST_SSHD_LIBS}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$NOBRAND_TEST_SSHD" -V >/dev/null 2>&1 \
    || fail 'extracted OpenSSH server is not executable in this environment'
  export NOBRAND_TEST_SSHD NOBRAND_TEST_SSHD_LIBS
}

if [ "${NOBRAND_SSH_RUNTIME_INNER:-0}" != 1 ]; then
  prepare_sshd_runtime
  export NOBRAND_SSH_RUNTIME_INNER=1
  if [ "$(id -u)" -eq 0 ] && [ "$(cat /proc/self/setgroups 2>/dev/null || true)" != deny ]; then
    exec unshare -m bash "$0"
  elif command -v wsl.exe >/dev/null 2>&1 && [ -n "${WSL_DISTRO_NAME:-}" ]; then
    runtime_script="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"
    exec wsl.exe -d "$WSL_DISTRO_NAME" -u root -- unshare -m env \
      NOBRAND_SSH_RUNTIME_INNER=1 \
      "NOBRAND_TEST_SSHD=$NOBRAND_TEST_SSHD" \
      "NOBRAND_TEST_SSHD_LIBS=$NOBRAND_TEST_SSHD_LIBS" \
      "NOBRAND_RUNTIME_CACHE=${NOBRAND_RUNTIME_CACHE:-/tmp/nobrand-runtime-cache}" \
      "PATH=$PATH" \
      bash "$runtime_script"
  else
    fail 'real OpenSSH runtime test requires root or a root-capable WSL mount namespace'
  fi
fi

fixture="$(mktemp -d)"
chmod 0711 "$fixture"
sshd_pid="" target_pid="" tunnel_pid=""
cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -s "$fixture/sshd.log" ]; then
    printf '%s\n' '--- OpenSSH runtime log (failure) ---' >&2
    sed -n '1,160p' "$fixture/sshd.log" >&2 || true
  fi
  [ -z "$tunnel_pid" ] || kill "$tunnel_pid" >/dev/null 2>&1 || true
  [ -z "$target_pid" ] || kill "$target_pid" >/dev/null 2>&1 || true
  [ -z "$sshd_pid" ] || kill "$sshd_pid" >/dev/null 2>&1 || true
  wait >/dev/null 2>&1 || true
  mountpoint -q /etc && umount /etc || true
  mountpoint -q /run && umount /run || true
  rm -rf -- "$fixture"
}
trap cleanup EXIT

for command_name in ssh ssh-keygen sftp scp python3 ss mount mountpoint getent; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "SSH runtime dependency missing: $command_name"
done
LD_LIBRARY_PATH="${NOBRAND_TEST_SSHD_LIBS}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
alice_uid=49001
bob_uid=49002
tunnel_gid=49000
getent passwd "$alice_uid" >/dev/null 2>&1 && fail "SSH runtime UID already exists: $alice_uid"
getent passwd "$bob_uid" >/dev/null 2>&1 && fail "SSH runtime UID already exists: $bob_uid"
getent group "$tunnel_gid" >/dev/null 2>&1 && fail "SSH runtime GID already exists: $tunnel_gid"

mkdir -p "$fixture/run/sshd" "$fixture/auth" "$fixture/keys" "$fixture/host" "$fixture/etc"
chmod 0755 "$fixture/run/sshd"
cp -a /etc/. "$fixture/etc/"
printf '%s\n' \
  'sshd:x:65534:65534:OpenSSH privilege separation:/run/sshd:/usr/sbin/nologin' \
  "nbt-alice:x:${alice_uid}:${tunnel_gid}:NoBrand SSH Tunnel a1111111111111111:/nonexistent:/usr/sbin/nologin" \
  "nbt-bob:x:${bob_uid}:${tunnel_gid}:NoBrand SSH Tunnel a2222222222222222:/nonexistent:/usr/sbin/nologin" \
  >>"$fixture/etc/passwd"
printf 'nobrand-ssh-tunnel:x:%s:nbt-alice,nbt-bob\n' "$tunnel_gid" >>"$fixture/etc/group"
mount --bind "$fixture/etc" /etc
mount --bind "$fixture/run" /run
getent passwd nbt-alice >/dev/null || fail 'synthetic OpenSSH Alice account lookup'
getent group nobrand-ssh-tunnel >/dev/null || fail 'synthetic OpenSSH tunnel group lookup'

free_tcp_port() {
  python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

wait_tcp() {
  local port="$1"
  for _ in {1..60}; do
    ss -lntH "sport = :${port}" | grep -q . && return 0
    sleep 0.1
  done
  return 1
}

stop_tunnel() {
  [ -z "$tunnel_pid" ] || kill "$tunnel_pid" >/dev/null 2>&1 || true
  [ -z "$tunnel_pid" ] || wait "$tunnel_pid" >/dev/null 2>&1 || true
  tunnel_pid=""
}

sshd_port="$(free_tcp_port)"
target_port="$(free_tcp_port)"
ssh-keygen -q -t ed25519 -N '' -f "$fixture/host/ssh_host_ed25519_key"
ssh-keygen -q -t ed25519 -N '' -f "$fixture/keys/admin"
ssh-keygen -q -t ed25519 -N '' -f "$fixture/keys/alice"
ssh-keygen -q -t ed25519 -N '' -f "$fixture/keys/bob"
cp "$fixture/keys/admin.pub" "$fixture/auth/admin"
chmod 0600 "$fixture/auth/admin"

sshd_config="$fixture/sshd_config"
cat >"$sshd_config" <<EOF
Port ${sshd_port}
ListenAddress 127.0.0.1
PidFile ${fixture}/sshd.pid
HostKey ${fixture}/host/ssh_host_ed25519_key
AuthorizedKeysFile ${fixture}/auth/admin
StrictModes no
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM no
UseDNS no
PrintMotd no
X11Forwarding no
AllowAgentForwarding no
PermitTunnel no
PermitUserRC no
Subsystem sftp internal-sftp
LogLevel VERBOSE
EOF
chmod 0600 "$sshd_config"
"$NOBRAND_TEST_SSHD" -t -f "$sshd_config" || fail 'real OpenSSH base config syntax'
"$NOBRAND_TEST_SSHD" -D -e -f "$sshd_config" >"$fixture/sshd.log" 2>&1 &
sshd_pid=$!
wait_tcp "$sshd_port" || {
  sed -n '1,120p' "$fixture/sshd.log" >&2 || true
  fail 'real OpenSSH test daemon startup'
}

known_hosts="$fixture/known_hosts"
awk -v host="[127.0.0.1]:${sshd_port}" '{print host" "$1" "$2}' \
  "$fixture/host/ssh_host_ed25519_key.pub" >"$known_hosts"
ssh_base=(ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -o "UserKnownHostsFile=$known_hosts" -o ConnectTimeout=5 -p "$sshd_port")
sftp_base=(sftp -q -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -o "UserKnownHostsFile=$known_hosts" -o ConnectTimeout=5 -P "$sshd_port")
scp_base=(scp -q -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -o "UserKnownHostsFile=$known_hosts" -o ConnectTimeout=5 -P "$sshd_port")
"${ssh_base[@]}" -i "$fixture/keys/admin" root@127.0.0.1 true \
  || fail 'administrator key authentication before NoBrand policy'

export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_SSH_CONFIG_MAIN="$sshd_config"
export NOBRAND_SSH_CONFIG_DROPIN="$fixture/sshd_config.d/90-nobrand-ssh-tunnel.conf"
export NOBRAND_SSHD_BIN="$NOBRAND_TEST_SSHD"
source_installer
nb_init_state_layout
chmod 0711 "$fixture/nobrand-oneclick"
mkdir -p "$NOBRAND_SSH_KEYS_DIR/a1111111111111111" "$NOBRAND_SSH_KEYS_DIR/a2222222222222222" \
  "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR"
chmod 0700 "$NOBRAND_SSH_KEYS_DIR/a1111111111111111" "$NOBRAND_SSH_KEYS_DIR/a2222222222222222" \
  "$NOBRAND_SSH_ACCOUNT_MARKER_DIR"
chmod 0755 "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR"
cp "$fixture/keys/alice" "$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519"
cp "$fixture/keys/alice.pub" "$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519.pub"
cp "$fixture/keys/bob" "$NOBRAND_SSH_KEYS_DIR/a2222222222222222/id_ed25519"
cp "$fixture/keys/bob.pub" "$NOBRAND_SSH_KEYS_DIR/a2222222222222222/id_ed25519.pub"
chmod 0600 "$NOBRAND_SSH_KEYS_DIR"/*/id_ed25519
chmod 0644 "$NOBRAND_SSH_KEYS_DIR"/*/id_ed25519.pub
alice_fp="$(ssh_tunnel_key_fingerprint "$fixture/keys/alice.pub")"
bob_fp="$(ssh_tunnel_key_fingerprint "$fixture/keys/bob.pub")"
alice_user="$(ssh_tunnel_user_json a1111111111111111 alice nbt-alice "$alice_uid" "$alice_fp" 2026-08-30T00:00:00Z)"
bob_user="$(ssh_tunnel_user_json a2222222222222222 bob nbt-bob "$bob_uid" "$bob_fp" 2026-08-30T00:00:00Z)"
users="[$alice_user,$bob_user]"
ssh_tunnel_generate_state "$NOBRAND_SSH_STATE_FILE" custom 127.0.0.1 "$sshd_port" "$sshd_port" \
  marker-block "$NOBRAND_SSH_CONFIG_MAIN" "$users" 2026-08-30T00:00:00Z
ssh_tunnel_authorized_key_line "$fixture/keys/alice.pub" /usr/sbin/nologin \
  >"$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/nbt-alice"
ssh_tunnel_authorized_key_line "$fixture/keys/bob.pub" /usr/sbin/nologin \
  >"$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/nbt-bob"
chmod 0644 "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR"/nbt-*
jq -n --argjson gid "$tunnel_gid" \
  '{schema_version:3,ownership:"nobrand-v3",group:"nobrand-ssh-tunnel",gid:$gid}' \
  >"$NOBRAND_SSH_GROUP_MARKER"
for row in 'nbt-alice|a1111111111111111' 'nbt-bob|a2222222222222222'; do
  linux_user="${row%%|*}" account_id="${row#*|}"
  uid="$alice_uid"
  [ "$linux_user" != nbt-bob ] || uid="$bob_uid"
  jq -n --arg account_id "$account_id" --arg linux_user "$linux_user" --argjson uid "$uid" \
    '{schema_version:3,ownership:"nobrand-v3",account_id:$account_id,linux_user:$linux_user,uid:$uid}' \
    >"$NOBRAND_SSH_ACCOUNT_MARKER_DIR/${linux_user}.json"
done
chmod 0600 "$NOBRAND_SSH_GROUP_MARKER" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR"/*.json

ssh_tunnel_reload() { kill -HUP "$sshd_pid"; sleep 0.3; kill -0 "$sshd_pid"; }
ssh_tunnel_detect_service() { printf 'sighup|%s' "$sshd_pid"; }
NOBRAND_SSH_WATCHDOG_DISABLED=1 ssh_tunnel_apply_policy nbt-alice install >/dev/null
ssh_tunnel_effective_policy_valid "$NOBRAND_SSH_CONFIG_MAIN" nbt-alice \
  || fail 'real sshd -T forwarding-only policy validation'
ssh_tunnel_user_identity_valid "$alice_user" || fail 'real SSH Alice identity tuple'
ssh_tunnel_user_identity_valid "$bob_user" || fail 'real SSH Bob identity tuple'

python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" echo-server --protocol tcp \
  --port "$target_port" >"$fixture/target.log" 2>&1 &
target_pid=$!
wait_tcp "$target_port" || fail 'SSH controlled TCP echo target'

start_forward() {
  local key="$1" user="$2"
  shift 2
  stop_tunnel
  "${ssh_base[@]}" -o ExitOnForwardFailure=yes -o ServerAliveInterval=3 \
    -o ServerAliveCountMax=2 -i "$key" -N "$@" "$user"@127.0.0.1 \
    >"$fixture/tunnel.log" 2>&1 &
  tunnel_pid=$!
  sleep 0.5
  kill -0 "$tunnel_pid" 2>/dev/null || {
    sed -n '1,100p' "$fixture/tunnel.log" >&2 || true
    fail "SSH forwarding startup for $user"
  }
}

direct_echo_probe() {
  local port="$1"
  python3 - "$port" <<'PY'
import socket, sys
payload = bytes((i * 17) % 251 for i in range(131072))
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), 5) as stream:
    stream.sendall(payload)
    data = bytearray()
    while len(data) < len(payload):
        chunk = stream.recv(len(payload) - len(data))
        if not chunk:
            raise SystemExit("unexpected EOF")
        data.extend(chunk)
if bytes(data) != payload:
    raise SystemExit("payload mismatch")
PY
}

local_port="$(free_tcp_port)"
start_forward "$fixture/keys/alice" nbt-alice -L "127.0.0.1:${local_port}:127.0.0.1:${target_port}"
wait_tcp "$local_port" && direct_echo_probe "$local_port" || fail 'SSH -L TCP byte integrity'

socks_port="$(free_tcp_port)"
start_forward "$fixture/keys/alice" nbt-alice -D "127.0.0.1:${socks_port}"
wait_tcp "$socks_port" || fail 'SSH -D SOCKS listener'
python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" tcp --proxy-port "$socks_port" \
  --target-port "$target_port" --size 131072 || fail 'SSH -D SOCKS TCP data plane'

remote_port="$(free_tcp_port)"
start_forward "$fixture/keys/alice" nbt-alice -R "127.0.0.1:${remote_port}:127.0.0.1:${target_port}"
wait_tcp "$remote_port" && direct_echo_probe "$remote_port" || fail 'SSH -R loopback TCP data plane'

public_remote_port="$(free_tcp_port)"
start_forward "$fixture/keys/alice" nbt-alice -R "0.0.0.0:${public_remote_port}:127.0.0.1:${target_port}"
wait_tcp "$public_remote_port" || fail 'SSH requested remote-forward listener'
remote_bind_addresses="$(ss -lntH "sport = :${public_remote_port}" | awk '{print $4}')"
while IFS= read -r bind_address; do
  case "$bind_address" in
    127.0.0.1:*|'[::1]:'*) ;;
    *) fail "GatewayPorts=no allowed non-loopback RemoteForward listener: $bind_address" ;;
  esac
done <<<"$remote_bind_addresses"
printf '[PASS] real OpenSSH -N/-L/-D/-R and REMOTE_FORWARD_PUBLIC_EXPOSURE=false\n'
stop_tunnel

if timeout 3 "${ssh_base[@]}" -i "$fixture/keys/alice" nbt-alice@127.0.0.1 id \
     >/dev/null 2>&1; then fail 'SSH Tunnel exec must be denied'; fi
if timeout 3 "${ssh_base[@]}" -tt -i "$fixture/keys/alice" nbt-alice@127.0.0.1 \
     >/dev/null 2>&1; then fail 'SSH Tunnel TTY/session must be denied'; fi
if printf 'quit\n' | timeout 3 "${sftp_base[@]}" -i "$fixture/keys/alice" nbt-alice@127.0.0.1 \
     >/dev/null 2>&1; then fail 'SSH Tunnel SFTP must be denied'; fi
printf '%s\n' test >"$fixture/scp-source"
if timeout 3 "${scp_base[@]}" -i "$fixture/keys/alice" "$fixture/scp-source" \
     nbt-alice@127.0.0.1:/tmp/nobrand-ssh-runtime-copy >/dev/null 2>&1; then
  fail 'SSH Tunnel SCP must be denied'
fi
if timeout 3 "${ssh_base[@]}" -i "$fixture/keys/alice" -w any:any -N \
     nbt-alice@127.0.0.1 >/dev/null 2>&1; then fail 'SSH Tunnel TUN/TAP must be denied'; fi
printf '[PASS] real OpenSSH shell/exec/TTY/SFTP/SCP/TUN denial matrix\n'

if timeout 2 "${ssh_base[@]}" -i "$fixture/keys/alice" -N nbt-alice@127.0.0.1 \
     >/dev/null 2>&1; then
  fail 'SSH -N unexpectedly exited instead of remaining connected'
else
  rc=$?
  [ "$rc" -eq 124 ] || fail 'SSH Alice key authentication failed'
fi
if timeout 2 "${ssh_base[@]}" -i "$fixture/keys/alice" -N nbt-bob@127.0.0.1 \
     >/dev/null 2>&1; then
  fail 'SSH Alice key authenticated Bob'
else
  rc=$?
  [ "$rc" -ne 124 ] || fail 'SSH Alice key authenticated Bob'
fi
if timeout 2 "${ssh_base[@]}" -i "$fixture/keys/bob" -N nbt-bob@127.0.0.1 \
     >/dev/null 2>&1; then
  fail 'SSH -N unexpectedly exited instead of remaining connected'
else
  rc=$?
  [ "$rc" -eq 124 ] || fail 'SSH Bob key authentication failed'
fi
printf '[PASS] real OpenSSH Alice/Bob key isolation\n'

confirm_watchdog_from_admin() {
  local token="$1" output="$2" remote_confirm
  remote_confirm="env MITA_SOURCE_ONLY=0 NOBRAND_STATE_DIR='$NOBRAND_STATE_DIR' NOBRAND_CONFIG_DIR='$NOBRAND_CONFIG_DIR' NOBRAND_LIB_DIR='$NOBRAND_LIB_DIR' NOBRAND_SSH_CONFIG_MAIN='$NOBRAND_SSH_CONFIG_MAIN' NOBRAND_SSH_CONFIG_DROPIN='$NOBRAND_SSH_CONFIG_DROPIN' NOBRAND_SSHD_BIN='$NOBRAND_SSHD_BIN' LD_LIBRARY_PATH='$LD_LIBRARY_PATH' PATH='$PATH' bash '$TEST_ROOT/install-nobrand.sh' ssh confirm-admin --token '$token'"
  "${ssh_base[@]}" -i "$fixture/keys/admin" root@127.0.0.1 "$remote_confirm" >"$output"
}

backup_archive="$fixture/ssh-backup.tar.gz"
nobrand_backup_create "$backup_archive" >/dev/null
assert_file_mode 600 "$backup_archive"
backup_private_hash="$(sha256sum "$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519")"
backup_auth_hash="$(sha256sum "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/nbt-alice")"
cp "$fixture/keys/alice" "$fixture/keys/alice-old"
bob_auth_hash="$(sha256sum "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/nbt-bob")"
ssh_tunnel_rotate_user_key alice
cp "$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519" "$fixture/keys/alice-rotated"
assert_eq "$bob_auth_hash" "$(sha256sum "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/nbt-bob")" \
  'SSH Alice rotation preserves Bob authorized key'
if timeout 2 "${ssh_base[@]}" -i "$fixture/keys/alice-old" -N nbt-alice@127.0.0.1 \
     >/dev/null 2>&1; then
  fail 'rotated old SSH key unexpectedly exited successfully'
else
  rc=$?
  [ "$rc" -ne 124 ] || fail 'rotated old SSH key still authenticates'
fi
if timeout 2 "${ssh_base[@]}" -i "$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519" \
     -N nbt-alice@127.0.0.1 >/dev/null 2>&1; then
  fail 'rotated new SSH key unexpectedly exited successfully'
else
  rc=$?
  [ "$rc" -eq 124 ] || fail 'rotated new SSH key authentication failed'
fi
printf '[PASS] real OpenSSH Ed25519 key rotation and revocation\n'

ssh_tunnel_set_endpoint_state perturbed.example.test 8443
NOBRAND_SSH_WATCHDOG_TIMEOUT=30 nobrand_backup_restore "$backup_archive" \
  >"$fixture/restore.out"
restore_token="$(ssh_tunnel_state_field pending_watchdog_token)"
[ -n "$restore_token" ] && [ "$restore_token" != disabled ] \
  || fail 'SSH restore must arm the real administrator watchdog'
confirm_watchdog_from_admin "$restore_token" "$fixture/restore-confirm.out" \
  || fail 'brand-new administrator confirmation after SSH backup restore'
assert_eq "$backup_private_hash" \
  "$(sha256sum "$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519")" \
  'SSH restore recovers exact private key'
assert_eq "$backup_auth_hash" "$(sha256sum "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/nbt-alice")" \
  'SSH restore recovers exact authorized key'
assert_eq custom "$(ssh_tunnel_state_field advertise_mode)" 'SSH restore endpoint mode'
assert_eq 127.0.0.1 "$(ssh_tunnel_state_field advertise_host)" 'SSH restore endpoint host'
assert_eq "$sshd_port" "$(ssh_tunnel_state_field advertise_port)" 'SSH restore endpoint port'
if timeout 2 "${ssh_base[@]}" -i "$fixture/keys/alice-rotated" -N nbt-alice@127.0.0.1 \
     >/dev/null 2>&1; then
  fail 'perturbed SSH key unexpectedly exited successfully after restore'
else
  rc=$?
  [ "$rc" -ne 124 ] || fail 'perturbed SSH key still authenticates after restore'
fi
if timeout 2 "${ssh_base[@]}" -i "$fixture/keys/alice-old" -N nbt-alice@127.0.0.1 \
     >/dev/null 2>&1; then
  fail 'restored SSH key unexpectedly exited successfully'
else
  rc=$?
  [ "$rc" -eq 124 ] || fail 'restored SSH key authentication failed'
fi
printf '[PASS] real SSH backup, key/endpoint perturbation, restore, and admin confirmation\n'

# Arm the real rollback watchdog, then confirm it by invoking NoBrand from an
# actual brand-new administrator SSH session rather than reusing local state.
NOBRAND_SSH_WATCHDOG_DISABLED=0 NOBRAND_SSH_WATCHDOG_TIMEOUT=30 \
  ssh_tunnel_apply_policy nbt-alice update >"$fixture/watchdog.out"
token="$(ssh_tunnel_state_field pending_watchdog_token)"
[ -n "$token" ] && [ "$token" != disabled ] || fail 'real SSH watchdog token'
confirm_watchdog_from_admin "$token" "$fixture/confirm.out" \
  || fail 'brand-new administrator SSH watchdog confirmation'
assert_eq '' "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" \
  'confirmed SSH watchdog clears token'
"${ssh_base[@]}" -i "$fixture/keys/admin" root@127.0.0.1 true \
  || fail 'administrator SSH after confirmed policy reload'
printf '[PASS] real SSH watchdog + brand-new administrator session confirmation\n'

NOBRAND_SSH_WATCHDOG_TIMEOUT=30 ssh_tunnel_uninstall uninstall >"$fixture/uninstall.out"
uninstall_token="$(ssh_tunnel_state_field pending_watchdog_token)"
[ -n "$uninstall_token" ] && [ "$uninstall_token" != disabled ] \
  || fail 'SSH uninstall must arm the real administrator watchdog'
confirm_watchdog_from_admin "$uninstall_token" "$fixture/uninstall-confirm.out" \
  || fail 'brand-new administrator confirmation during SSH uninstall'
"${ssh_base[@]}" -i "$fixture/keys/admin" root@127.0.0.1 true \
  || fail 'administrator SSH after validated policy removal'
grep -qF "$NOBRAND_SSH_BLOCK_BEGIN" "$NOBRAND_SSH_CONFIG_MAIN" \
  && fail 'managed SSH marker block remained after removal'
[ ! -e "$NOBRAND_SSH_STATE_FILE" ] || fail 'SSH uninstall left module state'
getent passwd nbt-alice >/dev/null 2>&1 && fail 'SSH uninstall left Alice Linux user'
getent passwd nbt-bob >/dev/null 2>&1 && fail 'SSH uninstall left Bob Linux user'
getent group "$NOBRAND_SSH_GROUP" >/dev/null 2>&1 && fail 'SSH uninstall left managed group'
kill -0 "$sshd_pid" || fail 'SSH uninstall stopped the external system sshd'
printf '[PASS] real SSH uninstall removes managed users/group/policy and preserves sshd/admin access\n'

pass 'real OpenSSH policy, permission, forwarding, watchdog, and removal integration'
