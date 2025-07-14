#!/bin/bash
set -euo pipefail

readonly CLOUD_INIT_LOG="/var/log/cloud-init-output.log"
readonly MAX_WAIT_ATTEMPTS=5

# Colors for output
readonly BLUE='\033[0;34m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

find_cloud_init_pid() {
    pgrep -f "python.*cloud-init" | head -1
}

wait_for_cloud_init() {
    local attempt=1

    while (( attempt <= MAX_WAIT_ATTEMPTS )); do
        local pid=$(find_cloud_init_pid)
        if [[ -n "$pid" ]]; then
            echo "$pid"
            return 0
        fi
        sleep 1
        ((attempt++))
    done

    return 1
}

main() {
    log_info "=== Monitoring cloud-init ==="

    local cloud_init_pid
    if cloud_init_pid=$(wait_for_cloud_init); then
        if [[ -f "$CLOUD_INIT_LOG" ]]; then
            sudo tail -f --pid="$cloud_init_pid" "$CLOUD_INIT_LOG"
        else
            log_error "Cloud-init log file not found: $CLOUD_INIT_LOG"
            return 1
        fi
    else
        log_error "Cloud-init process not found"
    fi

    log_info "=== Cloud-init status ==="
    cloud-init status --long --wait
}

main "$@"