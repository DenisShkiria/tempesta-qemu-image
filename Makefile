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
IMAGE_FILE := $(ARTIFACTS_DIR)/tempesta-fw.qcow2
SEED_ISO := $(ARTIFACTS_DIR)/seed.iso
SSH_KEY := $(ARTIFACTS_DIR)/id_rsa

# SSH connection configuration
SSH_WAIT_ATTEMPTS := 30
GRACEFUL_SHUTDOWN_ATTEMPTS := 10
SSH_PORT := 2222
SSH_CONNECT := ssh -i $(SSH_KEY) -p $(SSH_PORT) \
	-o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null \
	-o LogLevel=ERROR \
	dev@localhost

# VM configuration
VM_MEMORY := 4096
VM_CPUS := 4
VM_DISK_SIZE := +50G

clean:
	rm -rf $(ARTIFACTS_DIR)

ssh-connect:
	@$(SSH_CONNECT) || true

build-and-run: $(IMAGE_FILE)
	@echo "Starting VM in background..."
	@$(MAKE) run-vm-in-background

	@echo "Connecting to VM over SSH..."
	@$(MAKE) ssh-connect

	@$(MAKE) shutdown-vm

shutdown-vm:
	@echo "Shutting down VM gracefully..."
	@$(SSH_CONNECT) 'sudo shutdown now' || true

	@if [ -f $(ARTIFACTS_DIR)/qemu.pid ]; then \
		vm_pid=$$(cat $(ARTIFACTS_DIR)/qemu.pid); \
		echo "Waiting for VM to shutdown gracefully..."; \
		for i in $$(seq 1 $(GRACEFUL_SHUTDOWN_ATTEMPTS)); do \
			if ! kill -0 $$vm_pid 2>/dev/null; then \
				echo "VM has shut down gracefully"; \
				break; \
			fi; \
			echo "Waiting for shutdown ($$i/$(GRACEFUL_SHUTDOWN_ATTEMPTS))..."; \
			sleep 1; \
		done; \
		if kill -0 $$vm_pid 2>/dev/null; then \
			echo "VM did not shut down gracefully, force killing..."; \
			kill -9 $$vm_pid 2>/dev/null || true; \
			echo "VM process killed"; \
		fi; \
		rm -f $(ARTIFACTS_DIR)/qemu.pid; \
	else \
		echo "No VM pidfile found"; \
	fi;

run-vm-in-background:
	@qemu-system-x86_64 \
		-cpu host \
		-enable-kvm \
		-m $(VM_MEMORY) \
		-smp $(VM_CPUS) \
		-drive if=virtio,format=qcow2,file=$(IMAGE_FILE) \
		-drive if=virtio,format=raw,file=$(SEED_ISO) \
		-netdev type=user,id=net0,hostfwd=tcp::$(SSH_PORT)-:22 \
		-device virtio-net-pci,netdev=net0 \
		-virtfs local,path=$(PWD)/linux-6.12.12-tfw,mount_tag=linux-6.12.12-tfw,security_model=passthrough,id=linux-6.12.12-tfw \
		-virtfs local,path=$(PWD)/linux-5.10.35-tfw,mount_tag=linux-5.10.35-tfw,security_model=passthrough,id=linux-5.10.35-tfw \
		-virtfs local,path=$(PWD)/tempesta,mount_tag=tempesta,security_model=passthrough,id=tempesta \
		-virtfs local,path=$(PWD)/scripts,mount_tag=scripts,security_model=passthrough,id=scripts \
		-serial file:$(ARTIFACTS_DIR)/qemu-serial.log \
		-display none \
		-pidfile $(ARTIFACTS_DIR)/qemu.pid \
		-daemonize

	@echo "Waiting for VM to be ready for SSH connections..."
	@ssh_ready=false; \
	for i in $$(seq 1 $(SSH_WAIT_ATTEMPTS)); do \
		if $(SSH_CONNECT) 'exit 0' 2>/dev/null; then \
			echo "VM ready for SSH connections!"; \
			ssh_ready=true; \
			break; \
		fi; \
		echo "Waiting for VM to be ready for SSH connections ($$i/$(SSH_WAIT_ATTEMPTS))..."; \
		sleep 1; \
	done; \
	if [ "$$ssh_ready" = "false" ]; then \
		echo "ERROR: Could not establish SSH connection after $(SSH_WAIT_ATTEMPTS) attempts"; \
		$(MAKE) shutdown-vm || true; \
		exit 1; \
	fi

$(IMAGE_FILE): $(CLOUD_IMAGE_FILE).checked $(SEED_ISO)
	@mkdir -p $(dir $@)
	@cp $(CLOUD_IMAGE_FILE) $@
	@qemu-img resize $@ $(VM_DISK_SIZE)

	@echo "Starting VM to trigger cloud-init..."
	@$(MAKE) run-vm-in-background

	@echo "Connecting to VM over SSH..."
	@$(SSH_CONNECT) 'bash -s' < $(PWD)/scripts/monitor-cloud-init.sh || true

	@$(MAKE) shutdown-vm

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

$(SSH_KEY):
	@echo "Generating SSH key pair..."
	@mkdir -p $(dir $@)
	@ssh-keygen -t rsa -b 2048 -f $@ -N "" -C "tempesta-vm-key"
	@echo "SSH key pair generated: $@ and $@.pub"

$(SEED_ISO): cloud-init-config/* $(SSH_KEY)
	@echo "Creating cloud-init ISO with SSH public key..."
	@mkdir -p $(dir $@)
	@sed "s|SSH_PUBLIC_KEY_PLACEHOLDER|$$(cat $(SSH_KEY).pub)|g" \
		cloud-init-config/user-data > $(ARTIFACTS_DIR)/user-data
	@genisoimage -output $@ \
		-volid cidata \
		-joliet -rock \
		-input-charset utf-8 \
		$(ARTIFACTS_DIR)/user-data \
		cloud-init-config/meta-data \
		cloud-init-config/network-config

.PHONY: build-and-run run-vm-in-background shutdown-vm ssh-connect clean
