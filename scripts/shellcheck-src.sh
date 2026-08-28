#!/usr/bin/env bash
# Lint-only ordered source model. The generated release artifact never sources src/.
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
set --
export MITA_SOURCE_ONLY=1

# shellcheck source=src/00-bootstrap.sh
source "${SOURCE_ROOT}/src/00-bootstrap.sh"
# shellcheck source=src/05-constants.sh
source "${SOURCE_ROOT}/src/05-constants.sh"
# shellcheck source=src/10-cli-prelude.sh
source "${SOURCE_ROOT}/src/10-cli-prelude.sh"
# shellcheck source=src/15-core-state.sh
source "${SOURCE_ROOT}/src/15-core-state.sh"
# shellcheck source=src/16-core-port.sh
source "${SOURCE_ROOT}/src/16-core-port.sh"
# shellcheck source=src/17-core-endpoint.sh
source "${SOURCE_ROOT}/src/17-core-endpoint.sh"
# shellcheck source=src/18-core-nodes.sh
source "${SOURCE_ROOT}/src/18-core-nodes.sh"
# shellcheck source=src/20-platform-mieru.sh
source "${SOURCE_ROOT}/src/20-platform-mieru.sh"
# shellcheck source=src/21-platform-xray-hy2.sh
source "${SOURCE_ROOT}/src/21-platform-xray-hy2.sh"
# shellcheck source=src/22-platform-snell.sh
source "${SOURCE_ROOT}/src/22-platform-snell.sh"
# shellcheck source=src/23-platform-vless-sudoku.sh
source "${SOURCE_ROOT}/src/23-platform-vless-sudoku.sh"
# shellcheck source=src/25-network-mtu.sh
source "${SOURCE_ROOT}/src/25-network-mtu.sh"
# shellcheck source=src/30-users-instance.sh
source "${SOURCE_ROOT}/src/30-users-instance.sh"
# shellcheck source=src/35-users-state.sh
source "${SOURCE_ROOT}/src/35-users-state.sh"
# shellcheck source=src/40-tc-quota.sh
source "${SOURCE_ROOT}/src/40-tc-quota.sh"
# shellcheck source=src/45-backup-user-actions.sh
source "${SOURCE_ROOT}/src/45-backup-user-actions.sh"
# shellcheck source=src/50-diagnostics.sh
source "${SOURCE_ROOT}/src/50-diagnostics.sh"
# shellcheck source=src/52-user-actions-ui.sh
source "${SOURCE_ROOT}/src/52-user-actions-ui.sh"
# shellcheck source=src/55-profile-config.sh
source "${SOURCE_ROOT}/src/55-profile-config.sh"
# shellcheck source=src/56-snell.sh
source "${SOURCE_ROOT}/src/56-snell.sh"
# shellcheck source=src/57-hysteria2.sh
source "${SOURCE_ROOT}/src/57-hysteria2.sh"
# shellcheck source=src/58-vless-sudoku.sh
source "${SOURCE_ROOT}/src/58-vless-sudoku.sh"
# shellcheck source=src/60-daemon-firewall-network.sh
source "${SOURCE_ROOT}/src/60-daemon-firewall-network.sh"
# shellcheck source=src/65-service-bbr.sh
source "${SOURCE_ROOT}/src/65-service-bbr.sh"
# shellcheck source=src/70-client-export-install.sh
source "${SOURCE_ROOT}/src/70-client-export-install.sh"
# shellcheck source=src/71-snell-export.sh
source "${SOURCE_ROOT}/src/71-snell-export.sh"
# shellcheck source=src/80-lifecycle.sh
source "${SOURCE_ROOT}/src/80-lifecycle.sh"
# shellcheck source=src/85-status-actions.sh
source "${SOURCE_ROOT}/src/85-status-actions.sh"
# shellcheck source=src/90-ui.sh
source "${SOURCE_ROOT}/src/90-ui.sh"
# shellcheck source=src/99-main.sh
source "${SOURCE_ROOT}/src/99-main.sh"
