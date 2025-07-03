CLOUD_IMAGE_CHECKSUM := "92d2c4591af9a82785464bede56022c49d4be27bde1bdcf4a9fccc62425cda43"
CLOUD_IMAGE_URL := "https://cloud-images.ubuntu.com/noble/20250610/noble-server-cloudimg-amd64.img"

ARTIFACTS_DIR := artifacts
CLOUD_IMAGE_FILE := $(ARTIFACTS_DIR)/cloud-image.qcow2
IMAGE_FILE := $(ARTIFACTS_DIR)/tempesta-fw.qcow2
SEED_ISO := $(ARTIFACTS_DIR)/seed.iso

clean:
	rm -rf $(ARTIFACTS_DIR)

run: $(IMAGE_FILE)
	qemu-system-x86_64 \
		-cpu host \
		-enable-kvm \
		-m 8192 \
		-smp 4 \
		-drive if=virtio,format=qcow2,file=$(IMAGE_FILE) \
		-drive if=virtio,format=raw,file=$(SEED_ISO) \
		-netdev type=user,id=net0,hostfwd=tcp::2222-:22 \
		-device virtio-net-pci,netdev=net0 \
		-virtfs local,path=$(PWD)/kernel,mount_tag=kernel,security_model=passthrough,id=kernel \
		-virtfs local,path=$(PWD)/tempesta,mount_tag=tempesta,security_model=passthrough,id=tempesta \
		-nographic

image: $(IMAGE_FILE)

$(IMAGE_FILE): $(CLOUD_IMAGE_FILE).checked $(SEED_ISO)
	@mkdir -p $(dir $@)
	@cp $(CLOUD_IMAGE_FILE) $@
	@qemu-img resize $@ +50G

$(CLOUD_IMAGE_FILE).checked: $(CLOUD_IMAGE_FILE)
	@echo "Verifying cloud image checksum..."
	@if ! sha256sum $(CLOUD_IMAGE_FILE) | grep -q $(CLOUD_IMAGE_CHECKSUM); then \
		echo "Checksum verification failed, removing bad file"; \
		rm -f $(CLOUD_IMAGE_FILE) $@; \
		$(MAKE) $@; \
	else \
		echo "Cloud image checksum OK"; \
		touch $@; \
	fi

$(CLOUD_IMAGE_FILE):
	@echo "Downloading cloud image..."
	@mkdir -p $(dir $@)
	@curl -L -o $@ $(CLOUD_IMAGE_URL)

$(SEED_ISO): cloud-init-config/*
	@mkdir -p $(dir $@)
	genisoimage -output $@ \
		-volid cidata \
		-joliet -rock \
		-input-charset utf-8 \
		cloud-init-config/*

.PHONY: image run clean
