# The menu intentionally mutates globals inside isolated action subshells; the
# parent only consumes exit codes, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
# NoBrand-OneClick — Mieru / Snell / Hysteria2 / Plain VLESS Sudoku 工具箱
# 作者: ike / https://github.com/ike-sh/NoBrand-OneClick
# Mieru 母体代码源自 ike-sh/mieru-OneClick (MIT)；Hysteria2 与 VLESS
# FinalMask/Sudoku 逻辑参考 ike-sh/Xray-OneClick (GPL-3.0)。本融合项目按
# GPL-3.0 发布；VLESS 为 plain VLESS/TCP，不使用 VLESS Encryption。
set -euo pipefail
umask 077
