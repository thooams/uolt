# UOLT - Ultra Optimised Lightweight Toolset
#
# Single-command build. One assembler across platforms: the clang integrated
# assembler, x86_64 sources in Intel syntax (see include/uolt.inc). OS-specific
# syscall wrappers live in sys/<os>/ and are selected here by host detection.
#
#   make            # build every tool into ./build
#   make test       # run all test layers
#   make bench      # run benchmarks
#   make clean

UNAME_S := $(shell uname -s)

AS      := clang
ASFLAGS := -c -Iinclude

BUILD   := build

# Per-OS syscall directory and link recipe (constitution Principle III is
# platform-aware: Linux fully static; macOS carries the OS-imposed libSystem
# loader stub, into which we make zero calls).
ifeq ($(UNAME_S),Darwin)
  SYSDIR   := sys/macos
  SDKLIB   := $(shell xcrun --show-sdk-path)/usr/lib
  # macOS forbids fully static binaries; carry the OS-imposed libSystem loader
  # only (zero calls into it). Strip is skipped (breaks sub-page Mach-O).
  LINK      = $(AS) -nostdlib -e _start $(1) -L$(SDKLIB) -lSystem -o $(2)
else
  SYSDIR   := sys/linux
  # Fully static; small-page alignment + no build-id keep the ELF tiny, then
  # strip removes the symbol table to approach the < 1 KB target.
  LINK      = $(AS) -nostdlib -static -e _start \
                -Wl,--build-id=none -Wl,-z,max-page-size=0x1000 \
                $(1) -o $(2) && strip $(2)
endif

# Objects shared by every tool (the internal API + selected syscall wrappers).
COMMON_SRC := libuolt/exit.S $(SYSDIR)/exit.S

TOOLS := uolt-true

.PHONY: all test bench clean
all: $(addprefix $(BUILD)/,$(TOOLS))

# uolt-true = its own source + the common objects, linked per-OS.
$(BUILD)/uolt-true: src/true/true.S $(COMMON_SRC) | $(BUILD)
	$(AS) $(ASFLAGS) src/true/true.S -o $(BUILD)/true.o
	$(AS) $(ASFLAGS) libuolt/exit.S -o $(BUILD)/uolt_exit.o
	$(AS) $(ASFLAGS) $(SYSDIR)/exit.S -o $(BUILD)/sys_exit.o
	$(call LINK,$(BUILD)/true.o $(BUILD)/uolt_exit.o $(BUILD)/sys_exit.o,$@)

$(BUILD):
	mkdir -p $(BUILD)

test: all
	@sh tests/unit/true.sh
	@sh tests/unit/true_repeat.sh
	@sh tests/posix/true.sh
	@sh tests/differential/true.sh
	@sh tests/fuzz/true.sh
	@sh tests/trace/true.sh

bench: all
	@sh bench/true.sh

clean:
	rm -rf $(BUILD)
