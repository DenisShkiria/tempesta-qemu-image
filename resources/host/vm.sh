#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TMP_DIR="${SCRIPT_DIR}/../../artifacts"
readonly NETWORK_NAME="tempesta-net"
readonly VM_TFW_NAME="tempesta-fw"
readonly VM_TEST_NAME="tempesta-test"

readonly NETWORK_XML_FILE="${SCRIPT_DIR}/libvirt/network.xml"
readonly VM_TEST_XML_FILE="${SCRIPT_DIR}/libvirt/vm-test.xml"
readonly VM_TEST_XML_FILE_TMP="${TMP_DIR}/vm-test-temp.xml"
readonly VM_TFW_XML_FILE="${SCRIPT_DIR}/libvirt/vm-tfw.xml"
readonly VM_TFW_XML_FILE_TMP="${TMP_DIR}/vm-tfw-temp.xml"

# SSH connection configuration
readonly SSH_KEY="${SCRIPT_DIR}/ssh/id_rsa"
readonly SSH_USER="dev"
readonly SSH_WAIT_ATTEMPTS=15
readonly GRACEFUL_SHUTDOWN_ATTEMPTS=10
readonly TFW_VM_IP="192.168.123.10"
readonly TEST_VM_IP="192.168.123.11"

# Source shared library
source "${SCRIPT_DIR}/lib.sh"

connect_over_ssh() {
    local ip_address="$1"
    local ssh_command="${2:-}"
    
    check_dependencies "ssh" || return 1
    
    local ssh_options=(
        -i "$SSH_KEY"
        -o "StrictHostKeyChecking=no"
        -o "UserKnownHostsFile=/dev/null"
        -o "LogLevel=ERROR"
    )
    
    ssh "${ssh_options[@]}" "$SSH_USER@$ip_address" "$ssh_command"
}

show_help() {
    cat << EOF
Virtual Machine and Network Management Script

DESCRIPTION:
    Create and destroy virtual networks and VMs using virsh

USAGE:
    $0 [OPTIONS]

NETWORK OPTIONS:
    --create-network    Create the virtual network
    --destroy-network   Destroy the virtual network

VM OPTIONS:
    --start-vm-tfw <disk_image> <seed_iso> <resources_path> <kernel_path> <tempesta_path>
                        Start the Tempesta FW VM with specified paths
    --stop-vm-tfw       Stop the Tempesta FW VM
    --start-vm-test <disk_image> <seed_iso> <resources_path> <test_path>
                        Start the Tempesta Test VM with specified paths
    --stop-vm-test      Stop the Tempesta Test VM
    --ssh-to-tfw [command]
                        SSH into Tempesta FW VM
                        If no command provided, opens interactive session
    --ssh-to-test [command]
                        SSH into Tempesta Test VM
                        If no command provided, opens interactive session

GENERAL OPTIONS:
    --help              Show this help message
EOF
}

network_exists() {
    check_dependencies "virsh" || return 1

    virsh net-list --name | grep -q "^$NETWORK_NAME$"
}

vm_exists() {
    check_dependencies "virsh" || return 1

    local vm_name="$1"
    virsh list --name | grep -q "^$vm_name$"
}

create_network() {
    check_dependencies "virsh" || return 1
    
    log_info "Creating virtual network: $NETWORK_NAME"
    
    # Check if network already exists
    if network_exists; then
        log_warn "Network '$NETWORK_NAME' already exists"
        return 0
    fi
    
    # Validate network XML file exists
    validate_file "$NETWORK_XML_FILE" "Network XML file" || return 1
    
    # Create the network
    if virsh net-create --validate "$NETWORK_XML_FILE"; then
        log_success "Network '$NETWORK_NAME' created successfully"
    else
        log_error "Failed to create network '$NETWORK_NAME'"
        return 1
    fi
}

destroy_network() {
    check_dependencies "virsh" || return 1

    log_info "Destroying virtual network: $NETWORK_NAME"
    
    # Check if network exists
    if ! network_exists; then
        log_warn "Network '$NETWORK_NAME' does not exist"
        return 0
    fi

    virsh net-destroy "$NETWORK_NAME"
}

create_vm_xml() {
    local template_file="$1"
    local temp_xml_file="$2"
    local serial_log_file="$3"
    local disk_file="$4"
    local seed_iso_file="$5"
    local resources_path="$6"
    shift 6
    local replacements=("$@")

    # Validate template file exists
    validate_file "$template_file" "VM XML template" || return 1

    # Copy template to temporary file
    cp "$template_file" "$temp_xml_file"

    # Replace common placeholders
    sed -i "s|PATH_TO_DISK_IMAGE_PLACEMENT|${disk_file}|g" "$temp_xml_file"
    sed -i "s|PATH_TO_SEED_ISO_PLACEMENT|${seed_iso_file}|g" "$temp_xml_file"
    sed -i "s|PATH_TO_SERIAL_LOG_PLACEMENT|${serial_log_file}|g" "$temp_xml_file"
    sed -i "s|PATH_TO_RESOURCES_PLACEMENT|${resources_path}|g" "$temp_xml_file"

    # Replace placeholders based on VM type
    if [[ "$template_file" == *"vm-tfw.xml" ]]; then
        sed -i "s|PATH_TO_KERNEL_PLACEMENT|${replacements[0]}|g" "$temp_xml_file"
        sed -i "s|PATH_TO_TEMPESTA_PLACEMENT|${replacements[1]}|g" "$temp_xml_file"
    elif [[ "$template_file" == *"vm-test.xml" ]]; then
        sed -i "s|PATH_TO_TEST_PLACEMENT|${replacements[0]}|g" "$temp_xml_file"
    else
        log_error "Unexpected vm template file name '$template_file'"
        return 1
    fi

    log_success "Created temporary VM XML file: $temp_xml_file"
}

start_vm() {
    local xml_file="$1"
    local vm_name="$2"
    local ip_address="$3"

    log_info "Starting VM: $vm_name ($ip_address)"

    if ! network_exists && ! create_network; then
        return 1
    fi

    # Check if VM already exists
    if vm_exists "$vm_name"; then
        log_warn "VM '$vm_name' is already running"
        return 0
    fi

    # Start the VM
    if virsh create --validate "$xml_file"; then
        log_success "VM '$vm_name' started successfully"
    else
        log_error "Failed to start VM '$vm_name'"
        return 1
    fi

    # Wait for VM to be ready to accept SSH connections
    if ! wait_for_ssh_ready "$vm_name" "$ip_address"; then
        log_error "VM '$vm_name' failed to become ready for SSH connections"
        shutdown_vm_forcefully "$vm_name" "$ip_address"
        return 1
    fi
    return 0
}

wait_for_ssh_ready() {
    local vm_name="$1"
    local ip_address="$2"

    log_info "Waiting for VM '$vm_name' ($ip_address) to be ready for SSH connections..."
    
    for i in $(seq 1 "$SSH_WAIT_ATTEMPTS"); do
        if connect_over_ssh "$ip_address" 'exit 0'; then
            log_success "VM '$vm_name' ready for SSH connections!"
            return 0
        fi
        log_info "Waiting for VM '$vm_name' to be ready for SSH connections ($i/$SSH_WAIT_ATTEMPTS)..."
        sleep 1
    done
    
    log_error "Could not establish SSH connection to VM '$vm_name' ($ip_address) after $SSH_WAIT_ATTEMPTS attempts"
    return 1
}

shutdown_vm_forcefully() {
    local vm_name="$1"
    local ip_address="$2"

    log_info "Force shutting down VM '$vm_name' ($ip_address)..."

    if ! vm_exists "$vm_name"; then
        log_warn "VM '$vm_name' is not running"
        return 0
    fi

    if virsh destroy "$vm_name" 2>/dev/null; then
        log_success "VM '$vm_name' process was killed"
    else
        log_error "Failed to force kill VM '$vm_name'"
        return 1
    fi
}

shutdown_vm_gracefully() {
    local vm_name="$1"
    local ip_address="$2"
    
    log_info "Shutting down VM '$vm_name' ($ip_address)..."

    if ! vm_exists "$vm_name"; then
        log_warn "VM '$vm_name' is not running"
        return 0
    fi
    
    log_info "Trying to shutdown VM '$vm_name' gracefully via SSH..."
    if connect_over_ssh "$ip_address" 'sudo shutdown 0'; then
        log_info "Shutdown command sent successfully to VM '$vm_name'"
    else
        log_warn "Could not send shutdown command to VM '$vm_name' via SSH, will force shutdown"
        shutdown_vm_forcefully "$vm_name" "$ip_address"
        return 0
    fi
    
    log_info "Waiting for VM '$vm_name' to shutdown gracefully..."
    for i in $(seq 1 "$GRACEFUL_SHUTDOWN_ATTEMPTS"); do
        if ! virsh list --name | grep -q "^$vm_name$"; then
            log_success "VM '$vm_name' has shut down gracefully"
            return 0
        fi
        log_info "Waiting for shutdown ($i/$GRACEFUL_SHUTDOWN_ATTEMPTS)..."
        sleep 1
    done

    shutdown_vm_forcefully "$vm_name" "$ip_address"
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --create-network)
                create_network || exit 1
                exit 0
                ;;
            --destroy-network)
                destroy_network || exit 1
                exit 0
                ;;
            --start-vm-tfw)
                if [[ $# -lt 6 ]]; then
                    log_error "start-vm-tfw requires 6 parameters: \
                        <disk_image> <seed_iso> <resources_path> <kernel_path> <tempesta_path>"
                    exit 1
                fi
                create_vm_xml \
                    "$VM_TFW_XML_FILE" \
                    "$VM_TFW_XML_FILE_TMP" \
                    "${TMP_DIR}/serial-${VM_TFW_NAME}.log" \
                    "$2" "$3" "$4" "$5" "$6" || exit 1
                start_vm "$VM_TFW_XML_FILE_TMP" "$VM_TFW_NAME" "$TFW_VM_IP" || exit 1
                exit 0
                ;;
            --stop-vm-tfw)
                shutdown_vm_gracefully "$VM_TFW_NAME" "$TFW_VM_IP"
                exit 0
                ;;
            --start-vm-test)
                if [[ $# -lt 4 ]]; then
                    log_error "start-vm-test requires 3 parameters: \
                        <disk_image> <seed_iso> <resources_path> <test_path>"
                    exit 1
                fi
                create_vm_xml \
                    "$VM_TEST_XML_FILE" \
                    "$VM_TEST_XML_FILE_TMP" \
                    "${TMP_DIR}/serial-${VM_TEST_NAME}.log" \
                    "$2" "$3" "$4" "$5" || exit 1
                start_vm "$VM_TEST_XML_FILE_TMP" "$VM_TEST_NAME" "$TEST_VM_IP" || exit 1
                exit 0
                ;;
            --stop-vm-test)
                shutdown_vm_gracefully "$VM_TEST_NAME" "$TEST_VM_IP"
                exit 0
                ;;
            --ssh-to-tfw)
                shift 1
                
                log_info "Connecting to Tempesta FW VM ($TFW_VM_IP)..."
                connect_over_ssh "$TFW_VM_IP" "$*"
                exit 0
                ;;
            --ssh-to-test)
                shift 1
                
                log_info "Connecting to Tempesta Test VM ($TEST_VM_IP)..."
                connect_over_ssh "$TEST_VM_IP" "$*"
                exit 0
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    show_help
    exit 1
}

main "$@"
