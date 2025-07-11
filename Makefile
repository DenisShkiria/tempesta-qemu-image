# Makefile for building Tempesta FW kernel in QEMU VM
# 
# Available targets:
#   build-and-run        - Build VM image if needed, start VM in background and connect to it over SSH.
#   run-vm-in-background - Start VM in background.
#   shutdown-vm          - Shutdown VM if it's running.
#   ssh-connect          - Connect to VM over SSH. The VM should be running.
#   clean                - Remove all artifacts.

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

clean:
	rm -rf $(ARTIFACTS_DIR)

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
		$(PWD)/linux-5.10.35-tfw \
		$(PWD)/tempesta \
		$(PWD)/resources/guest

.PHONY: start-vm-test
start-vm-test:
# TODO: add test path
	@resources/host/vm.sh --start-vm-test \
		$(IMAGE_FILE_TEST) \
		$(SEED_ISO_TEST) \
		$(PWD)/resources/guest

$(IMAGE_FILE_TEST): $(CLOUD_IMAGE_FILE).checked $(SEED_ISO_TEST)
	@mkdir -p $(dir $@)
	@cp $(CLOUD_IMAGE_FILE) $@
	@qemu-img resize $@ $(VM_DISK_SIZE)

	@echo "Starting VM to trigger cloud-init..."
	@$(MAKE) start-vm-test

	@echo "Connecting to VM over SSH..."
	@resources/host/vm.sh --ssh-to-test \
		"bash -s < $(PWD)/resources/host/monitor-cloud-init.sh" || true

	@resources/host/vm.sh --stop-vm-test

$(IMAGE_FILE_TFW): $(CLOUD_IMAGE_FILE).checked $(SEED_ISO_TFW)
	@mkdir -p $(dir $@)
	@cp $(CLOUD_IMAGE_FILE) $@
	@qemu-img resize $@ $(VM_DISK_SIZE)

	@echo "Starting VM to trigger cloud-init..."
	@$(MAKE) start-vm-tfw

	@echo "Connecting to VM over SSH..."
	@resources/host/vm.sh --ssh-to-tfw \
		"bash -s < $(PWD)/resources/host/monitor-cloud-init.sh" || true

	@resources/host/vm.sh --stop-vm-tfw

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
