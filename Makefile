# =============================================================================
# Makefile — xemu Kiosk Builder
# Usage:
#   make build       — build the full kiosk image
#   make shell       — enter the builder container for debugging
#   make clean       — remove output images
#   make flash DEV=/dev/sdX  — flash image to a USB drive
# =============================================================================

BUILDER_IMAGE  := xemu-kiosk-builder
OUTPUT_DIR     := $(CURDIR)/output
CONFIG_FILE    := $(CURDIR)/config/build.env

# Load config values for display
IMAGE_NAME     := $(shell grep '^IMAGE_NAME'    $(CONFIG_FILE) | cut -d= -f2)
IMAGE_SIZE_MB  := $(shell grep '^IMAGE_SIZE_MB' $(CONFIG_FILE) | cut -d= -f2)

.PHONY: all build shell clean flash help

all: build

## build: Build the kiosk disk image
build: _check_docker _build_builder_image
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo " Building xemu kiosk image"
	@echo " Output: $(OUTPUT_DIR)/$(IMAGE_NAME).img"
	@echo " Size:   $(IMAGE_SIZE_MB) MB"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@mkdir -p $(OUTPUT_DIR)
	docker run --rm \
		--privileged \
		--env-file $(CONFIG_FILE) \
		-v $(OUTPUT_DIR):/output \
		$(BUILDER_IMAGE)
	@echo ""
	@echo "✅ Done! Image: $(OUTPUT_DIR)/$(IMAGE_NAME).img"

## shell: Enter builder container interactively for debugging
shell: _check_docker _build_builder_image
	@mkdir -p $(OUTPUT_DIR)
	docker run --rm -it \
		--privileged \
		--env-file $(CONFIG_FILE) \
		-v $(OUTPUT_DIR):/output \
		--entrypoint /bin/bash \
		$(BUILDER_IMAGE)

## clean: Remove output directory
clean:
	rm -rf $(OUTPUT_DIR)
	@echo "Cleaned output/"

## distclean: Remove output AND builder Docker image
distclean: clean
	docker rmi $(BUILDER_IMAGE) 2>/dev/null || true

## flash: Flash image to USB drive (requires DEV= argument)
## Usage: make flash DEV=/dev/sdb
flash:
	@[ -n "$(DEV)" ] || (echo "Usage: make flash DEV=/dev/sdX" && exit 1)
	sudo bash $(OUTPUT_DIR)/flash.sh $(DEV) $(OUTPUT_DIR)/$(IMAGE_NAME).img

## logs: Show builder container logs (last run must still be running)
logs:
	docker logs $$(docker ps -q --filter ancestor=$(BUILDER_IMAGE)) 2>/dev/null || \
		echo "No running builder container found"

## help: Show this help
help:
	@echo "xemu Kiosk Builder"
	@echo ""
	@grep -E '^## ' Makefile | sed 's/^## /  /'

# ── Internal targets ──────────────────────────────────────────────────────────
_check_docker:
	@command -v docker >/dev/null 2>&1 || \
		(echo "Docker is not installed or not in PATH" && exit 1)

_build_builder_image:
	@echo "Building Docker builder image..."
	docker build -t $(BUILDER_IMAGE) .
