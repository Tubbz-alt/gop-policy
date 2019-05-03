TARGET?=x86_64-efi-pe

export LD=ld
export RUST_TARGET_PATH=$(CURDIR)/targets
BUILD=build/$(TARGET)

all: $(BUILD)/boot.efi

clean:
	cargo clean
	rm -rf build

update:
	git submodule update --init --recursive --remote
	cargo update

$(BUILD)/OVMF_VARS.fd: /usr/share/OVMF/OVMF_VARS.fd
	cp $< $@

qemu: $(BUILD)/boot.img $(BUILD)/OVMF_VARS.fd
	kvm -M q35 -m 1024 -net none -vga std $< \
		-drive if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=$(BUILD)/OVMF_VARS.fd \
		-chardev stdio,id=debug -device isa-debugcon,iobase=0x402,chardev=debug

$(BUILD)/boot.img: $(BUILD)/efi.img
	dd if=/dev/zero of=$@.tmp bs=512 count=100352
	parted $@.tmp -s -a minimal mklabel gpt
	parted $@.tmp -s -a minimal mkpart EFI FAT16 2048s 93716s
	parted $@.tmp -s -a minimal toggle 1 boot
	dd if=$< of=$@.tmp bs=512 count=98304 seek=2048 conv=notrunc
	mv $@.tmp $@

$(BUILD)/efi.img: $(BUILD)/boot.efi
	dd if=/dev/zero of=$@.tmp bs=512 count=98304
	mkfs.vfat $@.tmp
	mmd -i $@.tmp efi
	mmd -i $@.tmp efi/boot
	mcopy -i $@.tmp $< ::driver.efi
	mv $@.tmp $@

$(BUILD)/boot.efi: $(BUILD)/boot.o
	$(LD) \
		-m i386pep \
		--oformat pei-x86-64 \
		--dll \
		--image-base 0 \
		--section-alignment 32 \
		--file-alignment 32 \
		--major-os-version 0 \
		--minor-os-version 0 \
		--major-image-version 0 \
		--minor-image-version 0 \
		--major-subsystem-version 0 \
		--minor-subsystem-version 0 \
		--subsystem 11 \
		--heap 0,0 \
		--stack 0,0 \
		--pic-executable \
		--entry _start \
		--no-insert-timestamp \
		$< -o $@

$(BUILD)/boot.o: $(BUILD)/boot.a
	rm -rf $(BUILD)/boot
	mkdir $(BUILD)/boot
	cd $(BUILD)/boot && ar x ../boot.a
	ld -r $(BUILD)/boot/*.o -o $@

$(BUILD)/boot.a: Cargo.lock Cargo.toml src/*
	mkdir -p $(BUILD)
	cargo xrustc \
		--lib \
		--target $(TARGET) \
		--release \
		-- \
		-C soft-float \
		-C lto \
		--emit link=$@
