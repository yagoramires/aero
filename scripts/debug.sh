#!/bin/zsh
# Envia um comando ao Aero aberto (precisa de: defaults write local.aero debugBridge -bool true).
# Uso: scripts/debug.sh left | right | up | down | screen-left | screen-right | screen-up | screen-down
#                       | dump | check-update | install-latest
# O dump vai para /tmp/aero-debug.txt.
set -euo pipefail
swift - "$*" <<'SWIFT'
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    .init("local.aero.debug"), object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
SWIFT
