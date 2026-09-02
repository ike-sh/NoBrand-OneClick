# ---------- SSH Tunnel: existing-OpenSSH policy and dedicated identities ----------

ssh_tunnel_state_exists() {
  [ -s "$NOBRAND_SSH_STATE_FILE" ] && jq empty "$NOBRAND_SSH_STATE_FILE" >/dev/null 2>&1
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
      warn "SSH Tunnel effective policy mismatch: ${key}=${value:-missing}, expected ${expected}"
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

ssh_tunnel_key_fingerprint() {
  local public_key="$1"
  ssh-keygen -lf "$public_key" -E sha256 2>/dev/null | awk '{print $2}'
}

ssh_tunnel_authorized_key_line() {
  local public_key="$1" nologin_shell="$2" key_material
  key_material="$(awk '{print $1" "$2}' "$public_key")" || return 1
  printf 'command="%s",no-agent-forwarding,no-X11-forwarding,no-pty %s\n' \
    "$nologin_shell" "$key_material"
}

ssh_tunnel_create_group() {
  local gid marker_tmp="" created_group=0
  if _has_group "$NOBRAND_SSH_GROUP"; then
    gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
    jq -e --arg group "$NOBRAND_SSH_GROUP" --arg gid "$gid" '
      .ownership=="nobrand-v3" and .group==$group and .gid==($gid|tonumber)
    ' "$NOBRAND_SSH_GROUP_MARKER" >/dev/null 2>&1
    return $?
  fi
  if command -v groupadd >/dev/null 2>&1; then
    groupadd --system "$NOBRAND_SSH_GROUP" || return 1
  elif command -v addgroup >/dev/null 2>&1; then
    addgroup -S "$NOBRAND_SSH_GROUP" || return 1
  else
    return 1
  fi
  created_group=1
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
    [ "$created_group" -eq 0 ] || ssh_tunnel_delete_group >/dev/null 2>&1 || true
    return 1
  fi
  rm -f "$marker_tmp"
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

ssh_tunnel_create_group_with_gid() {
  local expected_gid="$1" actual_gid
  [[ "$expected_gid" =~ ^[0-9]+$ ]] || return 1
  ! _has_group "$NOBRAND_SSH_GROUP" || return 1
  getent group "$expected_gid" >/dev/null 2>&1 && return 1
  if command -v groupadd >/dev/null 2>&1; then
    groupadd --system --gid "$expected_gid" "$NOBRAND_SSH_GROUP" || return 1
  elif command -v addgroup >/dev/null 2>&1; then
    addgroup -S -g "$expected_gid" "$NOBRAND_SSH_GROUP" || return 1
  else
    return 1
  fi
  actual_gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
  [ "$actual_gid" = "$expected_gid" ]
}

ssh_tunnel_group_identity_valid() {
  local gid
  _has_group "$NOBRAND_SSH_GROUP" || return 1
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

ssh_tunnel_create_linux_user_with_uid() {
  local linux_user="$1" account_id="$2" nologin_shell="$3" expected_uid="$4"
  ! _has_user "$linux_user" || return 1
  getent passwd "$expected_uid" >/dev/null 2>&1 && return 1
  if command -v useradd >/dev/null 2>&1; then
    useradd --system --uid "$expected_uid" --gid "$NOBRAND_SSH_GROUP" --no-create-home \
      --home-dir /nonexistent --shell "$nologin_shell" \
      --comment "NoBrand SSH Tunnel ${account_id}" "$linux_user" || return 1
  elif command -v adduser >/dev/null 2>&1; then
    adduser -S -D -H -u "$expected_uid" -G "$NOBRAND_SSH_GROUP" -h /nonexistent \
      -s "$nologin_shell" -g "NoBrand SSH Tunnel ${account_id}" "$linux_user" || return 1
  else
    return 1
  fi
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

ssh_tunnel_user_identity_valid() {
  local user_json="$1" linux_user expected_uid expected_group account_id expected_fp
  local passwd_line actual_uid actual_gid group_gid gecos shell marker auth_file actual_fp
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  expected_uid="$(jq -r .uid <<<"$user_json")"
  expected_group="$(jq -r .group <<<"$user_json")"
  account_id="$(jq -r .account_id <<<"$user_json")"
  expected_fp="$(jq -r .key_fingerprint <<<"$user_json")"
  passwd_line="$(getent passwd "$linux_user" 2>/dev/null || true)"
  [ -n "$passwd_line" ] || return 1
  IFS=: read -r _ _ actual_uid actual_gid gecos _ shell <<<"$passwd_line"
  group_gid="$(getent group "$expected_group" 2>/dev/null | awk -F: '{print $3}')"
  [ "$actual_uid" = "$expected_uid" ] && [ "$actual_gid" = "$group_gid" ] || return 1
  [ "$gecos" = "NoBrand SSH Tunnel ${account_id}" ] || return 1
  case "$shell" in /usr/sbin/nologin|/sbin/nologin|/bin/false) ;; *) return 1 ;; esac
  marker="$(ssh_tunnel_account_marker_file "$linux_user")"
  jq -e --arg account_id "$account_id" --arg linux_user "$linux_user" --arg uid "$expected_uid" \
    '.ownership=="nobrand-v3" and .account_id==$account_id and .linux_user==$linux_user and .uid==($uid|tonumber)' \
    "$marker" >/dev/null 2>&1 || return 1
  auth_file="$(ssh_tunnel_authorized_key_file "$linux_user")"
  [ -s "$auth_file" ] || return 1
  actual_fp="$(ssh-keygen -lf "$auth_file" -E sha256 2>/dev/null | awk '{print $2}')"
  [ "$actual_fp" = "$expected_fp" ]
}

ssh_tunnel_add_user_internal() {
  local label="$1" account_id linux_user nologin_shell key_dir private_key public_key
  local fingerprint uid user_json state_tmp marker_tmp auth_tmp created_user=0
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
  user_json="$(ssh_tunnel_resolve_user_json "$selector")" || die '找不到唯一 SSH Tunnel 用户'
  ssh_tunnel_user_identity_valid "$user_json" || die 'SSH Tunnel 用户 identity 不匹配，拒绝轮换'
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
  user_json="$(ssh_tunnel_resolve_user_json "$selector")" || die '找不到唯一 SSH Tunnel 用户'
  ssh_tunnel_user_identity_valid "$user_json" || die 'SSH Tunnel 用户 identity 不匹配，拒绝删除'
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
      warn 'SSH Tunnel state 提交失败；Linux 用户与 authorized key 已回滚'
    else
      warn 'SSH Tunnel state 提交失败且 Linux 用户回滚失败；authorized key 保持撤销，marker/key 保留供恢复'
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
  ssh_tunnel_strip_marker_block "$NOBRAND_SSH_CONFIG_MAIN" "$stripped" || return 1
  {
    cat "$stripped"
    printf '\n%s\n' "$NOBRAND_SSH_BLOCK_BEGIN"
    cat "$policy"
    printf '%s\n' "$NOBRAND_SSH_BLOCK_END"
  } >"$output"
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

ssh_tunnel_watchdog_begin() {
  local target="$1" operation="$2" token origin service kind name backup script token_file timeout pid
  local state_backup state_absent
  [ "${NOBRAND_SSH_WATCHDOG_DISABLED:-0}" != 1 ] \
    || { printf 'disabled|||%s' "$operation"; return 0; }
  mkdir -p "$NOBRAND_SSH_WATCHDOG_DIR" || return 1
  chmod 0700 "$NOBRAND_SSH_WATCHDOG_DIR" || return 1
  token="$(openssl rand -hex 16 2>/dev/null || printf '%08x%08x' "$RANDOM" "$RANDOM")"
  origin="${SSH_CONNECTION:-}"
  backup="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.backup"
  state_backup="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.state.backup"
  state_absent="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.state.absent"
  script="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.rollback.sh"
  token_file="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.armed"
  if [ -e "$target" ]; then cp -a "$target" "$backup"; else : >"${backup}.absent"; fi
  if [ -e "$NOBRAND_SSH_STATE_FILE" ]; then
    cp -a "$NOBRAND_SSH_STATE_FILE" "$state_backup"
  else
    : >"$state_absent"
  fi
  service="$(ssh_tunnel_detect_service)" || return 1
  kind="${service%%|*}"
  name="${service#*|}"
  timeout="${NOBRAND_SSH_WATCHDOG_TIMEOUT:-180}"
  [[ "$timeout" =~ ^[0-9]+$ ]] && [ "$timeout" -ge 30 ] || timeout=180
  : >"$token_file"
  {
    printf '#!/usr/bin/env bash\nset -u\n[ "${NOBRAND_SSH_WATCHDOG_NOW:-0}" = 1 ] || sleep %q\n' "$timeout"
    printf '[ -f %q ] || exit 0\n' "$token_file"
    printf 'if [ -f %q ]; then cp -a %q %q; else rm -f %q; fi\n' \
      "$backup" "$backup" "$target" "$target"
    printf '%q -t -f %q || exit 1\n' "$(ssh_tunnel_sshd_binary)" "$NOBRAND_SSH_CONFIG_MAIN"
    case "$kind" in
      systemd) printf 'systemctl reload %q\n' "$name" ;;
      openrc) printf 'rc-service %q reload\n' "$name" ;;
      sighup) printf 'kill -HUP %q\n' "$name" ;;
    esac
    printf 'if [ -f %q ]; then cp -a %q %q; else rm -f %q; fi\n' \
      "$state_backup" "$state_backup" "$NOBRAND_SSH_STATE_FILE" "$NOBRAND_SSH_STATE_FILE"
    printf 'rm -f %q %q %q %q %q %q %q\n' "$token_file" "$backup" "${backup}.absent" \
      "$state_backup" "$state_absent" "$script" "${script}.running"
  } >"$script"
  chmod 0700 "$script"
  nohup "$script" >/dev/null 2>&1 &
  pid=$!
  printf '%s|%s|%s|%s' "$token" "$pid" "$origin" "$operation"
}

ssh_tunnel_watchdog_cancel() {
  local token="$1" pid="${2:-}" base
  [ "$token" != disabled ] || return 0
  base="${NOBRAND_SSH_WATCHDOG_DIR}/${token}"
  rm -f "${base}.armed"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null || true
  rm -f "${base}.backup" "${base}.backup.absent" "${base}.state.backup" \
    "${base}.state.absent" "${base}.rollback.sh" "${base}.rollback.sh.running"
}

ssh_tunnel_watchdog_rollback_now() {
  local token="$1" pid="${2:-}" base script
  [ "$token" != disabled ] || return 0
  base="${NOBRAND_SSH_WATCHDOG_DIR}/${token}"
  script="${base}.rollback.sh"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null || true
  [ -x "$script" ] || return 1
  NOBRAND_SSH_WATCHDOG_NOW=1 bash "$script"
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
  policy="$(mktemp_file .ssh-policy)" || return 1
  candidate="$(mktemp_file .sshd-candidate)" || return 1
  ssh_tunnel_generate_policy "$policy" || return 1
  ssh_tunnel_build_main_candidate "$policy" "$candidate" || return 1
  ssh_tunnel_sshd_test "$candidate" || { warn 'SSH candidate config syntax validation failed'; return 1; }
  ssh_tunnel_effective_policy_valid "$candidate" "$validation_user" \
    || { warn 'SSH candidate effective-policy validation failed'; return 1; }
  if ssh_tunnel_dropin_supported; then
    strategy=dropin
    target="$NOBRAND_SSH_CONFIG_DROPIN"
  else
    strategy="marker-block"
    target="$NOBRAND_SSH_CONFIG_MAIN"
  fi
  watchdog="$(ssh_tunnel_watchdog_begin "$target" "$requested_operation")" || return 1
  IFS='|' read -r token pid origin operation <<<"$watchdog"
  mkdir -p "$(dirname "$target")" || {
    ssh_tunnel_watchdog_cancel "$token" "$pid"
    return 1
  }
  if [ "$strategy" = dropin ]; then
    nb_atomic_install_file "$policy" "$target" 0600 || {
      ssh_tunnel_watchdog_rollback_now "$token" "$pid" || true
      return 1
    }
  else
    nb_atomic_install_file "$candidate" "$target" 0600 || {
      ssh_tunnel_watchdog_rollback_now "$token" "$pid" || true
      return 1
    }
  fi
  if ! ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" \
     || ! ssh_tunnel_effective_policy_valid "$NOBRAND_SSH_CONFIG_MAIN" "$validation_user" \
     || ! ssh_tunnel_reload; then
    warn 'SSH policy apply/reload failed; rolling back immediately'
    ssh_tunnel_watchdog_rollback_now "$token" "$pid" || warn 'SSH immediate rollback failed; watchdog remains armed'
    return 1
  fi
  state_tmp="$(mktemp_file .ssh-state)" || return 1
  jq --arg strategy "$strategy" --arg path "$target" --arg token "$token" \
    --arg pid "$pid" --arg origin "$origin" --arg operation "$operation" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .config_strategy=$strategy | .managed_config_path=$path | .policy_applied=true
    | .pending_operation=$operation | .pending_watchdog_token=$token
    | .pending_watchdog_pid=$pid | .pending_origin_connection=$origin | .updated_at=$updated
  ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
    && nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 || {
      ssh_tunnel_watchdog_rollback_now "$token" "$pid" || true
      return 1
    }
  rm -f "$state_tmp" "$policy" "$candidate"
  if [ "$token" = disabled ]; then
    ssh_tunnel_confirm_admin disabled
  else
    ssh_tunnel_watchdog_prompt "$token"
  fi
}

ssh_tunnel_remove_policy() {
  local requested_operation="${1:-uninstall}" strategy target candidate candidate_root=""
  local watchdog token pid origin operation state_tmp managed_path
  managed_path="$(ssh_tunnel_state_field managed_config_path)"
  strategy="$(ssh_tunnel_state_field config_strategy)"
  candidate_root="$(mktemp_dir)" || return 1
  candidate="${candidate_root}/sshd_config"
  case "$strategy" in
    dropin)
      [ "$managed_path" = "$NOBRAND_SSH_CONFIG_DROPIN" ] || die 'SSH managed drop-in identity mismatch'
      [ -s "$managed_path" ] || die 'SSH managed drop-in missing'
      ssh_tunnel_build_dropin_removal_candidate "$candidate" "$candidate_root" || return 1
      target="$managed_path"
      ;;
    marker-block)
      [ "$managed_path" = "$NOBRAND_SSH_CONFIG_MAIN" ] || die 'SSH managed marker-block identity mismatch'
      ssh_tunnel_strip_marker_block "$NOBRAND_SSH_CONFIG_MAIN" "$candidate" || return 1
      target="$NOBRAND_SSH_CONFIG_MAIN"
      ;;
    *) die 'SSH managed config strategy 无效' ;;
  esac
  ssh_tunnel_sshd_test "$candidate" || {
    rm -rf -- "$candidate_root"
    die 'SSH policy removal candidate 无法通过 sshd -t'
  }
  watchdog="$(ssh_tunnel_watchdog_begin "$target" "$requested_operation")" || return 1
  IFS='|' read -r token pid origin operation <<<"$watchdog"
  if [ "$strategy" = dropin ]; then
    rm -f "$target" || {
      ssh_tunnel_watchdog_rollback_now "$token" "$pid" || true
      return 1
    }
  else
    nb_atomic_install_file "$candidate" "$target" 0600 || {
      ssh_tunnel_watchdog_rollback_now "$token" "$pid" || true
      return 1
    }
  fi
  if ! ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" || ! ssh_tunnel_reload; then
    warn 'SSH policy removal/reload failed; rolling back immediately'
    ssh_tunnel_watchdog_rollback_now "$token" "$pid" || warn 'SSH immediate rollback failed; watchdog remains armed'
    return 1
  fi
  state_tmp="$(mktemp_file .ssh-state)" || {
    ssh_tunnel_watchdog_rollback_now "$token" "$pid" || true
    return 1
  }
  jq --arg token "$token" --arg pid "$pid" --arg origin "$origin" --arg operation "$operation" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .policy_applied=false | .pending_operation=$operation | .pending_watchdog_token=$token
    | .pending_watchdog_pid=$pid | .pending_origin_connection=$origin | .updated_at=$updated
  ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
    && nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 || {
      ssh_tunnel_watchdog_rollback_now "$token" "$pid" || true
      return 1
    }
  rm -f "$state_tmp"
  rm -rf -- "$candidate_root"
  if [ "$token" = disabled ]; then
    ssh_tunnel_confirm_admin disabled
  else
    ssh_tunnel_watchdog_prompt "$token"
  fi
}

ssh_tunnel_confirm_admin() {
  local supplied="${1:-}" expected pid origin current operation state_tmp continue_unified=0
  require_root
  ssh_tunnel_state_exists || die 'SSH Tunnel state 不存在'
  expected="$(ssh_tunnel_state_field pending_watchdog_token)"
  [ -n "$expected" ] || die '没有待确认的 SSH policy watchdog'
  [ "$supplied" = "$expected" ] || die 'watchdog token 不匹配'
  origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
  current="${SSH_CONNECTION:-}"
  if [ "$expected" != disabled ]; then
    [ -n "$current" ] || die '必须从一条全新的管理员 SSH connection 确认 watchdog'
    [ -z "$origin" ] || [ "$current" != "$origin" ] \
      || die '必须从一条全新的管理员 SSH connection 确认 watchdog'
  fi
  operation="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
  pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
  ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" || return 1
  state_tmp="$(mktemp_file .ssh-state)" || return 1
  jq --arg operation "$operation" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .pending_operation="" | .pending_watchdog_token="" | .pending_watchdog_pid=""
    | .pending_origin_connection=""
    | .policy_applied=(if ($operation=="uninstall" or $operation=="unified-uninstall") then false else true end)
    | .updated_at=$updated
  ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
    && nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 || return 1
  ssh_tunnel_watchdog_cancel "$expected" "$pid"
  rm -f "$state_tmp"
  t '全新管理员 SSH connection 已确认；rollback watchdog 已取消' \
    'Brand-new administrator SSH connection confirmed; rollback watchdog cancelled'
  case "$operation" in
    uninstall) ssh_tunnel_finalize_uninstall ;;
    unified-uninstall)
      ssh_tunnel_finalize_uninstall || return 1
      continue_unified=1
      ;;
  esac
  if [ "$continue_unified" -eq 1 ]; then
    YES=1 nobrand_uninstall
  fi
}

ssh_tunnel_set_endpoint_state() {
  local host="$1" port="$2" mode=custom tmp
  ssh_tunnel_state_exists || die 'SSH Tunnel 未安装'
  if [ -z "$host" ]; then
    mode=auto
    port="$(ssh_tunnel_default_display_port)" || die '无法安全推导 SSH Display port'
  else
    valid_advertise_host "$host" || die 'SSH Display host 无效'
    valid_advertise_port "$port" || die 'SSH Display port 无效'
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
  printf 'SSH Tunnel user: %s\nLinux identity: %s\nIngress Profile: %s\nIngress Enforcement: Not applicable (system sshd)\nActual system listener: *:%s/TCP\nDisplay Endpoint: %s:%s\n' \
    "$label" "$linux_user" "$(nb_ingress_profile_name "$(ssh_tunnel_state_field ingress_profile_id 2>/dev/null || true)")" \
    "$(ssh_tunnel_state_field real_port)" "$host" "$port"
  printf 'Connection: ssh -N -i %s -p %s %s@%s\n' "$key_path" "$port" "$linux_user" "$host"
  printf 'TCP forwarding: -L / -D / -R\nGatewayPorts=no; shell/exec/TTY/SFTP/SCP are disabled.\n'
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
  fingerprint='unavailable'
  known_hosts='unavailable'
  [ -z "$public_key" ] || fingerprint="$(ssh-keygen -lf "$public_key" -E sha256 2>/dev/null || printf unavailable)"
  known_hosts="$(ssh_tunnel_known_hosts_entry "$host" "$port" 2>/dev/null || printf unavailable)"
  printf '%s\n' '===== OPENSSH PRIVATE KEY (explicit export) ====='
  cat "$key_path" || return 1
  printf '%s\n' '===== END OPENSSH PRIVATE KEY =====' ''
  printf 'Host key fingerprint: %s\nknown_hosts: %s\n\n' "$fingerprint" "$known_hosts"
  printf 'SOCKS5 command:\nssh -N -D 127.0.0.1:1080 -i <PRIVATE_KEY> -p %s %s@%s' \
    "$port" "$linux_user" "$host"
  printf ' -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3\n\n'
  printf 'LocalForward template:\nssh -N -L <LOCAL_BIND>:<TARGET_HOST>:<TARGET_PORT> -i <PRIVATE_KEY> -p %s %s@%s -o ExitOnForwardFailure=yes\n\n' \
    "$port" "$linux_user" "$host"
  printf 'RemoteForward template:\nssh -N -R <REMOTE_PORT>:<TARGET_HOST>:<TARGET_PORT> -i <PRIVATE_KEY> -p %s %s@%s -o ExitOnForwardFailure=yes\n' \
    "$port" "$linux_user" "$host"
  printf 'GatewayPorts=no: RemoteForward remains loopback-only and cannot expose a public listener.\n\n'
  printf 'OpenSSH config:\nHost nobrand-%s\n  HostName %s\n  Port %s\n  User %s\n  IdentityFile <PRIVATE_KEY>\n  IdentitiesOnly yes\n  ExitOnForwardFailure yes\n  ServerAliveInterval 30\n  ServerAliveCountMax 3\n' \
    "$(safe_filename_component "$label")" "$host" "$port" "$linux_user"
}

ssh_tunnel_node_rows() {
  local host port status user_json label
  ssh_tunnel_state_exists || return 0
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
    nb_doctor_line INFO 'SSH Tunnel not installed'
    return 0
  fi
  ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" \
    && nb_doctor_line PASS 'sshd config syntax' \
    || { nb_doctor_line FAIL 'sshd config syntax'; failed=1; }
  managed_path="$(ssh_tunnel_state_field managed_config_path)"
  [ -s "$managed_path" ] && nb_doctor_line PASS 'managed Match policy present' \
    || { nb_doctor_line FAIL 'managed Match policy missing'; failed=1; }
  ssh_tunnel_group_identity_valid && nb_doctor_line PASS 'dedicated group identity' \
    || { nb_doctor_line FAIL 'dedicated group identity'; failed=1; }
  validation_user="$(jq -r '.users[0].linux_user // empty' "$NOBRAND_SSH_STATE_FILE")"
  [ -z "$validation_user" ] || ssh_tunnel_effective_policy_valid "$NOBRAND_SSH_CONFIG_MAIN" "$validation_user" \
    && nb_doctor_line PASS 'effective forwarding-only policy' \
    || { nb_doctor_line FAIL 'effective forwarding-only policy'; failed=1; }
  while IFS= read -r user_json; do
    ssh_tunnel_user_identity_valid "$user_json" \
      && nb_doctor_line PASS "identity $(jq -r .display_name <<<"$user_json")" \
      || { nb_doctor_line FAIL "identity $(jq -r .display_name <<<"$user_json")"; failed=1; }
    [ "$(stat -c '%a' "$(ssh_tunnel_key_dir "$(jq -r .account_id <<<"$user_json")")/id_ed25519" 2>/dev/null || true)" = 600 ] \
      && nb_doctor_line PASS "private-key mode $(jq -r .display_name <<<"$user_json")" \
      || { nb_doctor_line FAIL "private-key mode $(jq -r .display_name <<<"$user_json")"; failed=1; }
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  nb_doctor_line PASS 'external_listener=true managed_listener=false managed_firewall=false'
  nb_doctor_line INFO 'NOT_APPLICABLE_TO_SYSTEM_SSH: system sshd / external mapped entry'
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
  local group_preexisting=0
  require_root
  require_linux
  nobrand_prepare_common
  nb_prepare_ingress_request || return 1
  command -v ssh-keygen >/dev/null 2>&1 || die 'SSH Tunnel 需要 OpenSSH ssh-keygen'
  ssh_tunnel_sshd_binary >/dev/null || die '未检测到现有 OpenSSH sshd'
  ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" || die '现有 sshd_config 无法通过 sshd -t'
  ssh_tunnel_state_exists && { t 'SSH Tunnel 已安装' 'SSH Tunnel is already installed'; return 0; }
  label="${SSH_TUNNEL_USER:-default}"
  ssh_tunnel_valid_label "$label" || die 'SSH Tunnel 用户标签无效'
  real_port="$(ssh_tunnel_detect_real_port)" || die '无法读取现有 sshd effective Port'
  if [ -n "${ADVERTISE_HOST:-}" ]; then
    valid_advertise_host "$ADVERTISE_HOST" || die 'SSH Display host 无效'
    valid_advertise_port "$ADVERTISE_PORT" || die 'SSH Display port 无效'
    mode=custom host="$ADVERTISE_HOST" port="$(normalize_uint "$ADVERTISE_PORT")"
  else
    [ "${YES:-0}" -ne 1 ] || [ "${ADVERTISE_AUTO_REQUESTED:-0}" -eq 1 ] \
      || [ -n "$(nb_ingress_profile_display_host "$INGRESS_PROFILE_ID" 2>/dev/null || true)" ] \
      || die '非交互 SSH install 必须明确 Display Endpoint、--advertise-auto 或选择带展示主机的入口配置'
    mode=auto host=""
    if [ -n "${ADVERTISE_PORT:-}" ]; then
      valid_advertise_port "$ADVERTISE_PORT" || die 'SSH Display port 无效'
      port="$(normalize_uint "$ADVERTISE_PORT")"
    else
      port="$(ssh_tunnel_default_display_port)" \
      || die '无法安全推导 SSH Display port；请明确指定'
    fi
  fi
  _has_group "$NOBRAND_SSH_GROUP" && group_preexisting=1
  ssh_tunnel_create_group || die '无法创建 SSH Tunnel group'
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
  if ! ssh_tunnel_apply_policy "$linux_user"; then
    if ! ssh_tunnel_delete_user_internal "$label" >/dev/null 2>&1; then
      warn 'SSH policy apply failed and account rollback was incomplete; state retained for safe retry'
      return 1
    fi
    ssh_tunnel_rollback_empty_install "$group_preexisting" \
      || warn 'SSH install rollback could not remove the newly created empty group'
    return 1
  fi
  nobrand_install_manager_script || true
  ssh_tunnel_show_user "$label"
}

ssh_tunnel_status() {
  ssh_tunnel_state_exists || { t 'SSH Tunnel 未安装' 'SSH Tunnel is not installed'; return 0; }
  printf 'SSH Tunnel\n  Policy: %s\n  Existing sshd real port: %s\n  Display Endpoint: %s:%s\n  Users: %s\n' \
    "$(ssh_tunnel_state_field policy_applied)" "$(ssh_tunnel_state_field real_port)" \
    "$(ssh_tunnel_effective_host)" "$(ssh_tunnel_state_field advertise_port)" \
    "$(jq '.users | length' "$NOBRAND_SSH_STATE_FILE")"
  printf '  Ingress Profile: %s\n' "$(nb_ingress_profile_name "$(ssh_tunnel_state_field ingress_profile_id 2>/dev/null || true)")"
  printf '  Ownership: external_listener=true managed_listener=false managed_firewall=false\n'
}

ssh_tunnel_user_list() {
  ssh_tunnel_state_exists || return 0
  jq -r '.users[]? | [.display_name,.linux_user,.key_fingerprint] | @tsv' "$NOBRAND_SSH_STATE_FILE"
}

ssh_tunnel_restore_preflight() {
  local staged_state="$1" user_json linux_user expected_uid marker
  [ -s "$staged_state" ] || return 0
  jq -e '
    .schema_version==3 and .ownership=="nobrand-v3" and .protocol=="ssh-tunnel"
    and .external_listener==true and .managed_listener==false and .managed_firewall==false
  ' "$staged_state" >/dev/null || return 1
  if _has_group "$NOBRAND_SSH_GROUP"; then
    ssh_tunnel_group_identity_valid || return 1
  fi
  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    expected_uid="$(jq -r .uid <<<"$user_json")"
    if _has_user "$linux_user"; then
      [ "$(id -u "$linux_user")" = "$expected_uid" ] || return 1
      # A backup is not proof that an already-existing local identity belongs
      # to NoBrand. Require the current, pre-restore ownership marker.
      marker="$(ssh_tunnel_account_marker_file "$linux_user")"
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

ssh_tunnel_snapshot_external_state() {
  local snapshot="$1" label path
  mkdir -p "$snapshot" || return 1
  for label in main dropin; do
    case "$label" in
      main) path="$NOBRAND_SSH_CONFIG_MAIN" ;;
      dropin) path="$NOBRAND_SSH_CONFIG_DROPIN" ;;
    esac
    if [ -e "$path" ]; then
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
  ssh_tunnel_state_exists || return 0
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
        warn "SSH restore rollback refused to delete identity mismatch: $name"
        failed=1
      fi
    done < <(awk -F'|' '$1=="USER" {line[NR]=$0} END {for (i=NR;i>=1;i--) if (line[i] != "") print line[i]}' "$log")
    while IFS='|' read -r kind name numeric_id _; do
      [ "$kind" = GROUP ] || continue
      if _has_group "$name"; then
        [ "$(getent group "$name" | awk -F: '{print $3}')" = "$numeric_id" ] || {
          warn "SSH restore rollback refused to delete group identity mismatch: $name"
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
    if [ -e "$snapshot/$label" ]; then
      mkdir -p "$(dirname "$path")" || { failed=1; continue; }
      cp -a "$snapshot/$label" "$path" || failed=1
    else
      rm -f "$path" || failed=1
    fi
  done
  if [ -e "$NOBRAND_SSH_CONFIG_MAIN" ]; then
    ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" && ssh_tunnel_reload || failed=1
  fi
  [ "$failed" -eq 0 ]
}

ssh_tunnel_restore_system_state() {
  local transaction_log="${1:-}" user_json linux_user account_id expected_uid nologin_shell
  local public_key fingerprint validation_user group_preexisting=0 group_gid created_user=0
  ssh_tunnel_state_exists || return 0
  _has_group "$NOBRAND_SSH_GROUP" && group_preexisting=1
  if ! ssh_tunnel_create_group; then
    if [ "$group_preexisting" -eq 0 ] && _has_group "$NOBRAND_SSH_GROUP"; then
      group_gid="$(getent group "$NOBRAND_SSH_GROUP" | awk -F: '{print $3}')"
      ssh_tunnel_log_created_restore_identity "$transaction_log" GROUP \
        "$NOBRAND_SSH_GROUP" "$group_gid"
    fi
    return 1
  fi
  if [ "$group_preexisting" -eq 0 ]; then
    group_gid="$(getent group "$NOBRAND_SSH_GROUP" | awk -F: '{print $3}')"
    ssh_tunnel_log_created_restore_identity "$transaction_log" GROUP \
      "$NOBRAND_SSH_GROUP" "$group_gid"
  fi
  nologin_shell="$(ssh_tunnel_nologin_shell)" || return 1
  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    account_id="$(jq -r .account_id <<<"$user_json")"
    expected_uid="$(jq -r .uid <<<"$user_json")"
    if _has_user "$linux_user"; then
      ssh_tunnel_user_identity_valid "$user_json" || return 1
    else
      created_user=0
      public_key="$(ssh_tunnel_key_dir "$account_id")/id_ed25519.pub"
      fingerprint="$(ssh_tunnel_key_fingerprint "$public_key")" || return 1
      [ "$fingerprint" = "$(jq -r .key_fingerprint <<<"$user_json")" ] || return 1
      if ssh_tunnel_create_linux_user_with_uid "$linux_user" "$account_id" "$nologin_shell" "$expected_uid"; then
        created_user=1
      elif _has_user "$linux_user"; then
        created_user=1
      else
        return 1
      fi
      if [ "$created_user" -eq 1 ]; then
        ssh_tunnel_log_created_restore_identity "$transaction_log" USER \
          "$linux_user" "$expected_uid" "$account_id"
      fi
      [ "$(id -u "$linux_user" 2>/dev/null || true)" = "$expected_uid" ] || return 1
      ssh_tunnel_authorized_key_line "$public_key" "$nologin_shell" \
        >"$(ssh_tunnel_authorized_key_file "$linux_user")" || return 1
      chmod 0644 "$(ssh_tunnel_authorized_key_file "$linux_user")" || return 1
    fi
    chmod 0600 "$(ssh_tunnel_key_dir "$account_id")/id_ed25519" || return 1
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  validation_user="$(jq -r '.users[0].linux_user // empty' "$NOBRAND_SSH_STATE_FILE")"
  [ -n "$validation_user" ] || return 1
  ssh_tunnel_apply_policy "$validation_user" restore
}

ssh_tunnel_restore_deleted_accounts() {
  local snapshot="$1" deleted_list="$2" nologin_shell user_json linux_user account_id uid auth_file
  nologin_shell="$(ssh_tunnel_nologin_shell)" || return 1
  while IFS= read -r user_json; do
    [ -n "$user_json" ] || continue
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    account_id="$(jq -r .account_id <<<"$user_json")"
    uid="$(jq -r .uid <<<"$user_json")"
    if ! _has_user "$linux_user"; then
      ssh_tunnel_create_linux_user_with_uid "$linux_user" "$account_id" "$nologin_shell" "$uid" \
        || return 1
    fi
    auth_file="$(ssh_tunnel_authorized_key_file "$linux_user")"
    [ ! -f "$snapshot/$linux_user" ] || cp -a "$snapshot/$linux_user" "$auth_file" || return 1
  done <"$deleted_list"
}

ssh_tunnel_restore_uninstall_snapshot() {
  local snapshot="$1" deleted_list="$2" group_gid="$3" state_mode config_mode failed=0
  state_mode="$(stat -c '%a' "$snapshot/state-dir" 2>/dev/null || true)"
  config_mode="$(stat -c '%a' "$snapshot/config-dir" 2>/dev/null || true)"
  [[ "$state_mode" =~ ^[0-7]{3,4}$ ]] || return 1
  [[ "$config_mode" =~ ^[0-7]{3,4}$ ]] || return 1
  mkdir -p "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_CONFIG_DIR" || return 1
  cp -a "$snapshot/state-dir/." "$NOBRAND_SSH_STATE_DIR/" || failed=1
  cp -a "$snapshot/config-dir/." "$NOBRAND_SSH_CONFIG_DIR/" || failed=1
  chmod "$state_mode" "$NOBRAND_SSH_STATE_DIR" 2>/dev/null || failed=1
  chmod "$config_mode" "$NOBRAND_SSH_CONFIG_DIR" 2>/dev/null || failed=1
  if ! _has_group "$NOBRAND_SSH_GROUP"; then
    ssh_tunnel_create_group_with_gid "$group_gid" || failed=1
  fi
  if _has_group "$NOBRAND_SSH_GROUP"; then
    ssh_tunnel_restore_deleted_accounts "$snapshot" "$deleted_list" || failed=1
  else
    failed=1
  fi
  [ "$failed" -eq 0 ]
}

ssh_tunnel_finalize_uninstall() {
  local user_json linux_user uid auth_file snapshot deleted_list group_gid
  snapshot="$(mktemp_dir)" || return 1
  deleted_list="${snapshot}/deleted.jsonl"
  : >"$deleted_list"
  ssh_tunnel_group_identity_valid || {
    rm -rf -- "$snapshot"
    die 'SSH Tunnel group identity mismatch，拒绝删除'
  }
  group_gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
  [[ "$group_gid" =~ ^[0-9]+$ ]] || { rm -rf -- "$snapshot"; return 1; }
  cp -a "$NOBRAND_SSH_STATE_DIR" "$snapshot/state-dir" \
    && cp -a "$NOBRAND_SSH_CONFIG_DIR" "$snapshot/config-dir" || {
      rm -rf -- "$snapshot"
      return 1
    }
  while IFS= read -r user_json; do
    ssh_tunnel_user_identity_valid "$user_json" || {
      rm -rf -- "$snapshot"
      die 'SSH Tunnel user identity mismatch，拒绝删除'
    }
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    auth_file="$(ssh_tunnel_authorized_key_file "$linux_user")"
    cp -a "$auth_file" "$snapshot/$linux_user" || { rm -rf -- "$snapshot"; return 1; }
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    uid="$(jq -r .uid <<<"$user_json")"
    rm -f "$(ssh_tunnel_authorized_key_file "$linux_user")"
    pkill -KILL -u "$uid" 2>/dev/null || true
    if ! ssh_tunnel_delete_linux_user "$linux_user"; then
      ssh_tunnel_restore_deleted_accounts "$snapshot" "$deleted_list" || true
      cp -a "$snapshot/$linux_user" "$(ssh_tunnel_authorized_key_file "$linux_user")" 2>/dev/null || true
      rm -rf -- "$snapshot"
      return 1
    fi
    printf '%s\n' "$user_json" >>"$deleted_list"
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  if _has_group "$NOBRAND_SSH_GROUP"; then
    if command -v groupdel >/dev/null 2>&1; then
      groupdel "$NOBRAND_SSH_GROUP" || {
        ssh_tunnel_restore_deleted_accounts "$snapshot" "$deleted_list" || true
        rm -rf -- "$snapshot"
        return 1
      }
    elif command -v delgroup >/dev/null 2>&1; then
      delgroup "$NOBRAND_SSH_GROUP" || {
        ssh_tunnel_restore_deleted_accounts "$snapshot" "$deleted_list" || true
        rm -rf -- "$snapshot"
        return 1
      }
    else
      ssh_tunnel_restore_deleted_accounts "$snapshot" "$deleted_list" || true
      rm -rf -- "$snapshot"
      return 1
    fi
  fi
  if ! find "$NOBRAND_SSH_STATE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! find "$NOBRAND_SSH_CONFIG_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! rmdir "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_CONFIG_DIR" 2>/dev/null; then
    if ! ssh_tunnel_restore_uninstall_snapshot "$snapshot" "$deleted_list" "$group_gid"; then
      warn "SSH Tunnel uninstall rollback incomplete; root-only snapshot retained: $snapshot"
      return 1
    fi
    ssh_tunnel_group_identity_valid || return 1
    while IFS= read -r user_json; do
      ssh_tunnel_user_identity_valid "$user_json" || return 1
    done <"$deleted_list"
    rm -rf -- "$snapshot"
    return 1
  fi
  rm -rf -- "$snapshot"
  t '已删除 NoBrand SSH Tunnel；system sshd/端口/firewall/host keys/admin access 均保留' \
    'Removed NoBrand SSH Tunnel; system sshd/port/firewall/host keys/admin access are preserved'
}

ssh_tunnel_uninstall() {
  local operation="${1:-uninstall}" pending token user_json
  require_root
  ssh_tunnel_state_exists || { t 'SSH Tunnel 未安装' 'SSH Tunnel is not installed'; return 0; }
  pending="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
  if [ "$pending" = uninstall ] || [ "$pending" = unified-uninstall ]; then
    token="$(ssh_tunnel_state_field pending_watchdog_token)"
    [ "$token" = disabled ] || ssh_tunnel_watchdog_prompt "$token"
    return 0
  fi
  [ -z "$pending" ] || die "SSH policy 尚有待确认操作: $pending"
  while IFS= read -r user_json; do
    ssh_tunnel_user_identity_valid "$user_json" \
      || die 'SSH Tunnel user identity mismatch，拒绝卸载'
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  ssh_tunnel_group_identity_valid || die 'SSH Tunnel group identity mismatch，拒绝卸载'
  ssh_tunnel_remove_policy "$operation"
}

nobrand_run_ssh_tunnel_action() {
  case "${SSH_TUNNEL_ACTION:-menu}" in
    install) ssh_tunnel_install ;;
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
SSH Tunnel reuses the existing OpenSSH sshd and allows -L/-D/-R TCP forwarding only.
EOF
      ;;
    *) die "未知 SSH Tunnel 操作: ${SSH_TUNNEL_ACTION}" ;;
  esac
}
