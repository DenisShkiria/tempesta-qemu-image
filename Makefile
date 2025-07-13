# Makefile for building Tempesta FW kernel in QEMU VM
# 
# Available targets:
#   build-and-start-tfw  - Build TFW VM image if needed, start VM and connect to it over SSH.
#   build-and-start-test - Build Test VM image if needed, start VM and connect to it over SSH.
#   ssh-to-tfw           - Connect to TFW VM over SSH. The VM should be running.
#   ssh-to-test          - Connect to Test VM over SSH. The VM should be running.
#   start-vm-tfw         - Start TFW VM.
#   start-vm-test        - Start Test VM.
#   shutdown-vm-tfw      - Shutdown TFW VM.
#   shutdown-vm-test     - Shutdown Test VM.
#   shutdown-all         - Shutdown all VMs and destroy virtual network.
#
# Variables:
#   KERNEL_PATH          - Path to the kernel directory (default: $(PWD)/../linux-5.10.35-tfw)
#   TEMPESTA_PATH        - Path to the Tempesta directory (default: $(PWD)/../tempesta)
#   TEST_PATH            - Path to the test directory (default: $(PWD)/../tempesta-test)

KERNEL_PATH ?= $(PWD)/../linux-5.10.35-tfw
TEMPESTA_PATH ?= $(PWD)/../tempesta
TEST_PATH ?= $(PWD)/../tempesta-test

export KERNEL_PATH TEMPESTA_PATH TEST_PATH

CLOUD_IMAGE_CHECKSUM := "92d2c4591af9a82785464bede56022c49d4be27bde1bdcf4a9fccc62425cda43"
CLOUD_IMAGE_URL := "https://cloud-images.ubuntu.com/noble/20250610/noble-server-cloudimg-amd64.img"

ARTIFACTS_DIR := artifacts
CLOUD_IMAGE_FILE := $(ARTIFACTS_DIR)/cloud-image.qcow2
IMAGE_FILE_TFW := $(ARTIFACTS_DIR)/tempesta-fw.qcow2
IMAGE_FILE_TEST := $(ARTIFACTS_DIR)/tempesta-test.qcow2
SEED_ISO_TFW := $(ARTIFACTS_DIR)/seed-tfw.iso
SEED_ISO_TEST := $(ARTIFACTS_DIR)/seed-test.iso
SSH_KEY := resources/host/ssh/id_rsa

VM_DISK_SIZE := +50G

.PHONY: shutdown-all
shutdown-all:
	@$(MAKE) shutdown-vm-tfw
	@$(MAKE) shutdown-vm-test
	@resources/host/vm.sh --destroy-network

.PHONY: ssh-to-tfw
ssh-to-tfw:
	@resources/host/vm.sh --ssh-to-tfw

.PHONY: ssh-to-test
ssh-to-test:
	@resources/host/vm.sh --ssh-to-test

.PHONY: build-and-start-tfw
build-and-start-tfw: $(IMAGE_FILE_TFW)
	@$(MAKE) start-vm-tfw
	@$(MAKE) ssh-to-tfw
	@$(MAKE) shutdown-vm-tfw

.PHONY: build-and-start-test
build-and-start-test: $(IMAGE_FILE_TEST)
	@$(MAKE) start-vm-test
	@$(MAKE) ssh-to-test
	@$(MAKE) shutdown-vm-test

.PHONY: shutdown-vm-tfw
shutdown-vm-tfw:
	@resources/host/vm.sh --stop-vm-tfw

.PHONY: shutdown-vm-test
shutdown-vm-test:
	@resources/host/vm.sh --stop-vm-test

.PHONY: start-vm-tfw
start-vm-tfw:
	@resources/host/vm.sh --start-vm-tfw \
		$(IMAGE_FILE_TFW) \
		$(SEED_ISO_TFW) \
		$(KERNEL_PATH) \
		$(TEMPESTA_PATH) \
		$(PWD)/resources/guest

.PHONY: start-vm-test
start-vm-test:
	@resources/host/vm.sh --start-vm-test \
		$(IMAGE_FILE_TEST) \
		$(SEED_ISO_TEST) \
		$(TEST_PATH)

$(IMAGE_FILE_TEST): $(CLOUD_IMAGE_FILE).checked $(SEED_ISO_TEST)
	@mkdir -p $(dir $@)
	@cp $(CLOUD_IMAGE_FILE) $@
	@qemu-img resize $@ $(VM_DISK_SIZE)

	@echo "Starting VM to trigger cloud-init..."
	@$(MAKE) start-vm-test

	@echo "Connecting to VM over SSH..."
	@resources/host/vm.sh --ssh-to-test \
		"bash -s < $(PWD)/resources/host/monitor-cloud-init.sh" || true

	@$(MAKE) shutdown-vm-test

$(IMAGE_FILE_TFW): $(CLOUD_IMAGE_FILE).checked $(SEED_ISO_TFW)
	@mkdir -p $(dir $@)
	@cp $(CLOUD_IMAGE_FILE) $@
	@qemu-img resize $@ $(VM_DISK_SIZE)

	@echo "Starting VM to trigger cloud-init..."
	@$(MAKE) start-vm-tfw

	@echo "Connecting to VM over SSH..."
	@resources/host/vm.sh --ssh-to-tfw \
		"bash -s < $(PWD)/resources/host/monitor-cloud-init.sh" || true

	@$(MAKE) shutdown-vm-tfw

$(CLOUD_IMAGE_FILE).checked: $(CLOUD_IMAGE_FILE)
	@echo "Verifying cloud image checksum..."
	@if ! sha256sum $(CLOUD_IMAGE_FILE) | grep -q $(CLOUD_IMAGE_CHECKSUM); then \
		@echo "Checksum verification failed, removing bad file"; \
		@rm -f $(CLOUD_IMAGE_FILE) $@; \
		@$(MAKE) $@; \
	else \
		@echo "Cloud image checksum OK"; \
		@touch $@; \
	fi

$(CLOUD_IMAGE_FILE):
	@echo "Downloading cloud image..."
	@mkdir -p $(dir $@)
	@curl -L -o $@ $(CLOUD_IMAGE_URL)

$(SEED_ISO_TEST): $(SSH_KEY) $(SSH_KEY).pub resources/host/cloud-init/network-config resources/host/cloud-init/test/*
	@echo "Creating cloud-init ISO for test VM..."
	@mkdir -p $(dir $@)
	@genisoimage -output $@ \
		-volid cidata \
		-joliet -rock \
		-input-charset utf-8 \
		resources/host/cloud-init/test/user-data \
		resources/host/cloud-init/test/meta-data \
		resources/host/cloud-init/network-config

$(SEED_ISO_TFW): $(SSH_KEY) $(SSH_KEY).pub resources/host/cloud-init/network-config resources/host/cloud-init/tfw/*
	@echo "Creating cloud-init ISO for TFW VM..."
	@mkdir -p $(dir $@)
	@genisoimage -output $@ \
		-volid cidata \
		-joliet -rock \
		-input-charset utf-8 \
		resources/host/cloud-init/tfw/user-data \
		resources/host/cloud-init/tfw/meta-data \
		resources/host/cloud-init/network-config
