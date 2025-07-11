#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLOUD_INIT_LOG="/var/log/cloud-init-output.log"
readonly MAX_WAIT_ATTEMPTS=5

# Source shared library
source "${SCRIPT_DIR}/lib.sh"

find_cloud_init_pid() {
    pgrep -f "python.*cloud-init" | head -1
}

wait_for_cloud_init() {
    local attempt=1

    log_info "Waiting for cloud-init process to start..."

    while (( attempt <= MAX_WAIT_ATTEMPTS )); do
        local pid=$(find_cloud_init_pid)
        if [[ -n "$pid" ]]; then
            log_info "Found cloud-init process with PID: $pid"
            echo "$pid"
            return 0
        fi

        log_info "Waiting for cloud-init (attempt $attempt/$MAX_WAIT_ATTEMPTS)..."
        sleep 1
        ((attempt++))
    done

    log_error "Cloud-init process not found"
    return 1
}

main() {
    echo "=== Monitoring cloud-init ==="

    local cloud_init_pid
    if cloud_init_pid=$(wait_for_cloud_init); then
        log_info "Monitoring cloud-init logs..."

        if [[ -f "$CLOUD_INIT_LOG" ]]; then
            sudo tail -f --pid="$cloud_init_pid" "$CLOUD_INIT_LOG"
        else
            log_error "Cloud-init log file not found: $CLOUD_INIT_LOG"
            return 1
        fi
    fi

    echo "=== Cloud-init status ==="
    cloud-init status --long --wait
}

main "$@"