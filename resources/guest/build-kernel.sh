#!/bin/bash
set -euo pipefail

readonly SCRIPT_NAME="${BASH_SOURCE[0]##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  -k, --kernel-dir DIR     Path to the directory containing kernel source code
  -d, --debug              Set debug configuration
  -c, --clean-build        Clean kernel directory before building (make clean && make mrproper)
  -h, --help               Show this help message and exit

Examples:
  $SCRIPT_NAME --kernel-dir /path/to/kernel --debug
  $SCRIPT_NAME -k ./linux-5.10.35
  $SCRIPT_NAME --kernel-dir ./linux-5.10.35 --clean-build
EOF
    exit 1
}

comment_config_option() {
    local option="$1"
    sed -i "s/^${option}=/#&/" .config
}

set_config_option() {
    local option="$1"
    local value="$2"

    if grep -q "^${option}=" .config; then
        sed -i "s/^${option}=.*/${option}=${value}/" .config
    else
        echo "${option}=${value}" >> .config
    fi
}

set_base_config_options() {
    # TODO: These options are mentioned in the requirements, but I am not sure if they are
    # really needed. Also, the CONFIG_DEBUG_INFO_BTF is not set in the CI kernel configs.
    set_config_option "CONFIG_DEBUG_INFO_BTF" "y"
    set_config_option "CONFIG_BPF_SYSCALL" "y"
    set_config_option "CONFIG_BPF_JIT" "y"
    set_config_option "CONFIG_HAVE_EBPF_JIT" "y"
    set_config_option "CONFIG_SYN_COOKIES" "y"

    # TODO: The instruction says that the CONFIG_SYSTEM_TRUSTED_KEYRING option should be
    # commented out, but the configs used in the CI have it enabled.
    comment_config_option "CONFIG_SYSTEM_TRUSTED_KEYRING"
    comment_config_option "CONFIG_SYSTEM_TRUSTED_KEYS"

    comment_config_option "CONFIG_DEFAULT_SECURITY_.*"
    set_config_option "CONFIG_LSM" "tempesta,lockdown,yama,loadpin,safesetid,integrity,selinux,smack,tomoyo,apparmor,bpf"

    set_config_option "CONFIG_SLUB" "y"
    set_config_option "CONFIG_HUGETLB_PAGE" "y"
    set_config_option "CONFIG_SECURITY" "y"
    set_config_option "CONFIG_SECURITY_NETWORK" "y"
    set_config_option "CONFIG_SECURITY_TEMPESTA" "y"
    set_config_option "CONFIG_DEFAULT_SECURITY_TEMPESTA" "y"

    set_config_option "CONFIG_SOCK_CGROUP_DATA" "y"
    set_config_option "CONFIG_NET" "y"
    set_config_option "CONFIG_CGROUPS" "y"
    set_config_option "CONFIG_CGROUP_NET_PRIO" "y"

    # The CI for 5.10.35 has CONFIG_UNWINDER_ORC unset, but seems it's not critical because
    # it should be a performance recommendation.
    comment_config_option "CONFIG_UNWINDER_FRAME_POINTER"
    comment_config_option "CONFIG_FRAME_POINTER"
    set_config_option "CONFIG_UNWINDER_ORC" "y"

    # For integration of HTTP tables with iptables and nftables.
    set_config_option "CONFIG_NF_TABLES_IPV4" "y"
    set_config_option "CONFIG_NF_TABLES_IPV6" "y"
    set_config_option "CONFIG_NF_TABLES" "m"

    # TODO: I am not sure if these options for high availability setup are needed for
    # development purposes, but they are present in the kernel configs used in the CI. The
    # instruction also mentions setting of the following options in /etc/sysctl.conf as
    # part of the high availability setup to have the machine rebooted on any hung,
    # software crash or out of memory event.
    # kernel.panic=1
    # kernel.panic_on_oops=1
    # kernel.panic_on_rcu_stall=1
    # vm.panic_on_oom=1
    set_config_option "CONFIG_WATCHDOG" "y"
    set_config_option "CONFIG_SOFTLOCKUP_DETECTOR" "y"
    set_config_option "CONFIG_BOOTPARAM_SOFTLOCKUP_PANIC" "y"
    set_config_option "CONFIG_BOOTPARAM_SOFTLOCKUP_PANIC_VALUE" "1"
    set_config_option "CONFIG_HARDLOCKUP_DETECTOR_PERF" "y"
    set_config_option "CONFIG_HARDLOCKUP_CHECK_TIMESTAMP" "y"
    set_config_option "CONFIG_HARDLOCKUP_DETECTOR" "y"
    set_config_option "CONFIG_BOOTPARAM_HARDLOCKUP_PANIC" "y"
    set_config_option "CONFIG_BOOTPARAM_HARDLOCKUP_PANIC_VALUE" "1"
    set_config_option "CONFIG_DETECT_HUNG_TASK" "y"

    # This seems to be necessary for 6.12.12.
    comment_config_option "CONFIG_SYSTEM_REVOCATION_LIST"
    comment_config_option "CONFIG_SYSTEM_REVOCATION_KEYS"
}

set_debug_config_options() {
    # TODO: The following is the diff between the release and debug versions
    # of 5.10.35 kernel configs used by the CI.
    set_config_option "CONFIG_CC_HAS_ASM_GOTO_OUTPUT" "y"
    set_config_option "CONFIG_CONSTRUCTORS" "y"
    set_config_option "CONFIG_KASAN_SHADOW_OFFSET" "0xdffffc0000000000"
    comment_config_option "CONFIG_VMAP_STACK"
    comment_config_option "CONFIG_BLK_DEV_NULL_BLK_FAULT_INJECTION"
    set_config_option "CONFIG_STACKDEPOT" "y"
    set_config_option "CONFIG_FRAME_WARN" "2048"
    set_config_option "CONFIG_HAVE_KCSAN_COMPILER" "y"
    set_config_option "CONFIG_DEBUG_PAGEALLOC" "y"
    set_config_option "CONFIG_DEBUG_PAGEALLOC_ENABLE_DEFAULT" "y"
    comment_config_option "CONFIG_PAGE_POISONING_ZERO"
    set_config_option "CONFIG_DEBUG_PAGE_REF" "y"
    set_config_option "CONFIG_SLUB_DEBUG_ON" "y"

    set_config_option "CONFIG_DEBUG_KMEMLEAK" "y"
    set_config_option "CONFIG_DEBUG_KMEMLEAK_MEM_POOL_SIZE" "16000"
    comment_config_option "CONFIG_DEBUG_KMEMLEAK_TEST"
    comment_config_option "CONFIG_DEBUG_KMEMLEAK_DEFAULT_OFF"
    set_config_option "CONFIG_DEBUG_KMEMLEAK_AUTO_SCAN" "y"

    set_config_option "CONFIG_DEBUG_MEMORY_INIT" "y"

    set_config_option "CONFIG_KASAN" "y"
    set_config_option "CONFIG_KASAN_GENERIC" "y"
    set_config_option "CONFIG_KASAN_OUTLINE" "y"
    comment_config_option "CONFIG_KASAN_INLINE"
    set_config_option "CONFIG_KASAN_STACK" "1"
    comment_config_option "CONFIG_KASAN_VMALLOC"
    comment_config_option "CONFIG_TEST_KASAN_MODULE"

    comment_config_option "CONFIG_UNWINDER_GUESS"

    comment_config_option "CONFIG_FAILSLAB"
    comment_config_option "CONFIG_FAIL_PAGE_ALLOC"
    comment_config_option "CONFIG_FAULT_INJECTION_USERCOPY"
    comment_config_option "CONFIG_FAIL_MAKE_REQUEST"
    comment_config_option "CONFIG_FAIL_IO_TIMEOUT"
    comment_config_option "CONFIG_FAIL_FUTEX"

    comment_config_option "CONFIG_FAIL_MMC_REQUEST"
}

apply_patch() {
    local patch_file="$1"
    local patch_name
    patch_name=$(basename "$patch_file")

    if [[ -f "$patch_file" ]]; then
        printf 'Checking %s...\n' "$patch_name"

        # Check if patch is already applied
        if patch --dry-run -R -p1 < "$patch_file" > /dev/null 2>&1; then
            printf 'Patch already applied, skipping...\n'
        elif patch -p1 < "$patch_file"; then
            printf 'Patch applied successfully!\n'
        else
            printf 'Error: Failed to apply patch!\n' >&2
            exit 1
        fi
    else
        printf 'Warning: Patch file not found at %s\n' "$patch_file"
    fi
}

main() {
    local kernel_source_dir=""
    local debug_flag="false"
    local clean_build_flag="false"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--kernel-dir)
                kernel_source_dir="$2"
                shift 2
                ;;
            -d|--debug)
                debug_flag="true"
                shift 1
                ;;
            -c|--clean-build)
                clean_build_flag="true"
                shift 1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$kernel_source_dir" ]]; then
        printf 'Error: The --kernel-dir argument is required\n' >&2
        usage
    fi

    # Validate kernel source directory
    if [[ ! -d "$kernel_source_dir" ]]; then
        printf 'Error: Kernel source directory "%s" does not exist.\n' "$kernel_source_dir" >&2
        exit 1
    fi

    printf 'Arguments validated successfully:\n'
    printf '  Kernel source directory: %s\n' "$kernel_source_dir"
    printf '  Debug configuration: %s\n' "$debug_flag"
    printf '  Clean build: %s\n' "$clean_build_flag"

    printf 'Changing to kernel source directory: %s\n' "$kernel_source_dir"
    pushd "$kernel_source_dir" > /dev/null

    if [[ "$clean_build_flag" == "true" ]]; then
        printf 'Cleaning kernel directory...\n'
        make clean && make mrproper
    fi

    printf 'Copying current kernel config...\n'
    cp "/boot/config-$(uname -r)" .config

    printf 'Setting base configuration options...\n'
    set_base_config_options

    if [[ "$debug_flag" == "true" ]]; then
        printf 'Setting debug configuration options...\n'
        set_debug_config_options
    fi

    printf 'Generating final configuration...\n'
    make olddefconfig

    printf 'Applying kernel patches...\n'
    # The link-vmlinux patch is needed to build the kernel inside a directory shared
    # between host OS and guest VM, see
    # https://stackoverflow.com/questions/23936929/error-could-not-mmap-file-vmlinux
    apply_patch "$SCRIPT_DIR/link-vmlinux.patch"

    printf 'Building kernel .deb packages...\n'
    make bindeb-pkg -j"$(nproc)"

    printf 'Kernel build completed successfully!\n'
    popd > /dev/null
}

main "$@"
