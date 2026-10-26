"""Terminal presentation of canonical client_profiles; no protocol generation."""
import json
import sys
from pathlib import Path


class ProfileError(ValueError):
    """A field name may be reported; profile values must never enter errors."""


def needed(value, field):
    if value is None or value == "" or value == [] or value == {}:
        raise ProfileError(field)
    return value


def endpoint(host, port):
    needed(host, "server")
    needed(port, "port")
    if not isinstance(host, str) or host in ("0.0.0.0", "::"):
        raise ProfileError("server")
    if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
        raise ProfileError("port")
    return host_port(host, port)


def host_port(host, port):
    # Match the CLI url_host convention; the Python generators have no shared helper.
    return ("[" + host + "]" if ":" in host and not host.startswith("[") else host) + ":" + str(port)


def client_only(value):
    """Fail closed if server private material enters a native client document."""
    forbidden = {"privatekey", "serversecret", "signingkey", "masterkey", "keyfile"}
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = key.replace("_", "").replace("-", "").lower()
            if normalized in forbidden or normalized.endswith(("privatekey", "privatekeyfile")):
                raise ProfileError("server private material")
            client_only(child)
    elif isinstance(value, list):
        for child in value:
            client_only(child)


def render_client_profiles(result, listeners=None, chinese=True):
    """Return all client sections atomically, without changing any input value."""
    listeners = listeners or {}
    profiles = needed(result.get("client_profiles"), "client_profiles")
    if not isinstance(profiles, list):
        raise ProfileError("client_profiles")
    lines = []
    titles = {"mieru": "Mieru", "snell": "Snell", "hysteria2": "Hysteria2",
              "tuic": "TUIC v5", "vless-reality": "VLESS REALITY"}
    def label(zh, en):
        return zh if chinese else en
    def field(zh, en, value, required=False):
        if required:
            needed(value, en)
        if value is not None and value != "" and value != [] and value != {}:
            lines.append(label(zh, en) + ": " + str(value))
    def section(zh, en, content):
        if content is not None and content != "" and content != [] and content != {}:
            lines.extend(["", "[" + label(zh, en) + "]"])
            if isinstance(content, str):
                lines.append(content.rstrip("\n"))
            else:
                client_only(content)
                lines.append(json.dumps(content, ensure_ascii=False, indent=2))
    def connection(host, port):
        field("客户端入口", "Client endpoint", endpoint(host, port))
    for index, profile in enumerate(profiles, 1):
        protocol = profile.get("protocol")
        if protocol not in titles:
            raise ProfileError("unsupported protocol")
        entries = needed(profile.get("profiles"), "profiles") if protocol == "tuic" else [profile]
        for user_index, entry in enumerate(entries, 1):
            lines.extend(["=" * 60, " " + titles[protocol] + label(" 节点配置", " client configuration")])
            if len(profiles) > 1:
                lines.append(" Profile " + str(index) + " / " + str(len(profiles)))
            if len(entries) > 1:
                lines.append(label(" 用户 ", " User ") + str(user_index) + " / " + str(len(entries)))
            lines.extend(["=" * 60, "", "[" + label("基本信息", "Connection info") + "]"])
            field("节点", "Node", profile.get("id"))
            listener = listeners.get(profile.get("id"))
            if listener:
                field("服务监听", "Server listen", host_port(listener["host"], listener["port"]))
            if protocol == "mieru":
                native = needed(profile.get("mieru"), "mieru")
                for config in needed(native.get("profiles"), "profiles"):
                    user = config["user"]
                    field("用户名", "Username", user.get("name"), True)
                    field("密码", "Password", user.get("password"), True)
                    field("传输预设", "Profile", config.get("profileName"))
                    for server in needed(config.get("servers"), "servers"):
                        host = server.get("domainName") or server.get("ipAddress")
                        for binding in needed(server.get("portBindings"), "portBindings"):
                            field("传输协议", "Transport", binding.get("protocol"), True)
                            connection(host, binding.get("port"))
                native_label = ("Mieru 原生客户端配置", "Mieru native client configuration")
            elif protocol == "vless-reality":
                native = needed(profile.get("xray"), "xray")
                target = native["settings"]["vnext"][0]
                user = target["users"][0]
                reality = native["streamSettings"]["realitySettings"]
                connection(target.get("address"), target.get("port"))
                field("UUID", "UUID", user.get("id"), True)
                field("Flow", "Flow", user.get("flow"), True)
                for zh, en, key in (("SNI", "SNI", "serverName"), ("Public Key", "Public Key", "publicKey"),
                                    ("Short ID", "Short ID", "shortId"), ("Fingerprint", "Fingerprint", "fingerprint")):
                    field(zh, en, reality.get(key), True)
                native_label = ("Xray 客户端出站配置", "Xray client outbound configuration")
            else:
                native = needed(entry.get("sing_box"), "sing_box")
                outbound = native["outbounds"][0] if protocol == "tuic" else native
                connection(outbound.get("server"), outbound.get("server_port"))
                if protocol == "snell":
                    field("PSK", "PSK", outbound.get("psk"), True)
                    field("服务端版本", "Server version", profile.get("server_version"))
                    field("客户端协议版本", "Client wire version", outbound.get("version"), True)
                else:
                    if protocol == "tuic":
                        field("用户", "User", entry.get("user"))
                        field("UUID", "UUID", outbound.get("uuid"), True)
                        field("拥塞控制", "Congestion control", outbound.get("congestion_control"))
                        field("UDP 转发模式", "UDP relay mode", outbound.get("udp_relay_mode"))
                    field("密码", "Password", outbound.get("password"), True)
                    tls = needed(outbound.get("tls"), "tls")
                    field("SNI", "SNI", tls.get("server_name"), True)
                    field("TLS 策略", "TLS policy", label("校验 CA 与主机名", "Verify CA and hostname")
                          if tls.get("insecure") is False else label("跳过证书校验", "Skip certificate verification"))
                    obfs = outbound.get("obfs", {})
                    field("混淆", "Obfuscation", obfs.get("type"))
                    field("混淆密码", "Obfuscation password", obfs.get("password"))
                native_label = (("sing-box 客户端配置", "sing-box client configuration") if protocol == "tuic"
                                else ("sing-box 客户端出站配置", "sing-box client outbound configuration"))
            section("分享链接", "Share link", profile.get("uri"))
            section("Mihomo / Clash Meta", "Mihomo / Clash Meta", entry.get("mihomo"))
            section("Surge", "Surge", entry.get("surge"))
            section(*native_label, native)
            lines.extend(["", "=" * 60, ""])
    return "\n".join(lines)


def main():
    try:
        result = json.load(sys.stdin)
        # State supplies only listener metadata; client fields come from the profile.
        state = json.loads(Path(sys.argv[1]).read_text())
        listeners = {node["id"]: node["document"]["listener"] for node in state["nodes"]}
        output = render_client_profiles(result, listeners, sys.argv[2] == "1")
    except ProfileError as exc:
        print("[错误 / Error] CLIENT_PROFILE_INVALID: " + str(exc), file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError, IndexError, AttributeError):
        print("[错误 / Error] CLIENT_PROFILE_INVALID: 客户端配置不完整或无效 / incomplete or invalid client profile", file=sys.stderr)
        return 1
    print(output, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
