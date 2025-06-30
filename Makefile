IMAGE_FILE := artifacts/qemu/noble/packer-noble

image: $(IMAGE_FILE)

clean:
	rm -rf ./artifacts

run: $(IMAGE_FILE)
	qemu-system-x86_64 \
		-enable-kvm \
		-m 8192 \
		-smp 4 \
		-drive file=$(IMAGE_FILE),if=virtio,format=qcow2 \
		-netdev user,id=net0,hostfwd=tcp::2222-:22,dns=8.8.8.8 \
		-device virtio-net-pci,netdev=net0 \
		-nographic

$(IMAGE_FILE): cloud-init-config/* noble.pkr.hcl
	packer init ./noble.pkr.hcl
	packer build -force ./noble.pkr.hcl

.PHONY: image run clean
