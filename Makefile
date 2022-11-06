KERNEL_VERSION = 5.15.6
KERNEL_MAJOR_VERSION = echo ${KERNEL_VERSION} | sed 's/\([(0-9]*\)[^0-9].*/\1/'
KERNEL_URL = https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/linux-${KERNEL_VERSION}.tar.gz

BUSYBOX_VERSION = 1.34.1
BUSYBOX_URL = https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2

#variables
TOP_DIR = $(shell pwd)
BUILD_DIR = ${TOP_DIR}/build
DOWNLOAD_DIR = ${TOP_DIR}/downloads
OUTPUT_DIR = ${TOP_DIR}/output
PATCH_DIR = ${TOP_DIR}/patches
SCRIPTS_DIR = ${TOP_DIR}/scripts
INITRD_DIR = ${TOP_DIR}/output/initrd

#NR_OF_CORES = ${nproc}
NR_OF_CORES = 4

fetch:
	@if [ ! -f downloads/linux-${KERNEL_VERSION}.tar.gz ]; then \
		wget ${KERNEL_URL} -P downloads; \
	else \
		echo "Linux version ${KERNEL_VERSION} already downloaded, skipping"; \
	fi

	@if [ ! -f downloads/busybox-${BUSYBOX_VERSION}.tar.bz2 ]; then \
		wget ${BUSYBOX_URL} -P downloads; \
	else \
		echo "BusyBox version ${BUSYBOX_VERSION} already downloaded, skipping"; \
	fi

extract:
	@if [ ! -d "build/linux-${KERNEL_VERSION}" ]; then \
		echo "extracting Linux-${KERNEL_VERSION}"; \
		tar -xf downloads/linux-${KERNEL_VERSION}.tar.gz --directory build/; \
	else \
		echo "Linux kernel already extracted, skipping"; \
	fi

	@if [ ! -d "build/busybox-${BUSYBOX_VERSION}" ]; then \
		echo "extracting BusyBox-${BUSYBOX_VERSION}"; \
		tar -xf downloads/busybox-${BUSYBOX_VERSION}.tar.bz2 --directory  build/; \
	else \
		echo "BusyBox already extracted, skipping"; \
	fi

patch:
	@if [ -z "$(ls -A patches/busybox && ls -A patches/linux_kernel)" ]; then \
		echo "No patches found, skipping"; \
		exit 0; \
	fi

# patch implementation here

configure: 
	@echo "configuring Linux-${KERNEL_VERSION}"
	@cd "${TOP_DIR}/build/linux-${KERNEL_VERSION}" && \
	$(MAKE) defconfig

	@echo "configuring BusyBox-${BUSYBOX_VERSION}"
	@cd "${TOP_DIR}/build/busybox-${BUSYBOX_VERSION}" && \
	$(MAKE) defconfig && \
	sed 's/^.*CONFIG_STATIC[^_].*$$/CONFIG_STATIC=y/g' -i .config

compile:
	@echo "compiling Linux-${KERNEL_VERSION}"
	cd ${TOP_DIR}/build/linux-${KERNEL_VERSION} && \
	$(MAKE) -j$(NR_OF_CORES)  || exit

	@echo "compiling BusyBox-${BUSYBOX_VERSION}"
	cd ${TOP_DIR}/build/busybox-${BUSYBOX_VERSION} && \
	$(MAKE) -j$(NR_OF_CORES)  || exit

install:
	@echo "moving Linux to ${TOP_DIR}/output"
	@cp ${BUILD_DIR}/linux-${KERNEL_VERSION}/arch/x86_64/boot/bzImage ${TOP_DIR}/output

	@mkdir -p ${INITRD_DIR}/bin ${INITRD_DIR}/dev ${INITRD_DIR}/proc ${INITRD_DIR}/sys
	@echo "moving BusyBox to ${TOP_DIR}/output"
	@cp ${BUILD_DIR}/busybox-${BUSYBOX_VERSION}/busybox ${INITRD_DIR}/bin

	@echo "creating symlinks of BusyBox commands"
	@for prog in $(./${INITRD_DIR}/bin/busybox --list); do \
		ln -s ${INITRD_DIR}/bin/busybox ./${prog}; \
	done

	@cp ${SCRIPTS_DIR}/init ${INITRD_DIR}
	@chmod -R 777 .

	@echo "creating initrd.img"
	@cd ${INITRD_DIR} && find . | cpio -o -H newc > ${OUTPUT_DIR}/initrd.img

help:

run:
	qemu-system-x86_64 -kernel ${OUTPUT_DIR}/bzImage -initrd ${OUTPUT_DIR}/initrd.img \
	-nographic -append "console=ttyS0"

.PHONY: all
all: fetch extract patch configure compile install

clean:
	rm -rf build/* output/*

mrproper:
	rm -rf patches/* downloads/* build/* output/*