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

AS := clang

# Output directory. Overridable so the Linux container build can target a
# separate dir (BUILD=build-linux) and never clobber the host's macOS binaries
# in ./build - the two are different formats (Mach-O vs ELF) and a stale one is
# unrunnable on the other OS. Exported so the test scripts pick the same dir.
BUILD ?= build
export BUILD

# Per-OS syscall directory and link recipe (constitution Principle III is
# platform-aware: Linux fully static; macOS carries the OS-imposed libSystem
# loader stub, into which we make zero calls). $(1) = source .S files, $(2) =
# output binary. clang assembles every .S and links in one step; -Iinclude lets
# sources #include "uolt.inc".
ifeq ($(UNAME_S),Darwin)
  SYSDIR := sys/macos
  OSDEF  := -DUOLT_OS_MACOS
  SDKLIB := $(shell xcrun --show-sdk-path)/usr/lib
  # macOS forbids fully static binaries; carry the OS-imposed libSystem loader
  # only (zero calls into it).
  LINK    = $(AS) -nostdlib -e _start -Iinclude $(OSDEF) $(1) -L$(SDKLIB) -lSystem -o $(2)
else
  SYSDIR := sys/linux
  OSDEF  := -DUOLT_OS_LINUX
  # Fully static and size-first: a custom link script collapses everything into
  # one segment (see sys/linux/uolt.ld), no build-id, then strip all symbols and
  # section headers to approach the < 1 KB target.
  LINK    = $(AS) -nostdlib -static -e _start -Iinclude $(OSDEF) \
              -Wl,--build-id=none -Wl,-T,sys/linux/uolt.ld \
              $(1) -o $(2) && strip -s $(2)
endif

# Sources every tool needs: the per-OS entry shim, the exit API, and the exit
# syscall wrapper.
COMMON := $(SYSDIR)/start.S libuolt/exit.S $(SYSDIR)/exit.S

# Per-tool extra sources (libuolt helpers + syscall wrappers a tool needs beyond
# COMMON). Tools without an entry here just use COMMON.
EXTRA_echo := libuolt/strlen.S libuolt/write.S $(SYSDIR)/write.S
EXTRA_pwd  := libuolt/strlen.S libuolt/write.S libuolt/getcwd.S \
              $(SYSDIR)/write.S $(SYSDIR)/getcwd.S
EXTRA_cat  := libuolt/strlen.S libuolt/write.S libuolt/read.S libuolt/open.S \
              libuolt/close.S $(SYSDIR)/write.S $(SYSDIR)/read.S \
              $(SYSDIR)/open.S $(SYSDIR)/close.S
EXTRA_head := libuolt/strlen.S libuolt/write.S libuolt/read.S libuolt/open.S \
              libuolt/close.S $(SYSDIR)/write.S $(SYSDIR)/read.S \
              $(SYSDIR)/open.S $(SYSDIR)/close.S
EXTRA_tail := libuolt/strlen.S libuolt/write.S libuolt/read.S libuolt/open.S \
              libuolt/close.S libuolt/lseek.S $(SYSDIR)/write.S $(SYSDIR)/read.S \
              $(SYSDIR)/open.S $(SYSDIR)/close.S $(SYSDIR)/lseek.S
EXTRA_wc   := libuolt/strlen.S libuolt/write.S libuolt/read.S libuolt/open.S \
              libuolt/close.S $(SYSDIR)/write.S $(SYSDIR)/read.S \
              $(SYSDIR)/open.S $(SYSDIR)/close.S
EXTRA_yes  := libuolt/strlen.S libuolt/write.S $(SYSDIR)/write.S
EXTRA_basename := libuolt/strlen.S libuolt/write.S $(SYSDIR)/write.S
EXTRA_dirname  := libuolt/strlen.S libuolt/write.S $(SYSDIR)/write.S
EXTRA_sleep    := libuolt/strlen.S libuolt/write.S libuolt/sleep.S \
                  $(SYSDIR)/write.S $(SYSDIR)/sleep.S
EXTRA_mkdir    := libuolt/strlen.S libuolt/write.S libuolt/mkdir.S \
                  $(SYSDIR)/write.S $(SYSDIR)/mkdir.S
EXTRA_rmdir    := libuolt/strlen.S libuolt/write.S libuolt/rmdir.S \
                  $(SYSDIR)/write.S $(SYSDIR)/rmdir.S
EXTRA_touch    := libuolt/strlen.S libuolt/write.S libuolt/close.S \
                  libuolt/create.S libuolt/utimes.S $(SYSDIR)/write.S \
                  $(SYSDIR)/close.S $(SYSDIR)/create.S $(SYSDIR)/utimes.S
EXTRA_ln       := libuolt/strlen.S libuolt/write.S libuolt/link.S \
                  libuolt/symlink.S libuolt/unlink.S $(SYSDIR)/write.S \
                  $(SYSDIR)/link.S $(SYSDIR)/symlink.S $(SYSDIR)/unlink.S
EXTRA_rm       := libuolt/strlen.S libuolt/write.S libuolt/unlink.S \
                  libuolt/opendir.S libuolt/getdents.S libuolt/close.S libuolt/rmdir.S \
                  $(SYSDIR)/write.S $(SYSDIR)/unlink.S $(SYSDIR)/opendir.S \
                  $(SYSDIR)/getdents.S $(SYSDIR)/close.S $(SYSDIR)/rmdir.S
EXTRA_mv       := libuolt/strlen.S libuolt/write.S libuolt/rename.S \
                  $(SYSDIR)/write.S $(SYSDIR)/rename.S
EXTRA_cp       := libuolt/strlen.S libuolt/write.S libuolt/read.S libuolt/open.S \
                  libuolt/close.S libuolt/opendst.S $(SYSDIR)/write.S \
                  $(SYSDIR)/read.S $(SYSDIR)/open.S $(SYSDIR)/close.S $(SYSDIR)/opendst.S
EXTRA_chmod    := libuolt/strlen.S libuolt/write.S libuolt/chmod.S \
                  $(SYSDIR)/write.S $(SYSDIR)/chmod.S
EXTRA_ls       := libuolt/strlen.S libuolt/write.S libuolt/opendir.S libuolt/close.S \
                  libuolt/getdents.S $(SYSDIR)/write.S $(SYSDIR)/opendir.S \
                  $(SYSDIR)/close.S $(SYSDIR)/getdents.S

# Tool names; each maps to src/<name>/<name>.S and produces build/uolt-<name>.
# Add a tool by creating that source, appending its name here, and (if needed) an
# EXTRA_<name> line above.
TOOLNAMES := true false echo pwd cat head tail wc yes basename dirname sleep mkdir rmdir touch ln rm mv cp chmod ls
TOOLBINS  := $(addprefix $(BUILD)/uolt-,$(TOOLNAMES))

.PHONY: all test bench clean
all: $(TOOLBINS)

# One explicit rule per tool (robust across make versions). Each links its own
# source + COMMON + its EXTRA sources in a single clang invocation.
define TOOL_RULE
$(BUILD)/uolt-$(1): src/$(1)/$(1).S $$(COMMON) $$(EXTRA_$(1)) | $$(BUILD)
	$$(call LINK,src/$(1)/$(1).S $$(COMMON) $$(EXTRA_$(1)),$$@)
endef
$(foreach t,$(TOOLNAMES),$(eval $(call TOOL_RULE,$(t))))

$(BUILD):
	mkdir -p $(BUILD)

test: all
	@sh tests/unit/true.sh
	@sh tests/unit/true_repeat.sh
	@sh tests/posix/true.sh
	@sh tests/differential/true.sh
	@sh tests/fuzz/true.sh
	@sh tests/trace/true.sh
	@sh tests/unit/false.sh
	@sh tests/posix/false.sh
	@sh tests/differential/false.sh
	@sh tests/fuzz/false.sh
	@sh tests/unit/echo.sh
	@sh tests/posix/echo.sh
	@sh tests/differential/echo.sh
	@sh tests/fuzz/echo.sh
	@sh tests/trace/echo.sh
	@sh tests/unit/pwd.sh
	@sh tests/differential/pwd.sh
	@sh tests/trace/pwd.sh
	@sh tests/unit/cat.sh
	@sh tests/posix/cat.sh
	@sh tests/differential/cat.sh
	@sh tests/fuzz/cat.sh
	@sh tests/trace/cat.sh
	@sh tests/unit/head.sh
	@sh tests/posix/head.sh
	@sh tests/differential/head.sh
	@sh tests/fuzz/head.sh
	@sh tests/trace/head.sh
	@sh tests/unit/tail.sh
	@sh tests/posix/tail.sh
	@sh tests/differential/tail.sh
	@sh tests/fuzz/tail.sh
	@sh tests/trace/tail.sh
	@sh tests/unit/wc.sh
	@sh tests/posix/wc.sh
	@sh tests/differential/wc.sh
	@sh tests/fuzz/wc.sh
	@sh tests/trace/wc.sh
	@sh tests/unit/yes.sh
	@sh tests/posix/yes.sh
	@sh tests/differential/yes.sh
	@sh tests/trace/yes.sh
	@sh tests/unit/basename.sh
	@sh tests/posix/basename.sh
	@sh tests/differential/basename.sh
	@sh tests/fuzz/basename.sh
	@sh tests/unit/dirname.sh
	@sh tests/posix/dirname.sh
	@sh tests/differential/dirname.sh
	@sh tests/fuzz/dirname.sh
	@sh tests/unit/sleep.sh
	@sh tests/posix/sleep.sh
	@sh tests/trace/sleep.sh
	@sh tests/unit/mkdir.sh
	@sh tests/posix/mkdir.sh
	@sh tests/differential/mkdir.sh
	@sh tests/unit/rmdir.sh
	@sh tests/differential/rmdir.sh
	@sh tests/unit/touch.sh
	@sh tests/differential/touch.sh
	@sh tests/unit/ln.sh
	@sh tests/differential/ln.sh
	@sh tests/unit/rm.sh
	@sh tests/differential/rm.sh
	@sh tests/unit/mv.sh
	@sh tests/differential/mv.sh
	@sh tests/unit/cp.sh
	@sh tests/differential/cp.sh
	@sh tests/unit/chmod.sh
	@sh tests/differential/chmod.sh
	@sh tests/unit/ls.sh
	@sh tests/differential/ls.sh
	@sh tests/trace/ls.sh

bench: all
	@sh bench/run.sh

clean:
	rm -rf $(BUILD)
