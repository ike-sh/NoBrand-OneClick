# The menu intentionally mutates globals inside isolated action subshells; the
# parent only consumes exit codes, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
# mieru / mita 服务端一键安装脚本
# 作者: ike / https://github.com/ike-sh/mieru-OneClick
# 基于 https://github.com/enfein/mieru
set -euo pipefail
umask 077
