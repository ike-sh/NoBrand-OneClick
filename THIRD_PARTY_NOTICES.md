# Third-Party Notices

NoBrand-OneClick 融合源码整体按 GPL-3.0 发布。以下 notice 不替代各上游许可证。

## ike-sh/mieru-OneClick

NoBrand-OneClick 的 Bash 架构和 Mieru 业务实现源自 `ike-sh/mieru-OneClick`。

MIT License

Copyright (c) 2026 ike-sh

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Other sources and runtimes

- Hysteria2 behavior derives from GPL-3.0 `ike-sh/Xray-OneClick`, principally `lib/57-hysteria2.sh`.
- VLESS TCP FinalMask/Sudoku structure derives from GPL-3.0 `ike-sh/Xray-OneClick`, principally `lib/50-vless-enc.sh`; NoBrand retains the FinalMask/Sudoku transport structure but intentionally omits the VLESS Encryption key-generation and secret layer.
- `enfein/mieru` / `mita` and `XTLS/Xray-core` follow their upstream licenses.
- `SagerNet/sing-box` is downloaded as the official TUIC v5 server runtime and follows its upstream license. No sing-box binary is vendored here.
- SSH Tunnel integrates with the operating system's existing OpenSSH `sshd`; NoBrand does not vendor, replace, or redistribute the OpenSSH server binary.
- Surge Snell Server is downloaded from `dl.nssurge.com`; use follows the developer's terms. No Snell binary is vendored here.
- `zhboner/realm` is downloaded from the official GitHub Release as the optional Port Forward userspace runtime and follows the MIT License (Copyright (c) 2020 zhboner). No Realm binary is vendored here; NoBrand verifies the release digest and installs it only to its private runtime path.
- `zywe03/realm-xwPF` (MIT, Copyright (c) 2025 zywe) was audited as a Port Forward behavior and interaction reference. No realm-xwPF source was copied, no `pf`/xwPF command is installed, and its `/etc/realm` state model is not used by NoBrand.
