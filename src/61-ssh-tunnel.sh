# ---------- SSH Tunnel: existing-OpenSSH policy and dedicated identities ----------

ssh_tunnel_state_exists() {
  [ -s "$NOBRAND_SSH_STATE_FILE" ] && jq empty "$NOBRAND_SSH_STATE_FILE" >/dev/null 2>&1
}

ssh_tunnel_state_absent() {
  [ ! -e "$NOBRAND_SSH_STATE_FILE" ] && [ ! -L "$NOBRAND_SSH_STATE_FILE" ]
}

ssh_tunnel_state_field() {
  local field="$1"
  ssh_tunnel_state_exists || return 1
  jq -r --arg field "$field" \
    'if has($field) and .[$field] != null then .[$field] else empty end' \
    "$NOBRAND_SSH_STATE_FILE"
}

ssh_tunnel_valid_label() {
  local value="${1:-}"
  [ -n "$value" ] || return 1
  [ "$(printf '%s' "$value" | wc -c | tr -d '[:space:]')" -le 64 ] || return 1
  ! has_control_chars "$value" && [[ "$value" != *'|'* ]]
}

ssh_tunnel_generate_account_id() {
  local value
  if command -v openssl >/dev/null 2>&1; then
    value="$(openssl rand -hex 8 2>/dev/null || true)"
  fi
  [ -n "${value:-}" ] || value="$(printf '%08x%08x' "$RANDOM" "$RANDOM")"
  printf 'a%s' "$value"
}

ssh_tunnel_linux_username() {
  local label="$1" account_id="$2" slug
  slug="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-14)"
  [ -n "$slug" ] || slug=user
  printf 'nbt-%s-%s' "$slug" "${account_id#a}" | cut -c1-31
}

ssh_tunnel_nologin_shell() {
  local candidate
  for candidate in /usr/sbin/nologin /sbin/nologin /bin/false; do
    [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

ssh_tunnel_generate_policy() {
  local output="$1" nologin_shell="${2:-}" auth_pattern
  [ -n "$nologin_shell" ] || nologin_shell="$(ssh_tunnel_nologin_shell)" || return 1
  auth_pattern="${NOBRAND_SSH_AUTHORIZED_KEYS_DIR}/%u"
  cat >"$output" <<EOF
Match Group ${NOBRAND_SSH_GROUP}
    AuthenticationMethods publickey
    PubkeyAuthentication yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AuthorizedKeysFile ${auth_pattern}
    AllowTcpForwarding yes
    AllowStreamLocalForwarding no
    GatewayPorts no
    PermitTTY no
    X11Forwarding no
    AllowAgentForwarding no
    PermitTunnel no
    PermitUserRC no
    MaxSessions 0
    ForceCommand ${nologin_shell}
Match all
EOF
  chmod 0600 "$output" 2>/dev/null || true
}

ssh_tunnel_sshd_binary() {
  local candidate
  for candidate in "${NOBRAND_SSHD_BIN:-}" /usr/sbin/sshd /sbin/sshd; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  command -v sshd 2>/dev/null || return 1
}

ssh_tunnel_sshd_test() {
  local config="${1:-$NOBRAND_SSH_CONFIG_MAIN}" sshd
  sshd="$(ssh_tunnel_sshd_binary)" || return 1
  "$sshd" -t -f "$config"
}

ssh_tunnel_sshd_effective() {
  local config="$1" user="$2" host="${3:-localhost}" addr="${4:-127.0.0.1}" sshd
  sshd="$(ssh_tunnel_sshd_binary)" || return 1
  "$sshd" -T -f "$config" -C "user=${user},host=${host},addr=${addr}"
}

ssh_tunnel_effective_policy_valid() {
  local config="$1" user="$2" effective expected key value
  effective="$(ssh_tunnel_sshd_effective "$config" "$user")" || return 1
  while IFS='|' read -r key expected; do
    value="$(printf '%s\n' "$effective" | awk -v key="$key" '$1==key {$1=""; sub(/^ /,""); print; exit}')"
    [ "$value" = "$expected" ] || {
      warn "SSH Tunnel 生效策略不匹配: ${key}=${value:-缺失}，预期 ${expected}"
      return 1
    }
  done <<EOF
authenticationmethods|publickey
pubkeyauthentication|yes
passwordauthentication|no
kbdinteractiveauthentication|no
allowtcpforwarding|yes
allowstreamlocalforwarding|no
gatewayports|no
permittty|no
x11forwarding|no
allowagentforwarding|no
permittunnel|no
permituserrc|no
maxsessions|0
forcecommand|$(ssh_tunnel_nologin_shell)
EOF
}

ssh_tunnel_detect_real_port() {
  local sshd output
  sshd="$(ssh_tunnel_sshd_binary)" || return 1
  output="$("$sshd" -T -f "$NOBRAND_SSH_CONFIG_MAIN" 2>/dev/null)" || return 1
  printf '%s\n' "$output" | awk '$1=="port" && $2 ~ /^[0-9]+$/ {print $2; exit}'
}

ssh_tunnel_default_display_port() {
  local ip base real_port profile
  if [ -n "${INGRESS_PROFILE_ID:-}" ] \
     && [ "$INGRESS_PROFILE_ID" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ]; then
    profile="$(nb_ingress_profile_json "$INGRESS_PROFILE_ID" 2>/dev/null || true)"
    ip="$(jq -r '.local_address // empty' <<<"$profile" 2>/dev/null || true)"
  else
    ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  fi
  if [ -n "$ip" ]; then
    base="$(nb_port_base_for_ip "$ip" 2>/dev/null || true)"
    if [ -n "$base" ]; then
      printf '%s' "$base"
      return 0
    fi
  fi
  real_port="$(ssh_tunnel_detect_real_port 2>/dev/null || true)"
  valid_advertise_port "$real_port" || return 1
  printf '%s' "$(normalize_uint "$real_port")"
}

ssh_tunnel_generate_state() {
  local output="$1" advertise_mode="$2" advertise_host="$3" advertise_port="$4"
  local real_port="$5" strategy="$6" managed_path="$7" users="$8" created_at="${9:-}"
  local ingress_profile_id="${10:-}"
  local updated_at
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg mode "$advertise_mode" --arg host "$advertise_host" \
    --arg advertise_port "$advertise_port" --arg real_port "$real_port" \
    --arg group "$NOBRAND_SSH_GROUP" --arg strategy "$strategy" \
    --arg managed_path "$managed_path" --argjson users "$users" \
    --arg created "$created_at" --arg updated "$updated_at" --arg ingress_profile_id "$ingress_profile_id" '
    {
      schema_version:3,
      ownership:"nobrand-v3",
      protocol:"ssh-tunnel",
      group:$group,
      external_listener:true,
      managed_listener:false,
      managed_firewall:false,
      real_port:($real_port|tonumber),
      advertise_mode:$mode,
      advertise_host:$host,
      advertise_port:($advertise_port|tonumber),
      config_strategy:$strategy,
      managed_config_path:$managed_path,
      policy_applied:false,
      pending_operation:"",
      pending_watchdog_token:"",
      pending_origin_connection:"",
      users:$users,
      created_at:$created,
      updated_at:$updated
    }
    + if $ingress_profile_id=="" then {} else {ingress_profile_id:$ingress_profile_id} end
  ' >"$output"
}

ssh_tunnel_user_json() {
  local account_id="$1" label="$2" linux_user="$3" uid="$4" fingerprint="$5"
  local created_at="${6:-}"
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg account_id "$account_id" --arg display_name "$label" --arg linux_user "$linux_user" \
    --arg uid "$uid" --arg group "$NOBRAND_SSH_GROUP" --arg fingerprint "$fingerprint" \
    --arg created "$created_at" '
    {
      account_id:$account_id,
      display_name:$display_name,
      linux_user:$linux_user,
      uid:($uid|tonumber),
      group:$group,
      key_fingerprint:$fingerprint,
      created_at:$created
    }
  '
}

ssh_tunnel_resolve_user_json() {
  local selector="${1:-}"
  ssh_tunnel_state_exists || return 1
  [ -n "$selector" ] || {
    [ "$(jq '.users | length' "$NOBRAND_SSH_STATE_FILE")" -eq 1 ] || return 1
    jq -c '.users[0]' "$NOBRAND_SSH_STATE_FILE"
    return 0
  }
  jq -ce --arg selector "$selector" '
    [.users[] | select(.account_id==$selector or .display_name==$selector or .linux_user==$selector)]
    | if length==1 then .[0] else empty end
  ' "$NOBRAND_SSH_STATE_FILE"
}

ssh_tunnel_account_marker_file() {
  printf '%s/%s.json' "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" "$1"
}

ssh_tunnel_authorized_key_file() {
  printf '%s/%s' "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$1"
}

ssh_tunnel_key_dir() {
  printf '%s/%s' "$NOBRAND_SSH_KEYS_DIR" "$1"
}

ssh_tunnel_public_key_material() {
  local public_key="$1"
  awk '
    NF {
      count++
      if (count != 1 || NF < 2) exit 1
      key_type=$1
      key_blob=$2
    }
    END {
      if (count != 1 || key_type=="" || key_blob=="") exit 1
      print key_type " " key_blob
    }
  ' "$public_key"
}

ssh_tunnel_single_key_fingerprint() {
  local key_file="$1" output fingerprint
  awk 'NF { count++ } END { exit count==1 ? 0 : 1 }' "$key_file" || return 1
  output="$(ssh-keygen -lf "$key_file" -E sha256 2>/dev/null)" || return 1
  fingerprint="$(awk '
    NF {
      count++
      if (count != 1 || length($2) != 50 || index($2,"SHA256:") != 1 ||
          substr($2,8) !~ /^[A-Za-z0-9+\/]+$/) exit 1
      value=$2
    }
    END {
      if (count != 1 || value=="") exit 1
      print value
    }
  ' <<<"$output")" || return 1
  printf '%s\n' "$fingerprint"
}

ssh_tunnel_key_fingerprint() {
  local public_key="$1"
  ssh_tunnel_public_key_material "$public_key" >/dev/null || return 1
  ssh_tunnel_single_key_fingerprint "$public_key"
}

ssh_tunnel_authorized_key_line() {
  local public_key="$1" nologin_shell="$2" key_material
  ssh_tunnel_key_fingerprint "$public_key" >/dev/null || return 1
  key_material="$(ssh_tunnel_public_key_material "$public_key")" || return 1
  printf 'command="%s",no-agent-forwarding,no-X11-forwarding,no-pty %s\n' \
    "$nologin_shell" "$key_material"
}

ssh_tunnel_group_creation_matches() {
  local expected_gid="$1" group_line actual_name actual_gid
  [[ "$expected_gid" =~ ^[0-9]+$ ]] || return 1
  group_line="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null || true)"
  [ -n "$group_line" ] || return 1
  IFS=: read -r actual_name _ actual_gid _ <<<"$group_line"
  [ "$actual_name" = "$NOBRAND_SSH_GROUP" ] && [ "$actual_gid" = "$expected_gid" ]
}

ssh_tunnel_create_group() {
  local result_var="${1:-}" gid marker_tmp="" created_group=0 create_rc=0
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 0
  if _has_group "$NOBRAND_SSH_GROUP"; then
    gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
    jq -e --arg group "$NOBRAND_SSH_GROUP" --arg gid "$gid" '
      .ownership=="nobrand-v3" and .group==$group and .gid==($gid|tonumber)
    ' "$NOBRAND_SSH_GROUP_MARKER" >/dev/null 2>&1
    return $?
  fi
  if command -v groupadd >/dev/null 2>&1; then
    groupadd --system "$NOBRAND_SSH_GROUP" || create_rc=$?
  elif command -v addgroup >/dev/null 2>&1; then
    addgroup -S "$NOBRAND_SSH_GROUP" || create_rc=$?
  else
    return 1
  fi
  if [ "$create_rc" -ne 0 ]; then
    gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
    if [ -n "$result_var" ] && ssh_tunnel_group_creation_matches "$gid"; then
      printf -v "$result_var" '%s' 1
    fi
    return "$create_rc"
  fi
  created_group=1
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 1
  gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
  if ! [[ "$gid" =~ ^[0-9]+$ ]] \
     || ! mkdir -p "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" \
     || ! chmod 0700 "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" \
     || ! marker_tmp="$(mktemp_file .ssh-group-marker)" \
     || ! jq -n --arg group "$NOBRAND_SSH_GROUP" --arg gid "$gid" '
    {schema_version:3,ownership:"nobrand-v3",group:$group,gid:($gid|tonumber)}
  ' >"$marker_tmp" \
     || ! nb_atomic_install_file "$marker_tmp" "$NOBRAND_SSH_GROUP_MARKER" 0600; then
    rm -f "$marker_tmp" "$NOBRAND_SSH_GROUP_MARKER"
    if [ "$created_group" -eq 1 ] \
       && ssh_tunnel_delete_group >/dev/null 2>&1; then
      [ -z "$result_var" ] || printf -v "$result_var" '%s' 0
    fi
    return 1
  fi
  rm -f "$marker_tmp"
}

ssh_tunnel_create_group_with_gid() {
  local expected_gid="$1" result_var="${2:-}" actual_gid create_rc=0
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 0
  [[ "$expected_gid" =~ ^[0-9]+$ ]] || return 1
  ! _has_group "$NOBRAND_SSH_GROUP" || return 1
  getent group "$expected_gid" >/dev/null 2>&1 && return 1
  if command -v groupadd >/dev/null 2>&1; then
    groupadd --system --gid "$expected_gid" "$NOBRAND_SSH_GROUP" || create_rc=$?
  elif command -v addgroup >/dev/null 2>&1; then
    addgroup -S -g "$expected_gid" "$NOBRAND_SSH_GROUP" || create_rc=$?
  else
    return 1
  fi
  if [ "$create_rc" -ne 0 ]; then
    if ssh_tunnel_group_creation_matches "$expected_gid"; then
      [ -z "$result_var" ] || printf -v "$result_var" '%s' 1
    fi
    return "$create_rc"
  fi
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 1
  actual_gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
  [ "$actual_gid" = "$expected_gid" ]
}

ssh_tunnel_delete_group() {
  _has_group "$NOBRAND_SSH_GROUP" || return 0
  if command -v groupdel >/dev/null 2>&1; then
    groupdel "$NOBRAND_SSH_GROUP"
  elif command -v delgroup >/dev/null 2>&1; then
    delgroup "$NOBRAND_SSH_GROUP"
  else
    return 1
  fi
}

ssh_tunnel_group_identity_valid() {
  local gid
  _has_group "$NOBRAND_SSH_GROUP" || return 1
  [ -f "$NOBRAND_SSH_GROUP_MARKER" ] && [ ! -L "$NOBRAND_SSH_GROUP_MARKER" ] \
    && secure_stat_path "$NOBRAND_SSH_GROUP_MARKER" file \
    && [ "$(stat -c '%a' "$NOBRAND_SSH_GROUP_MARKER")" = 600 ] || return 1
  gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
  jq -e --arg group "$NOBRAND_SSH_GROUP" --arg gid "$gid" '
    .ownership=="nobrand-v3" and .group==$group and .gid==($gid|tonumber)
  ' "$NOBRAND_SSH_GROUP_MARKER" >/dev/null 2>&1
}

ssh_tunnel_create_linux_user() {
  local linux_user="$1" account_id="$2" nologin_shell="$3"
  ! _has_user "$linux_user" || return 1
  if command -v useradd >/dev/null 2>&1; then
    useradd --system --gid "$NOBRAND_SSH_GROUP" --no-create-home --home-dir /nonexistent \
      --shell "$nologin_shell" --comment "NoBrand SSH Tunnel ${account_id}" "$linux_user" || return 1
  elif command -v adduser >/dev/null 2>&1; then
    adduser -S -D -H -G "$NOBRAND_SSH_GROUP" -h /nonexistent -s "$nologin_shell" \
      -g "NoBrand SSH Tunnel ${account_id}" "$linux_user" || return 1
  else
    return 1
  fi
  command -v passwd >/dev/null 2>&1 && passwd -l "$linux_user" >/dev/null 2>&1 || true
}

ssh_tunnel_linux_user_creation_matches() {
  local linux_user="$1" account_id="$2" nologin_shell="$3" expected_uid="$4"
  local passwd_line group_line actual_name actual_uid actual_gid gecos home shell
  local group_name group_gid
  passwd_line="$(getent passwd "$linux_user" 2>/dev/null || true)"
  group_line="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null || true)"
  [ -n "$passwd_line" ] && [ -n "$group_line" ] || return 1
  IFS=: read -r actual_name _ actual_uid actual_gid gecos home shell <<<"$passwd_line"
  IFS=: read -r group_name _ group_gid _ <<<"$group_line"
  [ "$actual_name" = "$linux_user" ] \
    && [ "$actual_uid" = "$expected_uid" ] \
    && [ "$group_name" = "$NOBRAND_SSH_GROUP" ] \
    && [ "$actual_gid" = "$group_gid" ] \
    && [ "$gecos" = "NoBrand SSH Tunnel ${account_id}" ] \
    && [ "$home" = /nonexistent ] \
    && [ "$shell" = "$nologin_shell" ]
}

ssh_tunnel_create_linux_user_with_uid() {
  local linux_user="$1" account_id="$2" nologin_shell="$3" expected_uid="$4"
  local result_var="${5:-}" create_rc=0
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 0
  ! _has_user "$linux_user" || return 1
  getent passwd "$expected_uid" >/dev/null 2>&1 && return 1
  if command -v useradd >/dev/null 2>&1; then
    useradd --system --uid "$expected_uid" --gid "$NOBRAND_SSH_GROUP" --no-create-home \
      --home-dir /nonexistent --shell "$nologin_shell" \
      --comment "NoBrand SSH Tunnel ${account_id}" "$linux_user" || create_rc=$?
  elif command -v adduser >/dev/null 2>&1; then
    adduser -S -D -H -u "$expected_uid" -G "$NOBRAND_SSH_GROUP" -h /nonexistent \
      -s "$nologin_shell" -g "NoBrand SSH Tunnel ${account_id}" "$linux_user" || create_rc=$?
  else
    return 1
  fi
  if [ "$create_rc" -ne 0 ]; then
    if ssh_tunnel_linux_user_creation_matches \
      "$linux_user" "$account_id" "$nologin_shell" "$expected_uid"; then
      [ -z "$result_var" ] || printf -v "$result_var" '%s' 1
    fi
    return "$create_rc"
  fi
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 1
  command -v passwd >/dev/null 2>&1 && passwd -l "$linux_user" >/dev/null 2>&1 || true
  [ "$(id -u "$linux_user")" = "$expected_uid" ]
}

ssh_tunnel_delete_linux_user() {
  local linux_user="$1"
  if command -v userdel >/dev/null 2>&1; then
    userdel "$linux_user"
  elif command -v deluser >/dev/null 2>&1; then
    deluser "$linux_user"
  else
    return 1
  fi
}

ssh_tunnel_linux_user_identity_valid() {
  local user_json="$1" linux_user expected_uid expected_group account_id
  local passwd_line actual_uid actual_gid group_gid gecos shell
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  expected_uid="$(jq -r .uid <<<"$user_json")"
  expected_group="$(jq -r .group <<<"$user_json")"
  account_id="$(jq -r .account_id <<<"$user_json")"
  passwd_line="$(getent passwd "$linux_user" 2>/dev/null || true)"
  [ -n "$passwd_line" ] || return 1
  IFS=: read -r _ _ actual_uid actual_gid gecos _ shell <<<"$passwd_line"
  group_gid="$(getent group "$expected_group" 2>/dev/null | awk -F: '{print $3}')"
  [ "$actual_uid" = "$expected_uid" ] && [ "$actual_gid" = "$group_gid" ] || return 1
  [ "$gecos" = "NoBrand SSH Tunnel ${account_id}" ] || return 1
  case "$shell" in /usr/sbin/nologin|/sbin/nologin|/bin/false) ;; *) return 1 ;; esac
}

ssh_tunnel_user_identity_valid() {
  local user_json="$1" linux_user expected_uid account_id expected_fp marker auth_file actual_fp
  ssh_tunnel_linux_user_identity_valid "$user_json" || return 1
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  expected_uid="$(jq -r .uid <<<"$user_json")"
  account_id="$(jq -r .account_id <<<"$user_json")"
  expected_fp="$(jq -r .key_fingerprint <<<"$user_json")"
  marker="$(ssh_tunnel_account_marker_file "$linux_user")"
  [ -f "$marker" ] && [ ! -L "$marker" ] && secure_stat_path "$marker" file \
    && [ "$(stat -c '%a' "$marker")" = 600 ] || return 1
  jq -e --arg account_id "$account_id" --arg linux_user "$linux_user" --arg uid "$expected_uid" \
    '.ownership=="nobrand-v3" and .account_id==$account_id and .linux_user==$linux_user and .uid==($uid|tonumber)' \
    "$marker" >/dev/null 2>&1 || return 1
  auth_file="$(ssh_tunnel_authorized_key_file "$linux_user")"
  [ -f "$auth_file" ] && [ ! -L "$auth_file" ] && [ -s "$auth_file" ] \
    && secure_stat_path "$auth_file" file \
    && [ "$(stat -c '%a' "$auth_file")" = 644 ] || return 1
  actual_fp="$(ssh_tunnel_single_key_fingerprint "$auth_file")" || return 1
  [ "$actual_fp" = "$expected_fp" ]
}

ssh_tunnel_user_key_material_valid() {
  local user_json="$1" account_id expected_fp key_dir private_key public_key
  local actual_fp private_check="" private_output private_material public_material
  account_id="$(jq -r .account_id <<<"$user_json")"
  expected_fp="$(jq -r .key_fingerprint <<<"$user_json")"
  key_dir="$(ssh_tunnel_key_dir "$account_id")"
  private_key="${key_dir}/id_ed25519"
  public_key="${private_key}.pub"
  [ -d "$key_dir" ] && [ ! -L "$key_dir" ] \
    && secure_stat_path "$key_dir" dir \
    && [ "$(stat -c '%a' "$key_dir")" = 700 ] \
    && [ -f "$private_key" ] && [ ! -L "$private_key" ] \
    && secure_stat_path "$private_key" file \
    && [ "$(stat -c '%a' "$private_key")" = 600 ] \
    && [ -f "$public_key" ] && [ ! -L "$public_key" ] \
    && secure_stat_path "$public_key" file || return 1
  actual_fp="$(ssh_tunnel_key_fingerprint "$public_key")" || return 1
  [ "$actual_fp" = "$expected_fp" ] || return 1
  private_check="$(mktemp_file .ssh-private-check)" || return 1
  if ! install -m 0600 "$private_key" "$private_check" \
     || ! private_output="$(ssh-keygen -y -f "$private_check" 2>/dev/null)" \
     || ! private_material="$(ssh_tunnel_public_key_material /dev/stdin <<<"$private_output")"; then
    rm -f "$private_check"
    return 1
  fi
  rm -f "$private_check"
  public_material="$(ssh_tunnel_public_key_material "$public_key")" || return 1
  [ -n "$public_material" ] && [ "$private_material" = "$public_material" ]
}

ssh_tunnel_user_file_destinations_valid() {
  local user_json="$1" linux_user account_id expected_uid expected_fp marker auth_file actual_fp path
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  account_id="$(jq -r .account_id <<<"$user_json")"
  expected_uid="$(jq -r .uid <<<"$user_json")"
  expected_fp="$(jq -r .key_fingerprint <<<"$user_json")"
  marker="$(ssh_tunnel_account_marker_file "$linux_user")"
  auth_file="$(ssh_tunnel_authorized_key_file "$linux_user")"
  for path in "$marker" "$auth_file"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      [ -f "$path" ] && [ ! -L "$path" ] && secure_stat_path "$path" file || return 1
    fi
  done
  if [ -e "$marker" ]; then
    jq -e --arg account_id "$account_id" --arg linux_user "$linux_user" \
      --arg uid "$expected_uid" '
      .ownership=="nobrand-v3" and .account_id==$account_id
      and .linux_user==$linux_user and .uid==($uid|tonumber)
    ' "$marker" >/dev/null 2>&1 || return 1
  fi
  if [ -e "$auth_file" ]; then
    [ -s "$auth_file" ] || return 1
    actual_fp="$(ssh_tunnel_single_key_fingerprint "$auth_file")" || return 1
    [ "$actual_fp" = "$expected_fp" ] || return 1
  fi
}

ssh_tunnel_reconcile_user_files() {
  local user_json="$1" nologin_shell="$2" linux_user account_id expected_uid expected_fp
  local key_dir private_key public_key actual_fp marker auth_file marker_tmp="" auth_tmp=""
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  account_id="$(jq -r .account_id <<<"$user_json")"
  expected_uid="$(jq -r .uid <<<"$user_json")"
  expected_fp="$(jq -r .key_fingerprint <<<"$user_json")"
  key_dir="$(ssh_tunnel_key_dir "$account_id")"
  private_key="${key_dir}/id_ed25519"
  public_key="${private_key}.pub"
  ssh_tunnel_user_key_material_valid "$user_json" || return 1
  ssh_tunnel_user_file_destinations_valid "$user_json" || return 1
  marker="$(ssh_tunnel_account_marker_file "$linux_user")"
  if [ -e "$marker" ] || [ -L "$marker" ]; then
    [ -f "$marker" ] && [ ! -L "$marker" ] \
      && jq -e --arg account_id "$account_id" --arg linux_user "$linux_user" \
        --arg uid "$expected_uid" '
        .ownership=="nobrand-v3" and .account_id==$account_id
        and .linux_user==$linux_user and .uid==($uid|tonumber)
      ' "$marker" >/dev/null 2>&1 || return 1
  else
    marker_tmp="$(mktemp_file .account-marker)" || return 1
    jq -n --arg account_id "$account_id" --arg linux_user "$linux_user" --arg uid "$expected_uid" '
      {schema_version:3,ownership:"nobrand-v3",account_id:$account_id,
       linux_user:$linux_user,uid:($uid|tonumber)}
    ' >"$marker_tmp" \
      && nb_atomic_install_file "$marker_tmp" "$marker" 0600 || {
        rm -f "$marker_tmp"
        return 1
      }
    rm -f "$marker_tmp"
  fi
  chmod 0600 "$marker" || return 1
  auth_file="$(ssh_tunnel_authorized_key_file "$linux_user")"
  if [ -e "$auth_file" ] || [ -L "$auth_file" ]; then
    [ -f "$auth_file" ] && [ ! -L "$auth_file" ] || return 1
    actual_fp="$(ssh_tunnel_single_key_fingerprint "$auth_file")" || return 1
    [ "$actual_fp" = "$expected_fp" ] || return 1
  fi
  auth_tmp="$(mktemp_file .authorized-key)" || return 1
  if ! ssh_tunnel_authorized_key_line "$public_key" "$nologin_shell" >"$auth_tmp"; then
    rm -f "$auth_tmp"
    return 1
  fi
  if [ ! -e "$auth_file" ] || ! cmp -s "$auth_tmp" "$auth_file"; then
    nb_atomic_install_file "$auth_tmp" "$auth_file" 0644 || {
      rm -f "$auth_tmp"
      return 1
    }
  fi
  rm -f "$auth_tmp"
  chmod 0700 "$key_dir" \
    && chmod 0600 "$private_key" \
    && chmod 0644 "$public_key" "$auth_file" || return 1
  ssh_tunnel_user_identity_valid "$user_json"
}

ssh_tunnel_restore_paths_preflight() {
  local path config_parent
  [ "$NOBRAND_SSH_STATE_DIR" = "${NOBRAND_STATE_DIR}/ssh-tunnel" ] || return 1
  [ "$(dirname "$NOBRAND_SSH_STATE_FILE")" = "$NOBRAND_SSH_STATE_DIR" ] || return 1
  [ "$NOBRAND_SSH_KEYS_DIR" = "${NOBRAND_SSH_STATE_DIR}/keys" ] || return 1
  [ "$NOBRAND_SSH_WATCHDOG_DIR" = "${NOBRAND_SSH_STATE_DIR}/watchdog" ] || return 1
  [ "$NOBRAND_SSH_CONFIG_DIR" = "${NOBRAND_CONFIG_DIR}/ssh-tunnel" ] || return 1
  [ "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" = "${NOBRAND_SSH_CONFIG_DIR}/authorized_keys" ] || return 1
  [ "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" = "${NOBRAND_SSH_CONFIG_DIR}/accounts" ] || return 1
  [ "$NOBRAND_SSH_GROUP_MARKER" = "${NOBRAND_SSH_ACCOUNT_MARKER_DIR}/.group.json" ] || return 1
  nb_assert_safe_nobrand_root "$NOBRAND_SSH_STATE_DIR" NOBRAND_SSH_STATE_DIR >/dev/null || return 1
  nb_assert_safe_nobrand_root "$NOBRAND_SSH_CONFIG_DIR" NOBRAND_SSH_CONFIG_DIR >/dev/null || return 1
  [ -d "$NOBRAND_STATE_DIR" ] && [ ! -L "$NOBRAND_STATE_DIR" ] \
    && secure_stat_path "$NOBRAND_STATE_DIR" dir \
    && [ "$(stat -c '%a' "$NOBRAND_STATE_DIR")" = 700 ] || return 1
  [ -d "$NOBRAND_SSH_STATE_DIR" ] && [ ! -L "$NOBRAND_SSH_STATE_DIR" ] \
    && secure_stat_path "$NOBRAND_SSH_STATE_DIR" dir \
    && [ "$(stat -c '%a' "$NOBRAND_SSH_STATE_DIR")" = 700 ] || return 1
  secure_stat_path "$NOBRAND_SSH_STATE_FILE" file \
    && [ "$(stat -c '%a' "$NOBRAND_SSH_STATE_FILE")" = 600 ] || return 1
  [ -d "$NOBRAND_SSH_KEYS_DIR" ] && [ ! -L "$NOBRAND_SSH_KEYS_DIR" ] \
    && secure_stat_path "$NOBRAND_SSH_KEYS_DIR" dir \
    && [ "$(stat -c '%a' "$NOBRAND_SSH_KEYS_DIR")" = 700 ] || return 1
  config_parent="$(dirname "$NOBRAND_CONFIG_DIR")"
  [ -d "$config_parent" ] && [ ! -L "$config_parent" ] \
    && secure_stat_path "$config_parent" dir || return 1
  for path in "$NOBRAND_CONFIG_DIR" "$NOBRAND_SSH_CONFIG_DIR" \
    "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      [ -d "$path" ] && [ ! -L "$path" ] && secure_stat_path "$path" dir || return 1
    fi
  done
  ssh_tunnel_watchdog_directory_preflight || return 1
}

ssh_tunnel_ensure_restore_directories() {
  local path mode
  while IFS='|' read -r path mode; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      [ -d "$path" ] && [ ! -L "$path" ] || return 1
    else
      mkdir "$path" || return 1
    fi
    chmod "$mode" "$path" \
      && chown root:root "$path" 2>/dev/null \
      && secure_stat_path "$path" dir || return 1
  done <<EOF
$NOBRAND_CONFIG_DIR|0711
$NOBRAND_SSH_CONFIG_DIR|0711
$NOBRAND_SSH_AUTHORIZED_KEYS_DIR|0755
$NOBRAND_SSH_ACCOUNT_MARKER_DIR|0700
EOF
}

ssh_tunnel_group_marker_preflight() {
  local expected_gid actual_gid
  if [ ! -e "$NOBRAND_SSH_GROUP_MARKER" ] && [ ! -L "$NOBRAND_SSH_GROUP_MARKER" ]; then
    return 0
  fi
  [ -f "$NOBRAND_SSH_GROUP_MARKER" ] && [ ! -L "$NOBRAND_SSH_GROUP_MARKER" ] \
    && secure_stat_path "$NOBRAND_SSH_GROUP_MARKER" file || return 1
  expected_gid="$(jq -er --arg group "$NOBRAND_SSH_GROUP" '
    select(.schema_version==3 and .ownership=="nobrand-v3" and .group==$group)
    | .gid | select(type=="number" and .>=0 and floor==.)
  ' "$NOBRAND_SSH_GROUP_MARKER" 2>/dev/null)" || return 1
  if _has_group "$NOBRAND_SSH_GROUP"; then
    actual_gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
    [ "$actual_gid" = "$expected_gid" ]
  else
    ! getent group "$expected_gid" >/dev/null 2>&1
  fi
}

ssh_tunnel_reconcile_group_marker() {
  local marker_tmp="" gid
  _has_group "$NOBRAND_SSH_GROUP" || return 1
  if [ -e "$NOBRAND_SSH_GROUP_MARKER" ] || [ -L "$NOBRAND_SSH_GROUP_MARKER" ]; then
    ssh_tunnel_group_marker_preflight || return 1
    chmod 0600 "$NOBRAND_SSH_GROUP_MARKER"
    return $?
  fi
  gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
  [[ "$gid" =~ ^[0-9]+$ ]] || return 1
  marker_tmp="$(mktemp_file .ssh-group-marker)" || return 1
  jq -n --arg group "$NOBRAND_SSH_GROUP" --arg gid "$gid" '
    {schema_version:3,ownership:"nobrand-v3",group:$group,gid:($gid|tonumber)}
  ' >"$marker_tmp" \
    && nb_atomic_install_file "$marker_tmp" "$NOBRAND_SSH_GROUP_MARKER" 0600 || {
      rm -f "$marker_tmp"
      return 1
    }
  rm -f "$marker_tmp"
  ssh_tunnel_group_identity_valid || return 1
  chmod 0600 "$NOBRAND_SSH_GROUP_MARKER"
}

ssh_tunnel_add_user_internal() {
  local label="$1" account_id linux_user nologin_shell key_dir private_key public_key
  local fingerprint uid user_json state_tmp marker_tmp auth_tmp created_user=0
  ssh_tunnel_watchdog_mutation_preflight || return $?
  ssh_tunnel_valid_label "$label" || die 'SSH Tunnel 用户标签必须为 1-64 字节且不能含控制字符或 |'
  ssh_tunnel_resolve_user_json "$label" >/dev/null 2>&1 && die "SSH Tunnel 用户已存在: $label"
  account_id="$(ssh_tunnel_generate_account_id)" || return 1
  linux_user="$(ssh_tunnel_linux_username "$label" "$account_id")"
  nologin_shell="$(ssh_tunnel_nologin_shell)" || die '找不到系统 nologin shell'
  ! _has_user "$linux_user" || die "Linux 用户名冲突: $linux_user"
  key_dir="$(ssh_tunnel_key_dir "$account_id")"
  private_key="${key_dir}/id_ed25519"
  public_key="${private_key}.pub"
  mkdir -p "$key_dir" "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" || return 1
  chmod 0700 "$key_dir" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" || return 1
  chmod 0755 "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" || return 1
  ssh-keygen -q -t ed25519 -N '' -C "nobrand:${account_id}" -f "$private_key" || {
    rm -rf -- "$key_dir"
    return 1
  }
  chmod 0600 "$private_key" && chmod 0644 "$public_key" || {
    rm -rf -- "$key_dir"
    return 1
  }
  fingerprint="$(ssh_tunnel_key_fingerprint "$public_key")" || {
    rm -rf -- "$key_dir"
    return 1
  }
  ssh_tunnel_create_linux_user "$linux_user" "$account_id" "$nologin_shell" || {
    rm -rf -- "$key_dir"
    return 1
  }
  created_user=1
  uid="$(id -u "$linux_user")" || {
    ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
    rm -rf -- "$key_dir"
    return 1
  }
  user_json="$(ssh_tunnel_user_json "$account_id" "$label" "$linux_user" "$uid" "$fingerprint")"
  auth_tmp="$(mktemp_file .authorized-key)" || {
    ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
    rm -rf -- "$key_dir"
    return 1
  }
  marker_tmp="$(mktemp_file .account-marker)" || {
    rm -f "$auth_tmp"
    ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
    rm -rf -- "$key_dir"
    return 1
  }
  state_tmp="$(mktemp_file .ssh-state)" || {
    rm -f "$auth_tmp" "$marker_tmp"
    ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
    rm -rf -- "$key_dir"
    return 1
  }
  ssh_tunnel_authorized_key_line "$public_key" "$nologin_shell" >"$auth_tmp" \
    && jq -n --arg account_id "$account_id" --arg linux_user "$linux_user" --arg uid "$uid" \
      '{schema_version:3,ownership:"nobrand-v3",account_id:$account_id,linux_user:$linux_user,uid:($uid|tonumber)}' \
      >"$marker_tmp" \
    && jq --argjson user "$user_json" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.users += [$user] | .updated_at=$updated' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
    && nb_atomic_install_file "$auth_tmp" "$(ssh_tunnel_authorized_key_file "$linux_user")" 0644 \
    && nb_atomic_install_file "$marker_tmp" "$(ssh_tunnel_account_marker_file "$linux_user")" 0600 \
    && nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 \
    || {
      rm -f "$auth_tmp" "$marker_tmp" "$state_tmp" \
        "$(ssh_tunnel_authorized_key_file "$linux_user")" \
        "$(ssh_tunnel_account_marker_file "$linux_user")"
      [ "$created_user" -ne 1 ] || ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
      find "$key_dir" -mindepth 1 -maxdepth 1 -delete 2>/dev/null || true
      rmdir "$key_dir" 2>/dev/null || true
      return 1
    }
  rm -f "$auth_tmp" "$marker_tmp" "$state_tmp"
  printf '%s' "$account_id"
}

ssh_tunnel_rotate_user_key() {
  local selector="${1:-}" user_json account_id linux_user nologin_shell key_dir new_private
  local new_public new_fp auth_tmp state_tmp snapshot
  ssh_tunnel_watchdog_mutation_preflight || return $?
  user_json="$(ssh_tunnel_resolve_user_json "$selector")" || die '找不到唯一 SSH Tunnel 用户'
  ssh_tunnel_user_identity_valid "$user_json" || die 'SSH Tunnel 用户身份不匹配，拒绝轮换'
  account_id="$(jq -r .account_id <<<"$user_json")"
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  nologin_shell="$(ssh_tunnel_nologin_shell)" || return 1
  key_dir="$(ssh_tunnel_key_dir "$account_id")"
  new_private="$(mktemp "${key_dir}/id_ed25519.new.XXXXXX")" || return 1
  rm -f "$new_private"
  ssh-keygen -q -t ed25519 -N '' -C "nobrand:${account_id}" -f "$new_private" || {
    rm -f "$new_private" "${new_private}.pub"
    return 1
  }
  new_public="${new_private}.pub"
  chmod 0600 "$new_private" && chmod 0644 "$new_public" || {
    rm -f "$new_private" "$new_public"
    return 1
  }
  new_fp="$(ssh_tunnel_key_fingerprint "$new_public")" || {
    rm -f "$new_private" "$new_public"
    return 1
  }
  auth_tmp="$(mktemp_file .authorized-key)" || {
    rm -f "$new_private" "$new_public"
    return 1
  }
  state_tmp="$(mktemp_file .ssh-state)" || {
    rm -f "$new_private" "$new_public" "$auth_tmp"
    return 1
  }
  snapshot="$(mktemp_dir)" || {
    rm -f "$new_private" "$new_public" "$auth_tmp" "$state_tmp"
    return 1
  }
  cp -a "$key_dir/id_ed25519" "$key_dir/id_ed25519.pub" \
    "$(ssh_tunnel_authorized_key_file "$linux_user")" "$NOBRAND_SSH_STATE_FILE" "$snapshot/" || {
      rm -f "$new_private" "$new_public" "$auth_tmp" "$state_tmp"
      rm -rf -- "$snapshot"
      return 1
    }
  ssh_tunnel_authorized_key_line "$new_public" "$nologin_shell" >"$auth_tmp" \
    && jq --arg account_id "$account_id" --arg fingerprint "$new_fp" \
      --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '(.users[] | select(.account_id==$account_id)).key_fingerprint=$fingerprint | .updated_at=$updated' \
      "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
    && nb_atomic_install_file "$new_private" "$key_dir/id_ed25519" 0600 \
    && nb_atomic_install_file "$new_public" "$key_dir/id_ed25519.pub" 0644 \
    && nb_atomic_install_file "$auth_tmp" "$(ssh_tunnel_authorized_key_file "$linux_user")" 0644 \
    && nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 \
    || {
      cp -a "$snapshot/id_ed25519" "$key_dir/id_ed25519" 2>/dev/null || true
      cp -a "$snapshot/id_ed25519.pub" "$key_dir/id_ed25519.pub" 2>/dev/null || true
      cp -a "$snapshot/$linux_user" "$(ssh_tunnel_authorized_key_file "$linux_user")" 2>/dev/null || true
      cp -a "$snapshot/state.json" "$NOBRAND_SSH_STATE_FILE" 2>/dev/null || true
      rm -f "$new_private" "$new_public" "$auth_tmp" "$state_tmp"
      rm -rf -- "$snapshot"
      return 1
    }
  rm -f "$new_private" "$new_public" "$auth_tmp" "$state_tmp"
  rm -rf -- "$snapshot"
}

ssh_tunnel_delete_user_internal() {
  local selector="${1:-}" user_json account_id linux_user uid auth_file state_tmp snapshot nologin_shell
  ssh_tunnel_watchdog_mutation_preflight || return $?
  user_json="$(ssh_tunnel_resolve_user_json "$selector")" || die '找不到唯一 SSH Tunnel 用户'
  ssh_tunnel_user_identity_valid "$user_json" || die 'SSH Tunnel 用户身份不匹配，拒绝删除'
  account_id="$(jq -r .account_id <<<"$user_json")"
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  uid="$(jq -r .uid <<<"$user_json")"
  auth_file="$(ssh_tunnel_authorized_key_file "$linux_user")"
  state_tmp="$(mktemp_file .ssh-state)" || return 1
  snapshot="$(mktemp_dir)" || { rm -f "$state_tmp"; return 1; }
  cp -a "$auth_file" "$NOBRAND_SSH_STATE_FILE" "$snapshot/" || {
    rm -f "$state_tmp"
    rm -rf -- "$snapshot"
    return 1
  }
  jq --arg account_id "$account_id" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.users |= map(select(.account_id!=$account_id)) | .updated_at=$updated' \
    "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" || {
      rm -f "$state_tmp"
      rm -rf -- "$snapshot"
      return 1
    }
  rm -f "$auth_file"
  pkill -KILL -u "$uid" 2>/dev/null || true
  if ! ssh_tunnel_delete_linux_user "$linux_user"; then
    cp -a "$snapshot/$linux_user" "$auth_file" 2>/dev/null || true
    rm -f "$state_tmp"
    rm -rf -- "$snapshot"
    return 1
  fi
  if ! nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600; then
    nologin_shell="$(ssh_tunnel_nologin_shell 2>/dev/null || true)"
    if [ -n "$nologin_shell" ] \
       && ssh_tunnel_create_linux_user_with_uid "$linux_user" "$account_id" "$nologin_shell" "$uid" \
       && cp -a "$snapshot/$linux_user" "$auth_file"; then
      warn 'SSH Tunnel 状态提交失败；Linux 用户与 authorized_keys 已回滚'
    else
      warn 'SSH Tunnel 状态提交失败且 Linux 用户回滚失败；authorized_keys 保持撤销，所有权标记与密钥保留供恢复'
    fi
    rm -f "$state_tmp"
    rm -rf -- "$snapshot"
    return 1
  fi
  rm -f "$(ssh_tunnel_account_marker_file "$linux_user")" "$state_tmp"
  find "$(ssh_tunnel_key_dir "$account_id")" -mindepth 1 -maxdepth 1 -delete 2>/dev/null || true
  rmdir "$(ssh_tunnel_key_dir "$account_id")" 2>/dev/null || true
  rm -rf -- "$snapshot"
}

ssh_tunnel_dropin_supported() {
  [ "$NOBRAND_SSH_CONFIG_DROPIN" = /etc/ssh/sshd_config.d/90-nobrand-ssh-tunnel.conf ] || return 1
  awk '
    /^[[:space:]]*#/ {next}
    tolower($1)=="match" {exit}
    tolower($1)=="include" {
      for (i=2;i<=NF;i++) if ($i=="/etc/ssh/sshd_config.d/*.conf") found=1
    }
    END {exit(found?0:1)}
  ' "$NOBRAND_SSH_CONFIG_MAIN"
}

ssh_tunnel_state_proves_config_target() {
  local strategy="$1" target="$2" allowed_policy_state="${3:-true}" actual_policy_state
  secure_stat_path "$NOBRAND_SSH_STATE_FILE" file || return 1
  ssh_tunnel_state_identity_valid || return 1
  [ "$(ssh_tunnel_state_field config_strategy 2>/dev/null || true)" = "$strategy" ] \
    && [ "$(ssh_tunnel_state_field managed_config_path 2>/dev/null || true)" = "$target" ] \
    && [ -z "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" ] \
    && [ -z "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" ] \
    && [ -z "$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)" ] \
    && [ -z "$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)" ] \
    || return 1
  actual_policy_state="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
  case "$allowed_policy_state" in
    any) [ "$actual_policy_state" = true ] || [ "$actual_policy_state" = false ] ;;
    true|false) [ "$actual_policy_state" = "$allowed_policy_state" ] ;;
    *) return 1 ;;
  esac
}

ssh_tunnel_existing_dropin_owned() {
  local target="$1" expected_policy="$2" allowed_policy_state="${3:-true}"
  [ "$target" = "$NOBRAND_SSH_CONFIG_DROPIN" ] || return 1
  [ -f "$target" ] && [ ! -L "$target" ] || return 1
  secure_stat_path "$target" file || return 1
  ssh_tunnel_state_proves_config_target dropin "$target" "$allowed_policy_state" \
    && cmp -s "$expected_policy" "$target"
}

ssh_tunnel_marker_block_matches_policy() {
  local target="$1" expected_policy="$2" extracted
  extracted="$(mktemp_file .ssh-marker-policy)" || return 1
  if ! awk -v begin="$NOBRAND_SSH_BLOCK_BEGIN" -v end="$NOBRAND_SSH_BLOCK_END" '
    $0==begin {
      if (inside || seen_begin) {bad=1; exit}
      inside=1
      seen_begin=1
      next
    }
    $0==end {
      if (!inside || seen_end) {bad=1; exit}
      inside=0
      seen_end=1
      next
    }
    inside {print}
    END {if (bad || inside || seen_begin!=1 || seen_end!=1) exit 2}
  ' "$target" >"$extracted"; then
    rm -f "$extracted"
    return 1
  fi
  if ! cmp -s "$expected_policy" "$extracted"; then
    rm -f "$extracted"
    return 1
  fi
  rm -f "$extracted"
}

ssh_tunnel_existing_marker_block_owned() {
  local target="$1" expected_policy="$2" allowed_policy_state="${3:-true}"
  [ "$target" = "$NOBRAND_SSH_CONFIG_MAIN" ] || return 1
  [ -f "$target" ] && [ ! -L "$target" ] || return 1
  secure_stat_path "$target" file || return 1
  ssh_tunnel_state_proves_config_target marker-block "$target" "$allowed_policy_state" \
    && ssh_tunnel_marker_block_matches_policy "$target" "$expected_policy"
}

ssh_tunnel_apply_target_preflight() {
  local strategy="$1" target="$2" policy="$3" operation="$4"
  case "$strategy" in
    dropin)
      if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        return 0
      fi
      # A fixed-name drop-in is not an ownership boundary by itself. During a
      # restore, accept only the exact policy already proved by current state;
      # a fresh install must require an absent target.
      [ "$operation" = restore ] \
        && ssh_tunnel_existing_dropin_owned "$target" "$policy" any
      ;;
    marker-block)
      [ "$target" = "$NOBRAND_SSH_CONFIG_MAIN" ] \
        && [ -f "$target" ] && [ ! -L "$target" ] \
        && secure_stat_path "$target" file || return 1
      if ! grep -Fqx "$NOBRAND_SSH_BLOCK_BEGIN" "$target" 2>/dev/null \
         && ! grep -Fqx "$NOBRAND_SSH_BLOCK_END" "$target" 2>/dev/null; then
        return 0
      fi
      [ "$operation" = restore ] \
        && ssh_tunnel_existing_marker_block_owned "$target" "$policy" any
      ;;
    *) return 1 ;;
  esac
}

ssh_tunnel_strip_marker_block() {
  local source="$1" output="$2"
  awk -v begin="$NOBRAND_SSH_BLOCK_BEGIN" -v end="$NOBRAND_SSH_BLOCK_END" '
    $0==begin {inside=1; next}
    $0==end {if (!inside) exit 2; inside=0; next}
    !inside {print}
    END {if (inside) exit 2}
  ' "$source" >"$output"
}

ssh_tunnel_build_main_candidate() {
  local policy="$1" output="$2" stripped
  stripped="$(mktemp_file .sshd-main)" || return 1
  if ! ssh_tunnel_strip_marker_block "$NOBRAND_SSH_CONFIG_MAIN" "$stripped"; then
    rm -f "$stripped"
    return 1
  fi
  if ! {
    cat "$stripped"
    printf '\n%s\n' "$NOBRAND_SSH_BLOCK_BEGIN"
    cat "$policy"
    printf '%s\n' "$NOBRAND_SSH_BLOCK_END"
  } >"$output"; then
    rm -f "$stripped"
    return 1
  fi
  rm -f "$stripped"
}

ssh_tunnel_build_dropin_removal_candidate() {
  local output="$1" candidate_root="$2" source_dir source_file candidate_dir replacement
  source_dir="$(dirname "$NOBRAND_SSH_CONFIG_DROPIN")"
  candidate_dir="${candidate_root}/sshd_config.d"
  replacement="${candidate_dir}/*.conf"
  mkdir -p "$candidate_dir" || return 1
  while IFS= read -r source_file; do
    [ "$source_file" = "$NOBRAND_SSH_CONFIG_DROPIN" ] && continue
    cp -a "$source_file" "$candidate_dir/" || return 1
  done < <(find "$source_dir" -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | LC_ALL=C sort)
  awk -v original='/etc/ssh/sshd_config.d/*.conf' -v replacement="$replacement" '
    {
      if (tolower($1)=="include") {
        changed=0
        for (i=2;i<=NF;i++) if ($i==original) {$i=replacement; changed=1}
        if (changed) {
          line=$1
          for (i=2;i<=NF;i++) line=line " " $i
          print line
          next
        }
      }
      print
    }
  ' "$NOBRAND_SSH_CONFIG_MAIN" >"$output"
}

ssh_tunnel_detect_service() {
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    systemctl status ssh.service >/dev/null 2>&1 && { printf 'systemd|ssh.service'; return 0; }
    systemctl status sshd.service >/dev/null 2>&1 && { printf 'systemd|sshd.service'; return 0; }
  fi
  if command -v rc-service >/dev/null 2>&1 && rc-service sshd status >/dev/null 2>&1; then
    printf 'openrc|sshd'
    return 0
  fi
  local pid_file pid
  for pid_file in /run/sshd.pid /var/run/sshd.pid; do
    [ -s "$pid_file" ] || continue
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null \
      && { printf 'sighup|%s' "$pid"; return 0; }
  done
  return 1
}

ssh_tunnel_reload() {
  local service kind name
  service="$(ssh_tunnel_detect_service)" || return 1
  kind="${service%%|*}"
  name="${service#*|}"
  case "$kind" in
    systemd) systemctl reload "$name" ;;
    openrc) rc-service "$name" reload ;;
    sighup) kill -HUP "$name" ;;
    *) return 1 ;;
  esac
}

ssh_tunnel_watchdog_token_valid() {
  local token="${1:-}"
  [ "$token" = disabled ] || [[ "$token" =~ ^([0-9a-f]{16}|[0-9a-f]{32})$ ]]
}

ssh_tunnel_watchdog_pid_valid() {
  local pid="${1:-}"
  [ -z "$pid" ] || [[ "$pid" =~ ^[0-9]+$ ]]
}

ssh_tunnel_pending_operation_valid() {
  case "${1:-}" in install|restore|uninstall|unified-uninstall) return 0 ;; esac
  return 1
}

ssh_tunnel_watchdog_pid_matches() {
  local token="$1" pid="${2:-}" script arg
  ssh_tunnel_watchdog_token_valid "$token" && [ "$token" != disabled ] || return 1
  [[ "$pid" =~ ^[0-9]+$ ]] && [ -r "/proc/${pid}/cmdline" ] || return 1
  script="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.rollback.sh"
  while IFS= read -r -d '' arg; do
    [ "$arg" = "$script" ] && return 0
  done <"/proc/${pid}/cmdline"
  return 1
}

ssh_tunnel_watchdog_stop_owned() {
  local token="$1" pid="${2:-}"
  ssh_tunnel_watchdog_pid_matches "$token" "$pid" || return 0
  kill "$pid" 2>/dev/null || true
}

ssh_tunnel_watchdog_cleanup_artifacts() {
  local token="$1" base script
  ssh_tunnel_watchdog_token_valid "$token" && [ "$token" != disabled ] || return 1
  base="${NOBRAND_SSH_WATCHDOG_DIR}/${token}"
  script="${base}.rollback.sh"
  rm -f "${base}.armed" "${base}.backup" "${base}.backup.absent" \
    "${base}.state.backup" "${base}.state.absent" "$script" \
    "${script}.confirmed" "${script}.cancelled"
}

ssh_tunnel_cleanup_disarmed_watchdogs() {
  local active=""
  if [ ! -e "$NOBRAND_SSH_WATCHDOG_DIR" ] && [ ! -L "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    return 0
  fi
  ssh_tunnel_watchdog_directory_preflight || return 1
  [ "$(stat -c '%a' "$NOBRAND_SSH_WATCHDOG_DIR")" = 700 ] || return 1
  active="$(find "$NOBRAND_SSH_WATCHDOG_DIR" -mindepth 1 -maxdepth 1 \
    \( -name '*.armed' -o -name '*.running' \) -print -quit)" || return 1
  [ -z "$active" ] || return 1
  find "$NOBRAND_SSH_WATCHDOG_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

ssh_tunnel_watchdog_directory_preflight() {
  [ "$NOBRAND_SSH_WATCHDOG_DIR" = "${NOBRAND_SSH_STATE_DIR}/watchdog" ] || return 1
  nb_assert_safe_nobrand_root "$NOBRAND_SSH_WATCHDOG_DIR" NOBRAND_SSH_WATCHDOG_DIR \
    >/dev/null || return 1
  [ -d "$NOBRAND_SSH_STATE_DIR" ] && [ ! -L "$NOBRAND_SSH_STATE_DIR" ] \
    && secure_stat_path "$NOBRAND_SSH_STATE_DIR" dir || return 1
  if [ -e "$NOBRAND_SSH_WATCHDOG_DIR" ] || [ -L "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    [ -d "$NOBRAND_SSH_WATCHDOG_DIR" ] && [ ! -L "$NOBRAND_SSH_WATCHDOG_DIR" ] \
      && secure_stat_path "$NOBRAND_SSH_WATCHDOG_DIR" dir || return 1
  fi
}

ssh_tunnel_prepare_watchdog_directory() {
  ssh_tunnel_watchdog_directory_preflight || return 1
  if [ ! -e "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    mkdir "$NOBRAND_SSH_WATCHDOG_DIR" || return 1
  fi
  chmod 0700 "$NOBRAND_SSH_WATCHDOG_DIR" \
    && chown root:root "$NOBRAND_SSH_WATCHDOG_DIR" 2>/dev/null \
    && secure_stat_path "$NOBRAND_SSH_WATCHDOG_DIR" dir \
    && [ "$(stat -c '%a' "$NOBRAND_SSH_WATCHDOG_DIR")" = 700 ]
}

# The armed/running claim is durable before its tuple can be committed to
# state.json. Treat that on-disk claim as an independent transaction boundary:
# after a manager SIGKILL, no later SSH mutation may race the still-authorized
# rollback and then be overwritten by its older snapshot. Fully disarmed
# leftovers remain eligible for the existing bounded cleanup routine.
ssh_tunnel_watchdog_mutation_preflight() {
  local active=""
  if [ "$NOBRAND_SSH_WATCHDOG_DIR" != "${NOBRAND_SSH_STATE_DIR}/watchdog" ]; then
    warn 'SSH watchdog 目录不在受管命名空间内；拒绝修改 SSH 状态'
    return 75
  fi
  if [ ! -e "$NOBRAND_SSH_WATCHDOG_DIR" ] && [ ! -L "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    return 0
  fi
  if ! ssh_tunnel_watchdog_directory_preflight \
     || [ "$(stat -c '%a' "$NOBRAND_SSH_WATCHDOG_DIR" 2>/dev/null || true)" != 700 ]; then
    warn 'SSH watchdog 目录的归属或权限无效；拒绝修改 SSH 状态'
    return 75
  fi
  active="$(find "$NOBRAND_SSH_WATCHDOG_DIR" -mindepth 1 -maxdepth 1 \
    \( -name '*.armed' -o -name '*.running' \) -print -quit)" || {
      warn '无法检查 SSH watchdog 操作权；拒绝修改 SSH 状态'
      return 75
    }
  [ -z "$active" ] || {
    warn 'SSH watchdog 回滚操作权尚未解决；拒绝并发修改 SSH 状态'
    return 75
  }
}

ssh_tunnel_watchdog_snapshot_pair_valid() {
  local payload="$1" absent="$2" kind="$3"
  if [ -e "$payload" ] || [ -L "$payload" ]; then
    [ ! -e "$absent" ] && [ ! -L "$absent" ] || return 1
    case "$kind" in
      config)
        if [ -L "$payload" ]; then
          return 0
        fi
        secure_stat_path "$payload" file
        ;;
      state) secure_stat_path "$payload" file ;;
      *) return 1 ;;
    esac
  else
    [ -f "$absent" ] && [ ! -L "$absent" ] \
      && secure_stat_path "$absent" file
  fi
}

ssh_tunnel_watchdog_claim_ready() {
  local token="$1" pid="${2:-}" base script armed artifact
  ssh_tunnel_watchdog_token_valid "$token" && [ "$token" != disabled ] || return 1
  [[ "$pid" =~ ^[0-9]+$ ]] && [ "$((10#$pid))" -gt 1 ] || return 1
  ssh_tunnel_watchdog_directory_preflight || return 1
  [ "$(stat -c '%a' "$NOBRAND_SSH_WATCHDOG_DIR")" = 700 ] || return 1
  base="${NOBRAND_SSH_WATCHDOG_DIR}/${token}"
  script="${base}.rollback.sh"
  armed="${base}.armed"
  [ -f "$script" ] && [ ! -L "$script" ] && [ -x "$script" ] \
    && secure_stat_path "$script" file \
    && [ "$(stat -c '%a' "$script")" = 700 ] || return 1
  [ -f "$armed" ] && [ ! -L "$armed" ] \
    && secure_stat_path "$armed" file \
    && [ "$(stat -c '%a' "$armed")" = 600 ] || return 1
  for artifact in "${script}.running" "${script}.confirmed" "${script}.cancelled"; do
    [ ! -e "$artifact" ] && [ ! -L "$artifact" ] || return 1
  done
  ssh_tunnel_watchdog_snapshot_pair_valid "${base}.backup" "${base}.backup.absent" config \
    && ssh_tunnel_watchdog_snapshot_pair_valid \
      "${base}.state.backup" "${base}.state.absent" state \
    && ssh_tunnel_watchdog_pid_matches "$token" "$pid"
}

ssh_tunnel_write_watchdog_script() {
  local timeout="$1" token_file="$2" script="$3" backup="$4" target="$5"
  local sshd="$6" main_config="$7" kind="$8" name="$9" state_backup="${10}"
  local state_absent="${11}" state_file="${12}"
  printf '#!/usr/bin/env bash\nset -eu\n[ "${NOBRAND_SSH_WATCHDOG_NOW:-0}" = 1 ] || sleep %q\n' \
    "$timeout" || return 1
  # Confirmation and rollback compete for one atomic rename. Only the
  # process that owns the resulting claim file may mutate SSH or state.
  printf 'mv -f -- %q %q 2>/dev/null || exit 0\n' \
    "$token_file" "${script}.running" || return 1
  printf 'if [ -e %q ] || [ -L %q ]; then\n' "$backup" "$backup" || return 1
  printf '  { [ -f %q ] || [ -L %q ]; } || exit 1\n' "$backup" "$backup" || return 1
  printf '  rm -f -- %q\n  cp -a -- %q %q\n' "$target" "$backup" "$target" || return 1
  printf 'elif [ -f %q ] && [ ! -L %q ]; then\n' \
    "${backup}.absent" "${backup}.absent" || return 1
  printf '  rm -f -- %q\nelse\n  exit 1\nfi\n' "$target" || return 1
  printf '%q -t -f %q || exit 1\n' "$sshd" "$main_config" || return 1
  case "$kind" in
    systemd) printf 'systemctl reload %q\n' "$name" || return 1 ;;
    openrc) printf 'rc-service %q reload\n' "$name" || return 1 ;;
    sighup) printf 'kill -HUP %q\n' "$name" || return 1 ;;
    *) return 1 ;;
  esac
  printf 'if [ -f %q ] && [ ! -L %q ]; then\n' \
    "$state_backup" "$state_backup" || return 1
  printf '  rm -f -- %q\n  cp -a -- %q %q\n' \
    "$state_file" "$state_backup" "$state_file" || return 1
  printf 'elif [ -f %q ] && [ ! -L %q ]; then\n' \
    "$state_absent" "$state_absent" || return 1
  printf '  rm -f -- %q\nelse\n  exit 1\nfi\n' "$state_file" || return 1
  printf 'rm -f %q %q %q %q %q %q %q\n' "$token_file" "$backup" \
    "${backup}.absent" "$state_backup" "$state_absent" "$script" \
    "${script}.running" || return 1
}

ssh_tunnel_watchdog_begin() {
  local target="$1" operation="$2" token origin service kind name backup script token_file timeout pid
  local state_backup state_absent sshd artifact ready=0 attempts=0
  ssh_tunnel_pending_operation_valid "$operation" || return 1
  ssh_tunnel_watchdog_mutation_preflight || return $?
  [ "${NOBRAND_SSH_WATCHDOG_DISABLED:-0}" != 1 ] \
    || {
      [ "${MITA_SOURCE_ONLY:-0}" = 1 ] || return 1
      printf 'disabled|||%s' "$operation"
      return 0
    }
  ssh_tunnel_prepare_watchdog_directory || return 1
  token="$(openssl rand -hex 16 2>/dev/null || printf '%08x%08x' "$RANDOM" "$RANDOM")"
  ssh_tunnel_watchdog_token_valid "$token" && [ "$token" != disabled ] || return 1
  origin="${SSH_CONNECTION:-}"
  backup="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.backup"
  state_backup="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.state.backup"
  state_absent="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.state.absent"
  script="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.rollback.sh"
  token_file="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.armed"
  for artifact in "$backup" "${backup}.absent" "$state_backup" "$state_absent" \
    "$script" "$token_file" "${script}.running" "${script}.confirmed" "${script}.cancelled"; do
    [ ! -e "$artifact" ] && [ ! -L "$artifact" ] || return 1
  done
  if [ -e "$target" ] || [ -L "$target" ]; then
    [ -f "$target" ] || [ -L "$target" ] || return 1
    cp -a "$target" "$backup" || {
      ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
      return 1
    }
  elif ! : >"${backup}.absent" || ! chmod 0600 "${backup}.absent"; then
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  fi
  if [ -e "$NOBRAND_SSH_STATE_FILE" ] || [ -L "$NOBRAND_SSH_STATE_FILE" ]; then
    [ -f "$NOBRAND_SSH_STATE_FILE" ] && [ ! -L "$NOBRAND_SSH_STATE_FILE" ] || {
      ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
      return 1
    }
    cp -a "$NOBRAND_SSH_STATE_FILE" "$state_backup" || {
      ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
      return 1
    }
  else
    : >"$state_absent" && chmod 0600 "$state_absent" || {
      ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
      return 1
    }
  fi
  service="$(ssh_tunnel_detect_service)" || {
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  }
  kind="${service%%|*}"
  name="${service#*|}"
  case "$kind" in systemd|openrc|sighup) ;; *)
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
    ;;
  esac
  [ -n "$name" ] || {
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  }
  sshd="$(ssh_tunnel_sshd_binary)" || {
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  }
  timeout="${NOBRAND_SSH_WATCHDOG_TIMEOUT:-180}"
  [[ "$timeout" =~ ^[0-9]+$ ]] && [ "$timeout" -ge 30 ] || timeout=180
  if ! ssh_tunnel_write_watchdog_script "$timeout" "$token_file" "$script" "$backup" \
    "$target" "$sshd" "$NOBRAND_SSH_CONFIG_MAIN" "$kind" "$name" \
    "$state_backup" "$state_absent" "$NOBRAND_SSH_STATE_FILE" >"$script"; then
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  fi
  chmod 0700 "$script" || {
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  }
  : >"$token_file" && chmod 0600 "$token_file" || {
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  }
  # The watchdog intentionally outlives this manager process while a fresh
  # administrator connection confirms the SSH policy. Do not let it inherit
  # the lifecycle flock, otherwise that confirmation process cannot start.
  NOBRAND_SSH_WATCHDOG_NOW=0 nohup "$script" 7>&- >/dev/null 2>&1 &
  pid=$!
  while [ "$attempts" -lt 100 ]; do
    if ssh_tunnel_watchdog_claim_ready "$token" "$pid"; then
      ready=1
      break
    fi
    kill -0 "$pid" 2>/dev/null || break
    attempts=$((attempts + 1))
    sleep 0.01
  done
  if [ "$ready" -ne 1 ] || ! ssh_tunnel_watchdog_claim_ready "$token" "$pid"; then
    # Claim cancellation is itself atomic. If rollback already owns the
    # artifacts, leave them untouched and report failure.
    ssh_tunnel_watchdog_cancel "$token" "$pid" >/dev/null 2>&1 || true
    return 1
  fi
  printf '%s|%s|%s|%s' "$token" "$pid" "$origin" "$operation"
}

ssh_tunnel_watchdog_cancel() {
  local token="$1" pid="${2:-}" base script cancelled
  [ "$token" != disabled ] || return 0
  ssh_tunnel_watchdog_token_valid "$token" || return 1
  ssh_tunnel_watchdog_pid_valid "$pid" || return 1
  base="${NOBRAND_SSH_WATCHDOG_DIR}/${token}"
  script="${base}.rollback.sh"
  cancelled="${script}.cancelled"
  if ! mv -f -- "${base}.armed" "$cancelled" 2>/dev/null; then
    # A running rollback or a confirmation owns these artifacts now. Never
    # remove its snapshots or terminate its process.
    [ ! -e "${script}.running" ] && [ ! -e "${script}.confirmed" ] \
      && [ ! -e "$cancelled" ] && [ ! -e "$script" ] && return 0
    return 1
  fi
  ssh_tunnel_watchdog_stop_owned "$token" "$pid"
  ssh_tunnel_watchdog_cleanup_artifacts "$token"
}

ssh_tunnel_watchdog_rollback_now() {
  local token="$1" pid="${2:-}" base script rc=0
  [ "$token" != disabled ] || return 0
  ssh_tunnel_watchdog_token_valid "$token" || return 1
  ssh_tunnel_watchdog_pid_valid "$pid" || return 1
  base="${NOBRAND_SSH_WATCHDOG_DIR}/${token}"
  script="${base}.rollback.sh"
  [ -x "$script" ] || return 1
  # Run the same atomic claimant synchronously before considering process
  # termination. If the sleeping watchdog already won, leave it untouched.
  NOBRAND_SSH_WATCHDOG_NOW=1 bash "$script" || rc=$?
  if [ "$rc" -eq 0 ] && [ ! -e "${script}.running" ] \
     && [ ! -e "${script}.confirmed" ] && [ ! -e "${base}.armed" ]; then
    ssh_tunnel_watchdog_stop_owned "$token" "$pid"
    return 0
  fi
  return 1
}

ssh_tunnel_watchdog_prompt() {
  local token="$1"
  t "SSH policy 已安全 reload；请在 ${NOBRAND_SSH_WATCHDOG_TIMEOUT:-180} 秒内通过全新管理员 SSH 连接运行：" \
    "SSH policy safely reloaded; from a brand-new administrator SSH connection, run within ${NOBRAND_SSH_WATCHDOG_TIMEOUT:-180} seconds:"
  printf '  nobrand ssh confirm-admin --token %s\n' "$token"
}

ssh_tunnel_apply_policy() {
  local validation_user="$1" requested_operation="${2:-install}"
  local policy strategy target candidate watchdog token pid origin operation state_tmp
  ssh_tunnel_watchdog_mutation_preflight || return $?
  policy="$(mktemp_file .ssh-policy)" || return 1
  candidate="$(mktemp_file .sshd-candidate)" || { rm -f "$policy"; return 1; }
  ssh_tunnel_generate_policy "$policy" || { rm -f "$policy" "$candidate"; return 1; }
  if ssh_tunnel_dropin_supported; then
    strategy=dropin
    target="$NOBRAND_SSH_CONFIG_DROPIN"
  else
    strategy="marker-block"
    target="$NOBRAND_SSH_CONFIG_MAIN"
  fi
  if ! ssh_tunnel_apply_target_preflight "$strategy" "$target" "$policy" \
    "$requested_operation"; then
    rm -f "$policy" "$candidate"
    warn 'SSH 配置目标已存在但无法证明归属，或其符号链接拓扑无法安全保留；拒绝修改'
    return 1
  fi
  ssh_tunnel_build_main_candidate "$policy" "$candidate" \
    || { rm -f "$policy" "$candidate"; return 1; }
  ssh_tunnel_sshd_test "$candidate" || {
    rm -f "$policy" "$candidate"
    warn 'SSH 候选配置语法校验失败'
    return 1
  }
  ssh_tunnel_effective_policy_valid "$candidate" "$validation_user" \
    || {
      rm -f "$policy" "$candidate"
      warn 'SSH 候选配置的生效策略校验失败'
      return 1
    }
  state_tmp="$(mktemp_file .ssh-state)" \
    || { rm -f "$policy" "$candidate"; return 1; }
  watchdog="$(ssh_tunnel_watchdog_begin "$target" "$requested_operation")" || {
    rm -f "$policy" "$candidate" "$state_tmp"
    return 1
  }
  IFS='|' read -r token pid origin operation <<<"$watchdog"
  if ! jq --arg strategy "$strategy" --arg path "$target" --arg token "$token" \
    --arg pid "$pid" --arg origin "$origin" --arg operation "$operation" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .config_strategy=$strategy | .managed_config_path=$path | .policy_applied=true
    | .pending_operation=$operation | .pending_watchdog_token=$token
    | .pending_watchdog_pid=$pid | .pending_origin_connection=$origin | .updated_at=$updated
  ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp"; then
    rm -f "$policy" "$candidate" "$state_tmp"
    if ! ssh_tunnel_watchdog_cancel "$token" "$pid"; then
      warn 'SSH watchdog 已取得操作权或无法安全取消；状态与回滚快照已保留'
      return 75
    fi
    return 1
  fi
  mkdir -p "$(dirname "$target")" || {
    rm -f "$policy" "$candidate" "$state_tmp"
    if ! ssh_tunnel_watchdog_cancel "$token" "$pid"; then
      warn 'SSH watchdog 已取得操作权或无法安全取消；状态与回滚快照已保留'
      return 75
    fi
    return 1
  }
  if [ "$strategy" = dropin ]; then
    nb_atomic_install_file "$policy" "$target" 0600 || {
      rm -f "$policy" "$candidate" "$state_tmp"
      if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
        warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
        return 75
      fi
      return 1
    }
  else
    nb_atomic_install_file "$candidate" "$target" 0600 || {
      rm -f "$policy" "$candidate" "$state_tmp"
      if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
        warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
        return 75
      fi
      return 1
    }
  fi
  if ! ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" \
     || ! ssh_tunnel_effective_policy_valid "$NOBRAND_SSH_CONFIG_MAIN" "$validation_user" \
     || ! ssh_tunnel_reload; then
    warn 'SSH 策略应用或重新加载失败，正在立即回滚'
    rm -f "$policy" "$candidate" "$state_tmp"
    if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
      warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
      return 75
    fi
    return 1
  fi
  if [ "$token" != disabled ] \
     && ! ssh_tunnel_watchdog_claim_ready "$token" "$pid"; then
    rm -f "$policy" "$candidate" "$state_tmp"
    warn 'SSH watchdog 已取得回滚权或回滚事务已失效；拒绝提交待确认状态'
    return 75
  fi
  if ! nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600; then
    rm -f "$policy" "$candidate" "$state_tmp"
    if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
      warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
      return 75
    fi
    return 1
  fi
  rm -f "$state_tmp" "$policy" "$candidate"
  if [ "$token" = disabled ]; then
    if ! ssh_tunnel_confirm_admin disabled; then
      warn 'SSH 策略已写入但待确认状态未能完成；已保留状态供安全重试'
      return 75
    fi
  else
    if ! ssh_tunnel_watchdog_prompt "$token"; then
      warn 'SSH 策略仍在等待确认，但确认提示输出失败；已保留 watchdog 状态'
      return 75
    fi
  fi
}

ssh_tunnel_remove_policy() {
  local requested_operation="${1:-uninstall}" strategy target candidate candidate_root="" policy=""
  local watchdog token pid origin operation state_tmp managed_path
  ssh_tunnel_watchdog_mutation_preflight || return $?
  managed_path="$(ssh_tunnel_state_field managed_config_path)" || return 1
  strategy="$(ssh_tunnel_state_field config_strategy)" || return 1
  candidate_root="$(mktemp_dir)" || return 1
  candidate="${candidate_root}/sshd_config"
  policy="$(mktemp_file .ssh-policy)" || {
    rm -rf -- "$candidate_root"
    return 1
  }
  case "$strategy" in
    dropin)
      if [ "$managed_path" != "$NOBRAND_SSH_CONFIG_DROPIN" ] \
         || ! ssh_tunnel_generate_policy "$policy" \
         || ! ssh_tunnel_existing_dropin_owned "$managed_path" "$policy"; then
        rm -f "$policy"
        rm -rf -- "$candidate_root"
        warn 'SSH 受管 drop-in 缺失、已被替换或无法证明归属；拒绝删除'
        return 1
      fi
      if ! ssh_tunnel_build_dropin_removal_candidate "$candidate" "$candidate_root"; then
        rm -f "$policy"
        rm -rf -- "$candidate_root"
        return 1
      fi
      target="$managed_path"
      ;;
    marker-block)
      if [ "$managed_path" != "$NOBRAND_SSH_CONFIG_MAIN" ] \
         || ! ssh_tunnel_generate_policy "$policy" \
         || ! ssh_tunnel_existing_marker_block_owned \
           "$NOBRAND_SSH_CONFIG_MAIN" "$policy"; then
        rm -f "$policy"
        rm -rf -- "$candidate_root"
        warn 'SSH 受管标记块缺失、已被替换或无法证明归属；拒绝移除'
        return 1
      fi
      if ! ssh_tunnel_strip_marker_block "$NOBRAND_SSH_CONFIG_MAIN" "$candidate"; then
        rm -f "$policy"
        rm -rf -- "$candidate_root"
        return 1
      fi
      target="$NOBRAND_SSH_CONFIG_MAIN"
      ;;
    *)
      rm -f "$policy"
      rm -rf -- "$candidate_root"
      warn 'SSH 受管配置策略无效'
      return 1
      ;;
  esac
  ssh_tunnel_sshd_test "$candidate" || {
    rm -f "$policy"
    rm -rf -- "$candidate_root"
    warn 'SSH 策略移除候选配置无法通过 sshd -t'
    return 1
  }
  watchdog="$(ssh_tunnel_watchdog_begin "$target" "$requested_operation")" || {
    rm -f "$policy"
    rm -rf -- "$candidate_root"
    return 1
  }
  IFS='|' read -r token pid origin operation <<<"$watchdog"
  state_tmp="$(mktemp_file .ssh-state)" || {
    rm -f "$policy"
    rm -rf -- "$candidate_root"
    if ! ssh_tunnel_watchdog_cancel "$token" "$pid"; then
      warn 'SSH watchdog 已取得操作权或无法安全取消；状态与回滚快照已保留'
      return 75
    fi
    return 1
  }
  if ! jq --arg token "$token" --arg pid "$pid" --arg origin "$origin" --arg operation "$operation" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .policy_applied=false | .pending_operation=$operation | .pending_watchdog_token=$token
    | .pending_watchdog_pid=$pid | .pending_origin_connection=$origin | .updated_at=$updated
  ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp"; then
    rm -f "$policy" "$state_tmp"
    rm -rf -- "$candidate_root"
    if ! ssh_tunnel_watchdog_cancel "$token" "$pid"; then
      warn 'SSH watchdog 已取得操作权或无法安全取消；状态与回滚快照已保留'
      return 75
    fi
    return 1
  fi
  if [ "$strategy" = dropin ]; then
    rm -f "$target" || {
      rm -f "$policy" "$state_tmp"
      rm -rf -- "$candidate_root"
      if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
        warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
        return 75
      fi
      return 1
    }
  else
    nb_atomic_install_file "$candidate" "$target" 0600 || {
      rm -f "$policy" "$state_tmp"
      rm -rf -- "$candidate_root"
      if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
        warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
        return 75
      fi
      return 1
    }
  fi
  if ! ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" || ! ssh_tunnel_reload; then
    warn 'SSH 策略移除或重新加载失败，正在立即回滚'
    rm -f "$policy" "$state_tmp"
    rm -rf -- "$candidate_root"
    if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
      warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
      return 75
    fi
    return 1
  fi
  if [ "$token" != disabled ] \
     && ! ssh_tunnel_watchdog_claim_ready "$token" "$pid"; then
    rm -f "$policy" "$state_tmp"
    rm -rf -- "$candidate_root"
    warn 'SSH watchdog 已取得回滚权或回滚事务已失效；拒绝提交待确认状态'
    return 75
  fi
  if ! nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600; then
    rm -f "$policy" "$state_tmp"
    rm -rf -- "$candidate_root"
    if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
      warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
      return 75
    fi
    return 1
  fi
  rm -f "$policy" "$state_tmp"
  rm -rf -- "$candidate_root"
  if [ "$token" = disabled ]; then
    if ! ssh_tunnel_confirm_admin disabled; then
      warn 'SSH 策略移除状态已写入但待确认状态未能完成；已保留状态供安全重试'
      return 75
    fi
  else
    if ! ssh_tunnel_watchdog_prompt "$token"; then
      warn 'SSH 策略移除仍在等待确认，但确认提示输出失败；已保留 watchdog 状态'
      return 75
    fi
  fi
}

ssh_tunnel_state_identity_file_valid() {
  local state_file="$1"
  [ -f "$state_file" ] && [ ! -L "$state_file" ] || return 1
  jq -e --arg group "$NOBRAND_SSH_GROUP" --arg main "$NOBRAND_SSH_CONFIG_MAIN" \
    --arg dropin "$NOBRAND_SSH_CONFIG_DROPIN" '
    .schema_version==3 and .ownership=="nobrand-v3" and .protocol=="ssh-tunnel"
    and .external_listener==true and .managed_listener==false and .managed_firewall==false
    and .group==$group and (.policy_applied|type)=="boolean"
    and (.real_port|type)=="number" and .real_port>=1 and .real_port<=65535
    and (.real_port|floor)==.real_port
    and (.advertise_mode=="auto" or .advertise_mode=="custom")
    and (.advertise_host|type)=="string"
    and (.advertise_port|type)=="number" and .advertise_port>=1 and .advertise_port<=65535
    and (.advertise_port|floor)==.advertise_port
    and (.config_strategy=="marker-block" or .config_strategy=="dropin")
    and ((.config_strategy=="marker-block" and .managed_config_path==$main)
      or (.config_strategy=="dropin" and .managed_config_path==$dropin))
    and (.users|type)=="array"
    and all(.users[];
      (.account_id|type)=="string"
      and (.account_id|test("^a([0-9a-f]{16}|[0-9a-f]{32})$"))
      and (.linux_user|type)=="string" and (.linux_user|test("^nbt-[a-z0-9_-]{1,27}$"))
      and (.uid|type)=="number" and .uid>=0 and (.uid|floor)==.uid
      and .group==$group
      and (.key_fingerprint|type)=="string"
      and (.key_fingerprint|test("^SHA256:[A-Za-z0-9+/]{43}$"))
    )
    and ([.users[].account_id]|unique|length)==(.users|length)
    and ([.users[].linux_user]|unique|length)==(.users|length)
    and ([.users[].uid]|unique|length)==(.users|length)
    and ((.pending_operation // "")|type)=="string"
    and ((.pending_watchdog_token // "")|type)=="string"
    and ((.pending_watchdog_pid // "")|type)=="string"
    and ((.pending_origin_connection // "")|type)=="string"
  ' "$state_file" >/dev/null 2>&1
}

ssh_tunnel_state_identity_valid() {
  ssh_tunnel_state_identity_file_valid "$NOBRAND_SSH_STATE_FILE"
}

ssh_tunnel_pending_tuple_valid() {
  local operation="$1" token="$2" pid="${3:-}" origin="${4:-}" policy="$5"
  ssh_tunnel_pending_operation_valid "$operation" || return 1
  [ -n "$token" ] && ssh_tunnel_watchdog_token_valid "$token" || return 1
  ssh_tunnel_watchdog_pid_valid "$pid" || return 1
  if [ "$token" = disabled ]; then
    [ -z "$pid" ] && [ -z "$origin" ] || return 1
  else
    [[ "$pid" =~ ^[0-9]+$ ]] && [ "$((10#$pid))" -gt 1 ] || return 1
  fi
  ! has_control_chars "$origin" || return 1
  case "$operation:$policy" in
    install:true|restore:true|uninstall:false|unified-uninstall:false) return 0 ;;
  esac
  return 1
}

ssh_tunnel_policy_absent() {
  local strategy managed_path
  strategy="$(ssh_tunnel_state_field config_strategy 2>/dev/null || true)"
  managed_path="$(ssh_tunnel_state_field managed_config_path 2>/dev/null || true)"
  case "$strategy" in
    dropin)
      [ "$managed_path" = "$NOBRAND_SSH_CONFIG_DROPIN" ] || return 1
      [ ! -e "$managed_path" ] && [ ! -L "$managed_path" ] || return 1
      ;;
    marker-block)
      [ "$managed_path" = "$NOBRAND_SSH_CONFIG_MAIN" ] || return 1
      ! grep -Fqx "$NOBRAND_SSH_BLOCK_BEGIN" "$NOBRAND_SSH_CONFIG_MAIN" 2>/dev/null \
        && ! grep -Fqx "$NOBRAND_SSH_BLOCK_END" "$NOBRAND_SSH_CONFIG_MAIN" 2>/dev/null \
        || return 1
      ;;
    *) return 1 ;;
  esac
  ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN"
}

ssh_tunnel_confirm_admin() {
  local supplied="${1:-}" expected pid origin current operation policy state_tmp=""
  local base script confirmed continue_unified=0 resume_repair=0
  require_root
  ssh_tunnel_state_identity_valid || die 'SSH Tunnel 状态无效，拒绝确认 watchdog'
  expected="$(ssh_tunnel_state_field pending_watchdog_token)"
  [ -n "$expected" ] || die '没有待确认的 SSH 策略 watchdog'
  ssh_tunnel_watchdog_token_valid "$expected" || die 'SSH watchdog token 状态无效'
  [ "$supplied" = "$expected" ] || die 'watchdog token 不匹配'
  origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
  operation="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
  pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
  policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
  ssh_tunnel_pending_tuple_valid "$operation" "$expected" "$pid" "$origin" "$policy" \
    || die 'SSH watchdog 待确认状态不一致，拒绝继续'
  current="${SSH_CONNECTION:-}"
  if [ "$expected" != disabled ]; then
    [ -n "$current" ] || die '必须从一条全新的管理员 SSH 连接确认 watchdog'
    [ -z "$origin" ] || [ "$current" != "$origin" ] \
      || die '必须从一条全新的管理员 SSH 连接确认 watchdog'
  fi
  ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" || return 1
  if [ "$operation" = uninstall ] || [ "$operation" = unified-uninstall ]; then
    ssh_tunnel_policy_absent || die 'SSH 受管策略仍存在或状态不一致，拒绝完成卸载确认'
  fi
  if [ "$expected" != disabled ]; then
    base="${NOBRAND_SSH_WATCHDOG_DIR}/${expected}"
    script="${base}.rollback.sh"
    confirmed="${script}.confirmed"
    if [ -e "$confirmed" ] || [ -L "$confirmed" ]; then
      [ -f "$confirmed" ] && [ ! -L "$confirmed" ] \
        || die 'SSH watchdog 确认标记无效，拒绝继续'
      [ ! -e "${base}.armed" ] && [ ! -L "${base}.armed" ] \
        && [ ! -e "${script}.running" ] && [ ! -L "${script}.running" ] \
        || die 'SSH watchdog 存在冲突的操作权标记，拒绝继续'
    else
      ssh_tunnel_watchdog_claim_ready "$expected" "$pid" \
        || die 'SSH watchdog 进程或回滚快照已失效，拒绝确认'
      if ! mv -f -- "${base}.armed" "$confirmed" 2>/dev/null; then
      if [ -e "${script}.running" ]; then
        die 'SSH 回滚 watchdog 已取得操作权；请等待回滚完成后重试'
      fi
      die 'SSH watchdog 已不再等待确认；状态未更改，请检查回滚结果'
      fi
    fi
  fi
  state_tmp="$(mktemp_file .ssh-state)" || return 1
  jq --arg operation "$operation" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .pending_operation=(if ($operation=="uninstall" or $operation=="unified-uninstall")
      then $operation else "" end)
    | .pending_watchdog_token="" | .pending_watchdog_pid=""
    | .pending_origin_connection=""
    | .policy_applied=(if ($operation=="uninstall" or $operation=="unified-uninstall") then false else true end)
    | .updated_at=$updated
  ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
    && nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 || {
      rm -f "$state_tmp"
      [ "$expected" = disabled ] || ssh_tunnel_watchdog_stop_owned "$expected" "$pid"
      # Keep the confirmed claim and snapshots. The same token can safely
      # retry the state commit; the rollback process can no longer win.
      return 1
    }
  rm -f "$state_tmp"
  if [ "$expected" != disabled ]; then
    ssh_tunnel_watchdog_stop_owned "$expected" "$pid"
    ssh_tunnel_watchdog_cleanup_artifacts "$expected" || return 1
  fi
  t '全新管理员 SSH 连接已确认；回滚 watchdog 已取消' \
    'Brand-new administrator SSH connection confirmed; rollback watchdog cancelled'
  case "$operation" in
    uninstall) ssh_tunnel_finalize_uninstall uninstall ;;
    unified-uninstall)
      ssh_tunnel_finalize_uninstall unified-uninstall || return 1
      continue_unified=1
      ;;
    restore)
      if [ "$expected" != disabled ] \
         && declare -F nb_lifecycle_tx_valid >/dev/null 2>&1 \
         && nb_lifecycle_tx_valid \
         && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
         && [ "$(nb_lifecycle_field OPERATION)" = repair ]; then
        resume_repair=1
      fi
      ;;
  esac
  if [ "$continue_unified" -eq 1 ]; then
    YES=1 nobrand_uninstall || return 1
  elif [ "$resume_repair" -eq 1 ]; then
    do_install || return 1
  fi
  if [ "$operation" = restore ] \
     && declare -F nobrand_backup_restore_confirmation_finalize >/dev/null 2>&1; then
    nobrand_backup_restore_confirmation_finalize || return 1
  fi
}

ssh_tunnel_set_endpoint_state() {
  local host="$1" port="$2" mode=custom tmp
  ssh_tunnel_watchdog_mutation_preflight || return $?
  ssh_tunnel_state_exists || die 'SSH Tunnel 未安装'
  if [ -z "$host" ]; then
    mode=auto
    port="$(ssh_tunnel_default_display_port)" || die '无法安全推导 SSH Display Endpoint 端口'
  else
    valid_advertise_host "$host" || die 'SSH Display Endpoint 主机无效'
    valid_advertise_port "$port" || die 'SSH Display Endpoint 端口无效'
    port="$(normalize_uint "$port")"
  fi
  tmp="$(mktemp_file .ssh-state)" || return 1
  jq --arg mode "$mode" --arg host "$host" --arg port "$port" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .advertise_mode=$mode | .advertise_host=$host | .advertise_port=($port|tonumber)
    | .updated_at=$updated
  ' "$NOBRAND_SSH_STATE_FILE" >"$tmp" \
    && nb_atomic_install_file "$tmp" "$NOBRAND_SSH_STATE_FILE" 0600
  rm -f "$tmp"
}

ssh_tunnel_effective_host() {
  local mode host ingress_profile_id
  mode="$(ssh_tunnel_state_field advertise_mode)"
  host="$(ssh_tunnel_state_field advertise_host)"
  ingress_profile_id="$(ssh_tunnel_state_field ingress_profile_id 2>/dev/null || true)"
  nb_effective_advertise_host "$mode" "$host" "$ingress_profile_id"
}

ssh_tunnel_host_public_key() {
  local candidate
  for candidate in /etc/ssh/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ecdsa_key.pub \
    /etc/ssh/ssh_host_rsa_key.pub; do
    [ -s "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

ssh_tunnel_known_hosts_entry() {
  local host="$1" port="$2" public_key key_fields known_host
  public_key="$(ssh_tunnel_host_public_key)" || return 1
  key_fields="$(awk '{print $1" "$2}' "$public_key")"
  known_host="$host"
  [ "$port" = 22 ] || known_host="[${host}]:${port}"
  printf '%s %s' "$known_host" "$key_fields"
}

ssh_tunnel_show_user() {
  local selector="${1:-}" user_json account_id label linux_user host port key_path
  user_json="$(ssh_tunnel_resolve_user_json "$selector")" || return 1
  account_id="$(jq -r .account_id <<<"$user_json")"
  label="$(jq -r .display_name <<<"$user_json")"
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  host="$(ssh_tunnel_effective_host)"
  port="$(ssh_tunnel_state_field advertise_port)"
  key_path="$(ssh_tunnel_key_dir "$account_id")/id_ed25519"
  printf 'SSH Tunnel 用户: %s\nLinux 身份: %s\n入口配置 / Ingress Profile: %s\nIngress 强制策略: 不适用（系统 sshd）\n系统实际监听 / Actual Listener: *:%s/TCP\n展示端点 / Display Endpoint: %s:%s\n' \
    "$label" "$linux_user" "$(nb_ingress_profile_name "$(ssh_tunnel_state_field ingress_profile_id 2>/dev/null || true)")" \
    "$(ssh_tunnel_state_field real_port)" "$host" "$port"
  printf '连接命令: ssh -N -i %s -p %s %s@%s\n' "$key_path" "$port" "$linux_user" "$host"
  printf 'TCP 转发：-L / -D / -R\nGatewayPorts=no；shell / exec / TTY / SFTP / SCP 均已禁用。\n'
}

ssh_tunnel_export_user() {
  local selector="${1:-}" user_json account_id label linux_user host port key_path public_key
  local fingerprint known_hosts
  user_json="$(ssh_tunnel_resolve_user_json "$selector")" || return 1
  account_id="$(jq -r .account_id <<<"$user_json")"
  label="$(jq -r .display_name <<<"$user_json")"
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  host="$(ssh_tunnel_effective_host)"
  port="$(ssh_tunnel_state_field advertise_port)"
  key_path="$(ssh_tunnel_key_dir "$account_id")/id_ed25519"
  public_key="$(ssh_tunnel_host_public_key 2>/dev/null || true)"
  fingerprint='不可用'
  known_hosts='不可用'
  [ -z "$public_key" ] || fingerprint="$(ssh-keygen -lf "$public_key" -E sha256 2>/dev/null || printf '不可用')"
  known_hosts="$(ssh_tunnel_known_hosts_entry "$host" "$port" 2>/dev/null || printf '不可用')"
  printf '%s\n' '===== OPENSSH 私钥（显式导出）====='
  cat "$key_path" || return 1
  printf '%s\n' '===== OPENSSH 私钥结束 =====' ''
  printf '主机密钥指纹: %s\nknown_hosts: %s\n\n' "$fingerprint" "$known_hosts"
  printf 'SOCKS5 命令:\nssh -N -D 127.0.0.1:1080 -i <PRIVATE_KEY> -p %s %s@%s' \
    "$port" "$linux_user" "$host"
  printf ' -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3\n\n'
  printf 'LocalForward 模板:\nssh -N -L <LOCAL_BIND>:<TARGET_HOST>:<TARGET_PORT> -i <PRIVATE_KEY> -p %s %s@%s -o ExitOnForwardFailure=yes\n\n' \
    "$port" "$linux_user" "$host"
  printf 'RemoteForward 模板:\nssh -N -R <REMOTE_PORT>:<TARGET_HOST>:<TARGET_PORT> -i <PRIVATE_KEY> -p %s %s@%s -o ExitOnForwardFailure=yes\n' \
    "$port" "$linux_user" "$host"
  printf 'GatewayPorts=no：RemoteForward 仅监听回环地址，不能暴露公网监听。\n\n'
  printf 'OpenSSH 配置:\nHost nobrand-%s\n  HostName %s\n  Port %s\n  User %s\n  IdentityFile <PRIVATE_KEY>\n  IdentitiesOnly yes\n  ExitOnForwardFailure yes\n  ServerAliveInterval 30\n  ServerAliveCountMax 3\n' \
    "$(safe_filename_component "$label")" "$host" "$port" "$linux_user"
}

ssh_tunnel_node_rows() {
  local host port status user_json label
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent && return 0
    return 1
  fi
  host="$(ssh_tunnel_effective_host)"
  port="$(ssh_tunnel_state_field advertise_port)"
  status=Stopped
  [ "$(ssh_tunnel_state_field policy_applied 2>/dev/null || printf false)" = true ] && status=Ready
  while IFS= read -r user_json; do
    [ -n "$user_json" ] || continue
    label="$(jq -r .display_name <<<"$user_json")"
    printf 'SSH Tunnel|%s|%s:%s|%s|TCP (external sshd)\n' "$label" "$host" "$port" "$status"
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
}

ssh_tunnel_doctor() {
  local failed=0 user_json managed_path validation_user
  if ! ssh_tunnel_state_exists; then
    if ssh_tunnel_state_absent; then
      nb_doctor_line INFO 'SSH Tunnel 未安装'
      return 0
    fi
    nb_doctor_line FAIL 'SSH Tunnel 权威状态损坏或无法读取'
    return 1
  fi
  ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" \
    && nb_doctor_line PASS 'sshd 配置语法有效' \
    || { nb_doctor_line FAIL 'sshd 配置语法无效'; failed=1; }
  managed_path="$(ssh_tunnel_state_field managed_config_path)"
  [ -s "$managed_path" ] && nb_doctor_line PASS '受管 Match 策略存在' \
    || { nb_doctor_line FAIL '缺少受管 Match 策略'; failed=1; }
  ssh_tunnel_group_identity_valid && nb_doctor_line PASS '专用用户组身份有效' \
    || { nb_doctor_line FAIL '专用用户组身份无效'; failed=1; }
  validation_user="$(jq -r '.users[0].linux_user // empty' "$NOBRAND_SSH_STATE_FILE")"
  [ -z "$validation_user" ] || ssh_tunnel_effective_policy_valid "$NOBRAND_SSH_CONFIG_MAIN" "$validation_user" \
    && nb_doctor_line PASS '仅转发生效策略有效' \
    || { nb_doctor_line FAIL '仅转发生效策略无效'; failed=1; }
  while IFS= read -r user_json; do
    ssh_tunnel_user_identity_valid "$user_json" \
      && nb_doctor_line PASS "用户身份有效: $(jq -r .display_name <<<"$user_json")" \
      || { nb_doctor_line FAIL "用户身份无效: $(jq -r .display_name <<<"$user_json")"; failed=1; }
    [ "$(stat -c '%a' "$(ssh_tunnel_key_dir "$(jq -r .account_id <<<"$user_json")")/id_ed25519" 2>/dev/null || true)" = 600 ] \
      && nb_doctor_line PASS "私钥权限有效: $(jq -r .display_name <<<"$user_json")" \
      || { nb_doctor_line FAIL "私钥权限无效: $(jq -r .display_name <<<"$user_json")"; failed=1; }
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  nb_doctor_line PASS 'external_listener=true managed_listener=false managed_firewall=false'
  nb_doctor_line INFO 'NOT_APPLICABLE_TO_SYSTEM_SSH：系统 sshd / 外部映射入口'
  return "$failed"
}

ssh_tunnel_rollback_empty_install() {
  local group_preexisting="${1:-1}"
  rm -f "$NOBRAND_SSH_STATE_FILE"
  find "$NOBRAND_SSH_KEYS_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
  find "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
  find "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" -mindepth 1 -maxdepth 1 -type f \
    ! -name '.group.json' -delete 2>/dev/null || true
  if [ "$group_preexisting" -eq 0 ]; then
    if ssh_tunnel_group_identity_valid; then
      ssh_tunnel_delete_group >/dev/null 2>&1 || return 1
    elif _has_group "$NOBRAND_SSH_GROUP"; then
      return 1
    fi
    rm -f "$NOBRAND_SSH_GROUP_MARKER"
  fi
  rmdir "$NOBRAND_SSH_KEYS_DIR" "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" \
    "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" "$NOBRAND_SSH_STATE_DIR" \
    "$NOBRAND_SSH_CONFIG_DIR" 2>/dev/null || true
}

ssh_tunnel_install() {
  local label mode host port real_port strategy managed_path users='[]' state_tmp="" account_id linux_user
  local group_preexisting=0 apply_rc=0
  require_root
  require_linux
  ssh_tunnel_watchdog_mutation_preflight || return $?
  nobrand_prepare_common
  nb_prepare_ingress_request || return 1
  command -v ssh-keygen >/dev/null 2>&1 || die 'SSH Tunnel 需要 OpenSSH ssh-keygen'
  ssh_tunnel_sshd_binary >/dev/null || die '未检测到现有 OpenSSH sshd'
  ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" || die '现有 sshd_config 无法通过 sshd -t'
  ssh_tunnel_state_exists && { t 'SSH Tunnel 已安装' 'SSH Tunnel is already installed'; return 0; }
  ssh_tunnel_state_absent || die 'SSH Tunnel 权威状态损坏或无法读取，拒绝覆盖'
  label="${SSH_TUNNEL_USER:-default}"
  ssh_tunnel_valid_label "$label" || die 'SSH Tunnel 用户标签无效'
  real_port="$(ssh_tunnel_detect_real_port)" || die '无法读取现有 sshd 生效端口'
  if [ -n "${ADVERTISE_HOST:-}" ]; then
    valid_advertise_host "$ADVERTISE_HOST" || die 'SSH Display Endpoint 主机无效'
    valid_advertise_port "$ADVERTISE_PORT" || die 'SSH Display Endpoint 端口无效'
    mode=custom host="$ADVERTISE_HOST" port="$(normalize_uint "$ADVERTISE_PORT")"
  else
    [ "${YES:-0}" -ne 1 ] || [ "${ADVERTISE_AUTO_REQUESTED:-0}" -eq 1 ] \
      || [ -n "$(nb_ingress_profile_display_host "$INGRESS_PROFILE_ID" 2>/dev/null || true)" ] \
      || die '非交互 SSH 安装必须明确指定 Display Endpoint、--advertise-auto，或选择带展示主机的入口配置'
    mode=auto host=""
    if [ -n "${ADVERTISE_PORT:-}" ]; then
      valid_advertise_port "$ADVERTISE_PORT" || die 'SSH Display Endpoint 端口无效'
      port="$(normalize_uint "$ADVERTISE_PORT")"
    else
      port="$(ssh_tunnel_default_display_port)" \
      || die '无法安全推导 SSH Display Endpoint 端口；请明确指定'
    fi
  fi
  _has_group "$NOBRAND_SSH_GROUP" && group_preexisting=1
  nb_lifecycle_mark_protocol_mutation_started ssh-tunnel || return 1
  ssh_tunnel_create_group || die '无法创建 SSH Tunnel 专用用户组'
  strategy="marker-block" managed_path="$NOBRAND_SSH_CONFIG_MAIN"
  ssh_tunnel_dropin_supported && { strategy=dropin; managed_path="$NOBRAND_SSH_CONFIG_DROPIN"; }
  state_tmp="$(mktemp_file .ssh-state)" || {
    ssh_tunnel_rollback_empty_install "$group_preexisting" || true
    return 1
  }
  ssh_tunnel_generate_state "$state_tmp" "$mode" "$host" "$port" "$real_port" \
    "$strategy" "$managed_path" "$users" "" "$INGRESS_PROFILE_ID" || {
      rm -f "$state_tmp"
      ssh_tunnel_rollback_empty_install "$group_preexisting" || true
      return 1
    }
  nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 || {
    rm -f "$state_tmp"
    ssh_tunnel_rollback_empty_install "$group_preexisting" || true
    return 1
  }
  rm -f "$state_tmp"
  account_id="$(ssh_tunnel_add_user_internal "$label")" || {
    ssh_tunnel_rollback_empty_install "$group_preexisting" || true
    return 1
  }
  linux_user="$(jq -r --arg account_id "$account_id" '.users[] | select(.account_id==$account_id) | .linux_user' \
    "$NOBRAND_SSH_STATE_FILE")"
  if ssh_tunnel_apply_policy "$linux_user"; then
    :
  else
    apply_rc=$?
    if [ "$apply_rc" -eq 75 ]; then
      warn 'SSH 策略事务的 watchdog 所有权未解决；已保留状态、账户与回滚证据'
      return 75
    fi
    if ! ssh_tunnel_delete_user_internal "$label" >/dev/null 2>&1; then
      warn 'SSH 策略应用失败，且账户回滚不完整；已保留状态以便安全重试'
      return 1
    fi
    ssh_tunnel_rollback_empty_install "$group_preexisting" \
      || warn 'SSH 安装回滚无法删除刚创建的空用户组'
    return "$apply_rc"
  fi
  nobrand_install_manager_script || true
  ssh_tunnel_show_user "$label"
}

ssh_tunnel_status() {
  local policy
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent \
      && { t 'SSH Tunnel 未安装' 'SSH Tunnel is not installed'; return 0; }
    die 'SSH Tunnel 权威状态损坏或无法读取'
  fi
  policy="$(ssh_tunnel_state_field policy_applied)"
  [ "$policy" = true ] && policy='已应用' || policy='未应用'
  printf 'SSH Tunnel\n  策略: %s\n  现有 sshd 实际端口: %s\n  展示端点 / Display Endpoint: %s:%s\n  用户数: %s\n' \
    "$policy" "$(ssh_tunnel_state_field real_port)" \
    "$(ssh_tunnel_effective_host)" "$(ssh_tunnel_state_field advertise_port)" \
    "$(jq '.users | length' "$NOBRAND_SSH_STATE_FILE")"
  printf '  入口配置 / Ingress Profile: %s\n' "$(nb_ingress_profile_name "$(ssh_tunnel_state_field ingress_profile_id 2>/dev/null || true)")"
  printf '  资源归属: external_listener=true managed_listener=false managed_firewall=false\n'
}

ssh_tunnel_user_list() {
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent && return 0
    return 1
  fi
  jq -r '.users[]? | [.display_name,.linux_user,.key_fingerprint] | @tsv' "$NOBRAND_SSH_STATE_FILE"
}

ssh_tunnel_watchdog_directory_empty_valid() {
  local entry=""
  if [ ! -e "$NOBRAND_SSH_WATCHDOG_DIR" ] && [ ! -L "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    return 0
  fi
  ssh_tunnel_watchdog_directory_preflight || return 1
  [ "$(stat -c '%a' "$NOBRAND_SSH_WATCHDOG_DIR")" = 700 ] || return 1
  entry="$(find "$NOBRAND_SSH_WATCHDOG_DIR" -mindepth 1 -maxdepth 1 -print -quit)" \
    || return 1
  [ -z "$entry" ]
}

ssh_tunnel_empty_directory_valid() {
  local path="$1" entry=""
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 0
  fi
  [ -d "$path" ] && [ ! -L "$path" ] || return 1
  entry="$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)" || return 1
  [ -z "$entry" ]
}

ssh_tunnel_uninstalled_layout_valid() {
  local state_root="$1" config_root="$2" entry=""
  if [ -e "$state_root" ] || [ -L "$state_root" ]; then
    [ -d "$state_root" ] && [ ! -L "$state_root" ] || return 1
    entry="$(find "$state_root" -mindepth 1 -maxdepth 1 \
      ! -path "${state_root}/keys" ! -path "${state_root}/watchdog" -print -quit)" \
      || return 1
    [ -z "$entry" ] \
      && ssh_tunnel_empty_directory_valid "${state_root}/keys" \
      && ssh_tunnel_empty_directory_valid "${state_root}/watchdog" || return 1
  fi
  if [ -e "$config_root" ] || [ -L "$config_root" ]; then
    [ -d "$config_root" ] && [ ! -L "$config_root" ] || return 1
    entry="$(find "$config_root" -mindepth 1 -maxdepth 1 \
      ! -path "${config_root}/authorized_keys" ! -path "${config_root}/accounts" -print -quit)" \
      || return 1
    [ -z "$entry" ] \
      && ssh_tunnel_empty_directory_valid "${config_root}/authorized_keys" \
      && ssh_tunnel_empty_directory_valid "${config_root}/accounts" || return 1
  fi
}

ssh_tunnel_backup_state_ready() {
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent || return 1
    _has_group "$NOBRAND_SSH_GROUP" && return 1
    ssh_tunnel_watchdog_directory_empty_valid || return 1
    ssh_tunnel_uninstalled_layout_valid "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_CONFIG_DIR"
    return $?
  fi
  ssh_tunnel_state_identity_valid || return 1
  [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)" = true ] \
    && ssh_tunnel_watchdog_directory_empty_valid
}

ssh_tunnel_restore_preflight() {
  local staged_state="$1" user_json linux_user expected_uid marker live_users staged_users path
  local staged_root staged_watchdog staged_config_root stage_base entry=""
  staged_root="$(dirname "$staged_state")"
  staged_watchdog="${staged_root}/watchdog"
  stage_base="$(dirname "$(dirname "$staged_root")")"
  staged_config_root="${stage_base}/config/ssh-tunnel"
  if [ ! -e "$staged_state" ] && [ ! -L "$staged_state" ]; then
    ssh_tunnel_uninstalled_layout_valid "$staged_root" "$staged_config_root" || return 1
    ssh_tunnel_state_absent || return 1
    _has_group "$NOBRAND_SSH_GROUP" && return 1
    return 0
  fi
  ssh_tunnel_state_identity_file_valid "$staged_state" || return 1
  if [ -e "$staged_watchdog" ] || [ -L "$staged_watchdog" ]; then
    [ -d "$staged_watchdog" ] && [ ! -L "$staged_watchdog" ] || return 1
    entry="$(find "$staged_watchdog" -mindepth 1 -maxdepth 1 -print -quit)" || return 1
    [ -z "$entry" ] || return 1
  fi
  [ "$(jq -r '.pending_operation // ""' "$staged_state")" = '' ] \
    && [ "$(jq -r '.pending_watchdog_token // ""' "$staged_state")" = '' ] \
    && [ "$(jq -r '.pending_watchdog_pid // ""' "$staged_state")" = '' ] \
    && [ "$(jq -r '.pending_origin_connection // ""' "$staged_state")" = '' ] \
    && [ "$(jq -r .policy_applied "$staged_state")" = true ] || return 1
  if ! ssh_tunnel_state_absent; then
    ssh_tunnel_state_exists && ssh_tunnel_state_identity_valid || return 1
    live_users="$(jq -c '[.users[] | {account_id,linux_user,uid,group}] | sort_by(.account_id)' \
      "$NOBRAND_SSH_STATE_FILE")" || return 1
    staged_users="$(jq -c '[.users[] | {account_id,linux_user,uid,group}] | sort_by(.account_id)' \
      "$staged_state")" || return 1
    [ "$live_users" = "$staged_users" ] || return 1
  fi
  if _has_group "$NOBRAND_SSH_GROUP"; then
    ssh_tunnel_group_identity_valid || return 1
  fi
  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    expected_uid="$(jq -r .uid <<<"$user_json")"
    if _has_user "$linux_user"; then
      ssh_tunnel_linux_user_identity_valid "$user_json" || return 1
      # A backup is not proof that an already-existing local identity belongs
      # to NoBrand. Require the current, pre-restore ownership marker.
      marker="$(ssh_tunnel_account_marker_file "$linux_user")"
      for path in "$NOBRAND_SSH_CONFIG_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR"; do
        [ -d "$path" ] && [ ! -L "$path" ] && secure_stat_path "$path" dir \
          || return 1
      done
      [ -f "$marker" ] && [ ! -L "$marker" ] \
        && secure_stat_path "$marker" file \
        && [ "$(stat -c '%a' "$marker")" = 600 ] || return 1
      jq -e --arg account_id "$(jq -r .account_id <<<"$user_json")" \
        --arg linux_user "$linux_user" --arg uid "$expected_uid" '
        .ownership=="nobrand-v3" and .account_id==$account_id
        and .linux_user==$linux_user and .uid==($uid|tonumber)
      ' "$marker" >/dev/null || return 1
    elif getent passwd "$expected_uid" >/dev/null 2>&1; then
      return 1
    fi
  done < <(jq -c '.users[]?' "$staged_state")
}

ssh_tunnel_reconcile_restored_listener_state() {
  local current_port state_tmp=""
  current_port="$(ssh_tunnel_detect_real_port)" || return 1
  valid_advertise_port "$current_port" || return 1
  current_port="$(normalize_uint "$current_port")"
  # advertise_port may be an explicit external mapping even in auto-host mode.
  # The current schema has no provenance bit, so preserve it exactly.
  if [ "$(ssh_tunnel_state_field real_port)" = "$current_port" ]; then
    return 0
  fi
  state_tmp="$(mktemp_file .ssh-listener-state)" || return 1
  if ! jq --arg real_port "$current_port" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      .real_port=($real_port|tonumber)
      | .updated_at=$updated
    ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
    || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600; then
    rm -f "$state_tmp"
    return 1
  fi
  rm -f "$state_tmp"
}

# A backup does not contain the destination host's external sshd configuration.
# Persist a truthful pre-apply state before the watchdog snapshots it, so a
# timeout restores a recoverable partial SSH module instead of claiming that a
# policy missing from the destination is already active.
ssh_tunnel_prepare_restored_policy_state() {
  local state_tmp=""
  ssh_tunnel_watchdog_mutation_preflight || return $?
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent && return 0
    return 1
  fi
  ssh_tunnel_state_identity_valid || return 1
  [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)" = '' ] \
    || return 1
  state_tmp="$(mktemp_file .ssh-restore-preapply)" || return 1
  if ! jq --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      .policy_applied=false
      | .pending_operation=""
      | .pending_watchdog_token=""
      | .pending_watchdog_pid=""
      | .pending_origin_connection=""
      | .updated_at=$updated
    ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
     || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600; then
    rm -f "$state_tmp"
    return 1
  fi
  rm -f "$state_tmp"
  ssh_tunnel_state_identity_valid
}

ssh_tunnel_snapshot_external_state() {
  local snapshot="$1" label path
  mkdir -p "$snapshot" || return 1
  for label in main dropin; do
    case "$label" in
      main) path="$NOBRAND_SSH_CONFIG_MAIN" ;;
      dropin) path="$NOBRAND_SSH_CONFIG_DROPIN" ;;
    esac
    if [ -e "$path" ] || [ -L "$path" ]; then
      [ -f "$path" ] || [ -L "$path" ] || return 1
      cp -a "$path" "$snapshot/$label" || return 1
    else
      : >"$snapshot/${label}.absent" || return 1
    fi
  done
  : >"$snapshot/created.log"
}

ssh_tunnel_log_created_restore_identity() {
  local log="${1:-}" kind="$2" name="$3" numeric_id="$4" account_id="${5:-}"
  [ -n "$log" ] || return 0
  printf '%s|%s|%s|%s\n' "$kind" "$name" "$numeric_id" "$account_id" >>"$log"
}

ssh_tunnel_cancel_pending_watchdog() {
  local token pid
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent && return 0
    return 1
  fi
  token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
  pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
  [ -n "$token" ] || return 0
  ssh_tunnel_watchdog_cancel "$token" "$pid"
}

ssh_tunnel_restore_external_snapshot() {
  local snapshot="$1" log="${2:-$1/created.log}" kind name numeric_id account_id
  local passwd_line actual_uid actual_gid gecos group_gid label path failed=0
  if [ -s "$log" ]; then
    while IFS='|' read -r kind name numeric_id account_id; do
      [ "$kind" = USER ] || continue
      passwd_line="$(getent passwd "$name" 2>/dev/null || true)"
      [ -n "$passwd_line" ] || continue
      IFS=: read -r _ _ actual_uid actual_gid gecos _ _ <<<"$passwd_line"
      group_gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
      if [ "$actual_uid" = "$numeric_id" ] && [ "$actual_gid" = "$group_gid" ] \
         && [ "$gecos" = "NoBrand SSH Tunnel ${account_id}" ]; then
        pkill -KILL -u "$actual_uid" 2>/dev/null || true
        ssh_tunnel_delete_linux_user "$name" || failed=1
      else
        warn "SSH 恢复回滚因身份不匹配而拒绝删除用户: $name"
        failed=1
      fi
    done < <(awk -F'|' '$1=="USER" {line[NR]=$0} END {for (i=NR;i>=1;i--) if (line[i] != "") print line[i]}' "$log")
    while IFS='|' read -r kind name numeric_id _; do
      [ "$kind" = GROUP ] || continue
      if _has_group "$name"; then
        [ "$(getent group "$name" | awk -F: '{print $3}')" = "$numeric_id" ] || {
          warn "SSH 恢复回滚因身份不匹配而拒绝删除用户组: $name"
          failed=1
          continue
        }
        if command -v groupdel >/dev/null 2>&1; then
          groupdel "$name" || failed=1
        elif command -v delgroup >/dev/null 2>&1; then
          delgroup "$name" || failed=1
        else
          failed=1
        fi
      fi
    done <"$log"
  fi
  for label in main dropin; do
    case "$label" in
      main) path="$NOBRAND_SSH_CONFIG_MAIN" ;;
      dropin) path="$NOBRAND_SSH_CONFIG_DROPIN" ;;
    esac
    if [ -e "$snapshot/$label" ] || [ -L "$snapshot/$label" ]; then
      [ -f "$snapshot/$label" ] || [ -L "$snapshot/$label" ] \
        || { failed=1; continue; }
      mkdir -p "$(dirname "$path")" || { failed=1; continue; }
      rm -f -- "$path" || { failed=1; continue; }
      cp -a -- "$snapshot/$label" "$path" || failed=1
    elif [ -f "$snapshot/${label}.absent" ] \
         && [ ! -L "$snapshot/${label}.absent" ]; then
      rm -f "$path" || failed=1
    else
      failed=1
    fi
  done
  if [ -e "$NOBRAND_SSH_CONFIG_MAIN" ] || [ -L "$NOBRAND_SSH_CONFIG_MAIN" ]; then
    ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" && ssh_tunnel_reload || failed=1
  fi
  [ "$failed" -eq 0 ]
}

ssh_tunnel_restore_system_state() {
  local transaction_log="${1:-}" user_json linux_user account_id expected_uid nologin_shell
  local validation_user group_preexisting=0 group_marker_preexisting=0 expected_group_gid=""
  local group_gid group_created=0 group_create_rc=0 created_user=0 user_create_rc=0 surviving_users=0
  ssh_tunnel_watchdog_mutation_preflight || return $?
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent && return 0
    return 1
  fi
  ssh_tunnel_state_identity_valid || return 1
  [ "$(jq '.users | length' "$NOBRAND_SSH_STATE_FILE")" -gt 0 ] || return 1
  ssh_tunnel_restore_paths_preflight || return 1
  nologin_shell="$(ssh_tunnel_nologin_shell)" || return 1

  _has_group "$NOBRAND_SSH_GROUP" && group_preexisting=1
  if [ -e "$NOBRAND_SSH_GROUP_MARKER" ] || [ -L "$NOBRAND_SSH_GROUP_MARKER" ]; then
    group_marker_preexisting=1
  fi
  ssh_tunnel_group_marker_preflight || return 1
  # Complete the read-only preflight before creating a group, user, marker, or
  # authorized-key file. An occupied historical UID or a replacement account
  # must never be adopted merely because current state still exists.
  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    expected_uid="$(jq -r .uid <<<"$user_json")"
    ssh_tunnel_user_key_material_valid "$user_json" || return 1
    ssh_tunnel_user_file_destinations_valid "$user_json" || return 1
    if _has_user "$linux_user"; then
      [ "$group_preexisting" -eq 1 ] || return 1
      ssh_tunnel_linux_user_identity_valid "$user_json" || return 1
      surviving_users=$((surviving_users + 1))
    elif getent passwd "$expected_uid" >/dev/null 2>&1; then
      return 1
    fi
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")

  # A surviving group without its ownership marker can be rebound only when a
  # surviving state-listed account proves the exact group GID relationship.
  # With no such account there is no way to distinguish a replacement group.
  if [ "$group_preexisting" -eq 1 ] \
     && [ ! -e "$NOBRAND_SSH_GROUP_MARKER" ] && [ ! -L "$NOBRAND_SSH_GROUP_MARKER" ] \
     && [ "$surviving_users" -eq 0 ]; then
    return 1
  fi

  ssh_tunnel_ensure_restore_directories || return 1
  if [ "$group_preexisting" -eq 0 ]; then
    group_create_rc=0
    group_created=0
    if [ "$group_marker_preexisting" -eq 1 ]; then
      expected_group_gid="$(jq -r .gid "$NOBRAND_SSH_GROUP_MARKER")"
      ssh_tunnel_create_group_with_gid "$expected_group_gid" group_created \
        || group_create_rc=$?
    else
      ssh_tunnel_create_group group_created || group_create_rc=$?
    fi
    group_gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
    if ! [[ "$group_gid" =~ ^[0-9]+$ ]] && [ -f "$NOBRAND_SSH_GROUP_MARKER" ]; then
      group_gid="$(jq -r '.gid // empty' "$NOBRAND_SSH_GROUP_MARKER" 2>/dev/null || true)"
    fi
    [[ "$group_gid" =~ ^[0-9]+$ ]] || return 1
    if [ "$group_create_rc" -eq 0 ] && [ "$group_created" -eq 0 ]; then
      # Compatibility with restore adapters that predate the result parameter:
      # a successful create call for a name proven absent at preflight is ours.
      group_created=1
    fi
    if [ "$group_created" -eq 1 ]; then
      if ! ssh_tunnel_log_created_restore_identity "$transaction_log" GROUP \
        "$NOBRAND_SSH_GROUP" "$group_gid"; then
        if ssh_tunnel_group_identity_valid \
           && ssh_tunnel_delete_group >/dev/null 2>&1; then
          [ "$group_marker_preexisting" -eq 1 ] || rm -f "$NOBRAND_SSH_GROUP_MARKER"
        fi
        return 1
      fi
    fi
    [ "$group_create_rc" -eq 0 ] || return "$group_create_rc"
  fi
  ssh_tunnel_reconcile_group_marker || return 1

  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    account_id="$(jq -r .account_id <<<"$user_json")"
    expected_uid="$(jq -r .uid <<<"$user_json")"
    created_user=0
    if _has_user "$linux_user"; then
      ssh_tunnel_linux_user_identity_valid "$user_json" || return 1
    else
      getent passwd "$expected_uid" >/dev/null 2>&1 && return 1
      user_create_rc=0
      ssh_tunnel_create_linux_user_with_uid \
        "$linux_user" "$account_id" "$nologin_shell" "$expected_uid" created_user \
        || user_create_rc=$?
      if [ "$user_create_rc" -eq 0 ] && [ "$created_user" -eq 0 ]; then
        # Compatibility with older restore adapters that return success without
        # accepting the optional result parameter.
        created_user=1
      fi
      if [ "$created_user" -eq 1 ]; then
        if ! ssh_tunnel_log_created_restore_identity "$transaction_log" USER \
          "$linux_user" "$expected_uid" "$account_id"; then
          ssh_tunnel_linux_user_identity_valid "$user_json" \
            && ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
          return 1
        fi
      fi
      [ "$user_create_rc" -eq 0 ] || return "$user_create_rc"
    fi
    ssh_tunnel_linux_user_identity_valid "$user_json" || return 1
    ssh_tunnel_reconcile_user_files "$user_json" "$nologin_shell" || return 1
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  validation_user="$(jq -r '.users[0].linux_user // empty' "$NOBRAND_SSH_STATE_FILE")"
  [ -n "$validation_user" ] || return 1
  ssh_tunnel_reconcile_restored_listener_state || return 1
  ssh_tunnel_apply_policy "$validation_user" restore
}

ssh_tunnel_uninstall_checkpoint() {
  local phase="$1"
  declare -F nb_test_mode_enabled >/dev/null 2>&1 && nb_test_mode_enabled || return 0
  [ "${NOBRAND_TEST_INTERRUPT_SSH_UNINSTALL_AT:-}" != "$phase" ] || return 75
}

ssh_tunnel_uninstall_roots_valid() {
  local safe_state safe_config active=""
  [ "$(dirname "$NOBRAND_SSH_STATE_FILE")" = "$NOBRAND_SSH_STATE_DIR" ] || return 1
  [ "$NOBRAND_SSH_KEYS_DIR" = "${NOBRAND_SSH_STATE_DIR}/keys" ] || return 1
  [ "$NOBRAND_SSH_WATCHDOG_DIR" = "${NOBRAND_SSH_STATE_DIR}/watchdog" ] || return 1
  [ "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" = "${NOBRAND_SSH_CONFIG_DIR}/authorized_keys" ] || return 1
  [ "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" = "${NOBRAND_SSH_CONFIG_DIR}/accounts" ] || return 1
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_SSH_STATE_DIR" NOBRAND_SSH_STATE_DIR)" \
    || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_SSH_CONFIG_DIR" NOBRAND_SSH_CONFIG_DIR)" \
    || return 1
  [ "$safe_state" != "$safe_config" ] || return 1
  case "$safe_state" in "$safe_config"/*) return 1 ;; esac
  case "$safe_config" in "$safe_state"/*) return 1 ;; esac
  [ -d "$safe_state" ] && [ ! -L "$safe_state" ] || return 1
  [ -f "$NOBRAND_SSH_STATE_FILE" ] && [ ! -L "$NOBRAND_SSH_STATE_FILE" ] || return 1
  if [ -e "$safe_config" ] || [ -L "$safe_config" ]; then
    [ -d "$safe_config" ] && [ ! -L "$safe_config" ] || return 1
  fi
  if [ -e "$NOBRAND_SSH_WATCHDOG_DIR" ] || [ -L "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    [ -d "$NOBRAND_SSH_WATCHDOG_DIR" ] && [ ! -L "$NOBRAND_SSH_WATCHDOG_DIR" ] || return 1
    active="$(find "$NOBRAND_SSH_WATCHDOG_DIR" -mindepth 1 -maxdepth 1 \
      \( -name '*.armed' -o -name '*.running' \) -print -quit)" || return 1
    [ -z "$active" ] || return 1
  fi
}

ssh_tunnel_finalization_state_valid() {
  local expected_operation="${1:-}" pending token pid origin policy
  ssh_tunnel_state_identity_valid || return 1
  pending="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
  token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
  pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
  origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
  policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
  [ "$policy" = false ] && [ -z "$token" ] && [ -z "$pid" ] && [ -z "$origin" ] || return 1
  case "$pending" in ''|uninstall|unified-uninstall) ;; *) return 1 ;; esac
  if [ -n "$expected_operation" ] && [ -n "$pending" ]; then
    [ "$expected_operation" = "$pending" ] || return 1
  fi
  ssh_tunnel_policy_absent || return 1
  ssh_tunnel_uninstall_roots_valid
}

ssh_tunnel_finalization_identities_valid() {
  local user_json linux_user present_users=0
  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    if _has_user "$linux_user"; then
      present_users=$((present_users + 1))
      ssh_tunnel_user_identity_valid "$user_json" || return 1
    fi
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  if _has_group "$NOBRAND_SSH_GROUP"; then
    ssh_tunnel_group_identity_valid || return 1
  else
    [ "$present_users" -eq 0 ] || return 1
  fi
}

ssh_tunnel_clear_managed_directory() {
  local root="$1"
  if [ ! -e "$root" ] && [ ! -L "$root" ]; then
    return 0
  fi
  [ -d "$root" ] && [ ! -L "$root" ] || return 1
  find "$root" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || return 1
  rmdir "$root" 2>/dev/null || [ ! -e "$root" ]
}

ssh_tunnel_clear_state_payload() {
  local remaining=""
  find "$NOBRAND_SSH_STATE_DIR" -mindepth 1 -maxdepth 1 \
    ! -path "$NOBRAND_SSH_STATE_FILE" -exec rm -rf -- {} + || return 1
  remaining="$(find "$NOBRAND_SSH_STATE_DIR" -mindepth 1 -maxdepth 1 \
    ! -path "$NOBRAND_SSH_STATE_FILE" -print -quit)" || return 1
  [ -z "$remaining" ]
}

ssh_tunnel_finalize_uninstall() {
  local expected_operation="${1:-}" user_json linux_user uid deleted_count=0 checkpoint_rc=0
  local state_snapshot=""
  ssh_tunnel_watchdog_mutation_preflight || return $?
  ssh_tunnel_finalization_state_valid "$expected_operation" \
    || die 'SSH Tunnel 卸载状态、受管策略或路径不一致，拒绝删除'
  # Validate every still-present identity before the first mutation. Missing
  # state-listed identities are already removed; an unrelated user reusing an
  # old UID is deliberately ignored.
  ssh_tunnel_finalization_identities_valid \
    || die 'SSH Tunnel 用户或用户组身份不匹配，拒绝删除'
  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    _has_user "$linux_user" || continue
    # Revalidate immediately before signalling or deleting the account so a
    # replaced same-name identity is never acted upon.
    ssh_tunnel_user_identity_valid "$user_json" \
      || die 'SSH Tunnel 用户身份在卸载期间发生变化，拒绝继续'
    uid="$(jq -r .uid <<<"$user_json")"
    pkill -KILL -u "$uid" 2>/dev/null || true
    ssh_tunnel_delete_linux_user "$linux_user" || return 1
    deleted_count=$((deleted_count + 1))
    if [ "$deleted_count" -eq 1 ]; then
      ssh_tunnel_uninstall_checkpoint after-first-user-deletion || checkpoint_rc=$?
      [ "$checkpoint_rc" -eq 0 ] || return "$checkpoint_rc"
    fi
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  if _has_group "$NOBRAND_SSH_GROUP"; then
    ssh_tunnel_group_identity_valid \
      || die 'SSH Tunnel 用户组身份在卸载期间发生变化，拒绝继续'
    ssh_tunnel_delete_group || return 1
    ssh_tunnel_uninstall_checkpoint after-group-deletion || checkpoint_rc=$?
    [ "$checkpoint_rc" -eq 0 ] || return "$checkpoint_rc"
  fi
  # Account markers and authorized keys remain as ownership proof until all
  # identities are gone. Then remove config first and authoritative state last.
  ssh_tunnel_clear_managed_directory "$NOBRAND_SSH_CONFIG_DIR" || return 1
  ssh_tunnel_clear_state_payload || return 1
  ssh_tunnel_uninstall_checkpoint before-state-removal || checkpoint_rc=$?
  [ "$checkpoint_rc" -eq 0 ] || return "$checkpoint_rc"
  state_snapshot="$(mktemp_file .ssh-final-state)" || return 1
  cp -a "$NOBRAND_SSH_STATE_FILE" "$state_snapshot" || {
    rm -f "$state_snapshot"
    return 1
  }
  if ! rm -f "$NOBRAND_SSH_STATE_FILE"; then
    rm -f "$state_snapshot"
    return 1
  fi
  if ! rmdir "$NOBRAND_SSH_STATE_DIR" 2>/dev/null; then
    if [ -e "$NOBRAND_SSH_STATE_DIR" ]; then
      nb_atomic_install_file "$state_snapshot" "$NOBRAND_SSH_STATE_FILE" 0600 \
        || warn 'SSH Tunnel 状态根目录清理失败，且权威状态文件恢复失败'
      rm -f "$state_snapshot"
      return 1
    fi
  fi
  rm -f "$state_snapshot"
  t '已删除 NoBrand SSH Tunnel；系统 sshd、端口、防火墙、主机密钥与管理员访问均保留' \
    'Removed NoBrand SSH Tunnel; system sshd/port/firewall/host keys/admin access are preserved'
}

ssh_tunnel_uninstall() {
  local operation="${1:-uninstall}" pending token pid origin policy user_json
  require_root
  case "$operation" in uninstall|unified-uninstall) ;; *) die 'SSH Tunnel 卸载操作无效' ;; esac
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent \
      && { t 'SSH Tunnel 未安装' 'SSH Tunnel is not installed'; return 0; }
    die 'SSH Tunnel 权威状态损坏或无法读取，拒绝卸载'
  fi
  ssh_tunnel_state_identity_valid || die 'SSH Tunnel 状态无效，拒绝卸载'
  pending="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
  token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
  pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
  origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
  policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
  if [ "$pending" = uninstall ] || [ "$pending" = unified-uninstall ]; then
    [ "$pending" = "$operation" ] || die 'SSH Tunnel 卸载必须由原始生命周期操作继续'
    if [ -n "$token" ]; then
      ssh_tunnel_pending_tuple_valid "$pending" "$token" "$pid" "$origin" "$policy" \
        || die 'SSH Tunnel 待确认卸载状态不一致'
      if [ "$token" = disabled ]; then
        ssh_tunnel_confirm_admin disabled
      else
        ssh_tunnel_watchdog_prompt "$token"
      fi
      return $?
    fi
    [ "$policy" = false ] && [ -z "$pid" ] && [ -z "$origin" ] \
      || die 'SSH Tunnel 已确认卸载状态不一致'
    ssh_tunnel_finalize_uninstall "$operation"
    return $?
  fi
  [ -z "$pending" ] || die "SSH 策略仍有待确认操作: $pending"
  [ -z "$token" ] && [ -z "$pid" ] && [ -z "$origin" ] \
    || die 'SSH Tunnel watchdog 状态不一致，拒绝卸载'
  if [ "$policy" = false ]; then
    # Compatibility recovery for a post-confirm state written by an older
    # candidate before it durably retained pending_operation.
    ssh_tunnel_finalize_uninstall "$operation"
    return $?
  fi
  [ "$policy" = true ] || die 'SSH Tunnel 策略状态无效，拒绝卸载'
  while IFS= read -r user_json; do
    ssh_tunnel_user_identity_valid "$user_json" \
      || die 'SSH Tunnel 用户身份不匹配，拒绝卸载'
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  ssh_tunnel_group_identity_valid || die 'SSH Tunnel 用户组身份不匹配，拒绝卸载'
  ssh_tunnel_remove_policy "$operation"
}

nobrand_run_ssh_tunnel_action() {
  case "${SSH_TUNNEL_ACTION:-menu}" in
    install)
      if [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -eq 1 ]; then
        nb_lifecycle_run_protocol_install ssh-tunnel ssh_tunnel_install
      else
        ssh_tunnel_install
      fi
      ;;
    status) ssh_tunnel_status ;;
    doctor) ssh_tunnel_doctor ;;
    show) ssh_tunnel_show_user "${SSH_TUNNEL_USER:-}" ;;
    export) ssh_tunnel_export_user "${SSH_TUNNEL_USER:-}" ;;
    set-endpoint) ssh_tunnel_set_endpoint_state "${ADVERTISE_HOST:-}" "${ADVERTISE_PORT:-}" ;;
    confirm-admin) ssh_tunnel_confirm_admin "$SSH_TUNNEL_WATCHDOG_TOKEN" ;;
    user-list) ssh_tunnel_user_list ;;
    user-add) ssh_tunnel_add_user_internal "$SSH_TUNNEL_USER" >/dev/null ;;
    user-show) ssh_tunnel_show_user "$SSH_TUNNEL_USER" ;;
    user-export) ssh_tunnel_export_user "$SSH_TUNNEL_USER" ;;
    user-rotate-key) ssh_tunnel_rotate_user_key "$SSH_TUNNEL_USER" ;;
    user-delete) ssh_tunnel_delete_user_internal "$SSH_TUNNEL_USER" ;;
    uninstall) ssh_tunnel_uninstall ;;
    menu) ssh_tunnel_status ;;
    help)
      cat <<'EOF'
nobrand ssh install|status|doctor|show|export|set-endpoint|uninstall
nobrand ssh user add|delete|list|show|rotate-key
SSH Tunnel 复用现有 OpenSSH sshd，仅允许 -L/-D/-R TCP 转发。
EOF
      ;;
    *) die "未知 SSH Tunnel 操作: ${SSH_TUNNEL_ACTION}" ;;
  esac
}
