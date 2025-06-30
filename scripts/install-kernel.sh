#!/bin/bash
set -euo pipefail

readonly SCRIPT_NAME="${BASH_SOURCE[0]##*/}"

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] DEB_PACKAGE [DEB_PACKAGE...]

Install kernel .deb packages after validating they have the same kernel version.

Options:
  -h, --help               Show this help message and exit

Examples:
  $SCRIPT_NAME linux-image-5.10.35_*.deb linux-headers-5.10.35_*.deb
  $SCRIPT_NAME /path/to/linux-*.deb
EOF
    exit 1
}

extract_kernel_version() {
    local package_name="$1"
    local basename
    basename=$(basename "$package_name")

    # Extract version from package name patterns like:
    #
    # linux-headers-5.10.35_5.10.35-2_amd64.deb
    # linux-image-5.10.35-dbg_5.10.35-2_amd64.deb
    # linux-image-5.10.35_5.10.35-2_amd64.deb
    # linux-libc-dev_5.10.35-2_amd64.deb
    #
    # For the above set of packages, the kernel version should be 5.10.35.
    if [[ "$basename" =~ linux.*([0-9]+\.[0-9]+\.[0-9]+).*\.deb ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

get_common_kernel_version() {
    local packages=("$@")
    local first_version=""
    local current_version=""

    for package in "${packages[@]}"; do
        current_version=$(extract_kernel_version "$package")

        if [[ -z "$current_version" ]]; then
            printf 'Error: Unable to extract kernel version from package: %s\n' "$package" >&2
            return 1
        fi

        if [[ -z "$first_version" ]]; then
            first_version="$current_version"
        elif [[ "$first_version" != "$current_version" ]]; then
            printf 'Error: Package version mismatch!\n' >&2
            printf '  Expected version: %s\n' "$first_version" >&2
            printf '  Found version: %s in package: %s\n' "$current_version" "$package" >&2
            return 1
        fi
    done

    echo "$first_version"
    return 0
}

install_packages() {
    local packages=("$@")

    printf 'Installing kernel packages:\n'
    for package in "${packages[@]}"; do
        printf '  %s\n' "$package"
    done

    sudo dpkg -i "${packages[@]}"

    printf 'Kernel packages installed successfully!\n'
}

main() {
    local packages=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
            *)
                packages+=("$1")
                shift 1
                ;;
        esac
    done

    # Validate that we have at least one package
    if [[ ${#packages[@]} -eq 0 ]]; then
        printf 'Error: No .deb packages specified\n' >&2
        usage
    fi

    # Validate all packages exist
    for package in "${packages[@]}"; do
        if [[ ! -f "$package" ]]; then
            printf 'Error: Package file does not exist: %s\n' "$package" >&2
            exit 1
        fi
    done

    # Validate all packages have the same kernel version
    local kernel_version
    kernel_version=$(get_common_kernel_version "${packages[@]}")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi

    # Install the kernel packages
    install_packages "${packages[@]}"

    # Configure grub to use the installed kernel as default
    if [[ -n "$kernel_version" ]]; then
        printf 'Configuring grub to use kernel version: %s\n' "$kernel_version"

        # Extract submenu ID from grub configuration
        # Example line:
        #   submenu 'Advanced options for Ubuntu' $menuentry_id_option 'gnulinux-advanced-21f08275-91e8-4a2a-85f9-9a52f3ea034b' {
        local submenu_id
        submenu_id=$(sudo grep -E "submenu.*\\\$menuentry_id_option" /boot/grub/grub.cfg | head -1 | \
            sed -n "s/.*\\\$menuentry_id_option[[:space:]]*'\([^']*\)'.*/\1/p" 2>/dev/null || true)

        # Extract kernel ID from grub configuration
        # Example line:
        #   menuentry 'Ubuntu, with Linux 5.10.35' --class ubuntu --class gnu-linux --class gnu \
        #       --class os $menuentry_id_option 'gnulinux-5.10.35-advanced-21f08275-91e8-4a2a-85f9-9a52f3ea034b' {
        local kernel_id
        kernel_id=$(sudo grep -E "menuentry.*${kernel_version}.*\\\$menuentry_id_option" /boot/grub/grub.cfg | \
            grep -v "recovery" | head -1 | \
            sed -n "s/.*\\\$menuentry_id_option[[:space:]]*'\([^']*\)'.*/\1/p" 2>/dev/null || true)

        if [[ -n "$submenu_id" && -n "$kernel_id" ]]; then
            printf 'Found submenu ID: %s\n' "$submenu_id"
            printf 'Found kernel ID: %s\n' "$kernel_id"

            # Set the default grub entry (submenu>kernel format)
            sudo sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"$submenu_id>$kernel_id\"/" /etc/default/grub

            # Update grub
            sudo update-grub

            printf 'Grub configuration updated successfully!\n'
        else
            printf 'Warning: Could not find grub entry for kernel version %s\n' "$kernel_version"
            printf 'You may need to manually update grub configuration.\n'
        fi
    fi
}

main "$@" 