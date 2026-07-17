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
UNAME_M := $(shell uname -m)

AS := clang

# Output directory. Overridable so the Linux container build can target a
# separate dir (BUILD=build-linux) and never clobber the host's macOS binaries
# in ./build - the two are different formats (Mach-O vs ELF) and a stale one is
# unrunnable on the other OS. Exported so the test scripts pick the same dir.
BUILD ?= build
export BUILD

# Architecture dimension. Detected from the host (overridable: `make ARCH=arm64`)
# and normalized to the canonical spellings used by our source layout. Both the
# libuolt primitives and the tool bodies are authored per-arch (instruction sets
# are disjoint), so ARCH selects LIBDIR and the tool/extra source path; on Linux
# the syscall numbers differ by arch too, so SYSDIR nests arch under the OS.
# An unknown arch is a hard error (FR-012): we never silently build the wrong ISA.
ARCH ?= $(shell uname -m)
ifneq (,$(filter aarch64 arm64,$(ARCH)))
  ARCH    := arm64
  ARCHDEF := -DUOLT_ARCH_ARM64
  TARGET  := aarch64-linux-gnu
else ifneq (,$(filter x86_64 amd64,$(ARCH)))
  ARCH    := x86_64
  ARCHDEF := -DUOLT_ARCH_X86_64
  TARGET  := x86_64-linux-gnu
else
  $(error Unsupported ARCH '$(ARCH)': expected one of aarch64/arm64 or x86_64/amd64)
endif

# Arch-only layers: libuolt primitives and (below) tool bodies live under <arch>/.
LIBDIR := libuolt/$(ARCH)

# Per-OS(-and-arch) syscall directory and link recipe (constitution Principle III
# is platform-aware: Linux fully static; macOS carries the OS-imposed libSystem
# loader stub, into which we make zero calls). $(1) = source .S files, $(2) =
# output binary. clang assembles every .S and links in one step; -Iinclude lets
# sources #include "uolt.inc"; -DUOLT_ARCH_* selects the assembler dialect.
ifeq ($(UNAME_S),Darwin)
  # macOS syscall layer is not arch-split (only x86_64 macOS is in scope; macOS
  # ARM stays deferred, see the constitution). libuolt is arch-split like Linux.
  SYSDIR := sys/macos
  OSDEF  := -DUOLT_OS_MACOS
  SDKLIB := $(shell xcrun --show-sdk-path)/usr/lib
  # macOS forbids fully static binaries; carry the OS-imposed libSystem loader
  # only (zero calls into it).
  LINK    = $(AS) -nostdlib -e _start -Iinclude $(OSDEF) $(ARCHDEF) $(1) -L$(SDKLIB) -lSystem -o $(2)
else
  SYSDIR := sys/linux/$(ARCH)
  OSDEF  := -DUOLT_OS_LINUX
  # Cross-linking to aarch64 from an x86_64 host needs lld (GNU ld in the image is
  # single-target) and the aarch64 cross-strip (host strip cannot process aarch64
  # ELF). A NATIVE aarch64 build (host uname -m already aarch64, e.g. an AUR/Nix
  # aarch64 builder) uses the plain native ld + strip instead - the cross tools are
  # not installed there. The native x86_64 path keeps GNU ld + strip so its output
  # stays byte-identical to the pre-arch build (SC-005).
  ifeq ($(ARCH),arm64)
    ifeq (,$(filter aarch64 arm64,$(UNAME_M)))
      LDFLAGS := -fuse-ld=lld
      STRIP   := aarch64-linux-gnu-strip
    else
      LDFLAGS :=
      STRIP   := strip
    endif
  else
    LDFLAGS :=
    STRIP   := strip
  endif
  # Fully static and size-first: a custom link script collapses everything into
  # one segment (see sys/linux/uolt.ld), no build-id, then strip all symbols and
  # section headers to approach the < 1 KB target.
  LINK    = $(AS) -target $(TARGET) -nostdlib -static -e _start -Iinclude $(OSDEF) $(ARCHDEF) \
              $(LDFLAGS) -Wl,--build-id=none -Wl,-T,sys/linux/uolt.ld \
              $(1) -o $(2) && $(STRIP) -s $(2)
endif

# Sources every tool needs: the per-OS entry shim, the exit API, and the exit
# syscall wrapper.
COMMON := $(SYSDIR)/start.S $(LIBDIR)/exit.S $(SYSDIR)/exit.S

# Per-tool extra sources (libuolt helpers + syscall wrappers a tool needs beyond
# COMMON). Tools without an entry here just use COMMON.
EXTRA_echo := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(SYSDIR)/write.S
EXTRA_pwd  := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/getcwd.S \
              $(SYSDIR)/write.S $(SYSDIR)/getcwd.S
EXTRA_cat  := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(LIBDIR)/open.S \
              $(LIBDIR)/close.S $(SYSDIR)/write.S $(SYSDIR)/read.S \
              $(SYSDIR)/open.S $(SYSDIR)/close.S
EXTRA_head := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(LIBDIR)/open.S \
              $(LIBDIR)/close.S $(SYSDIR)/write.S $(SYSDIR)/read.S \
              $(SYSDIR)/open.S $(SYSDIR)/close.S
EXTRA_tail := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(LIBDIR)/open.S \
              $(LIBDIR)/close.S $(LIBDIR)/lseek.S $(LIBDIR)/mmap.S $(LIBDIR)/munmap.S \
              $(SYSDIR)/write.S $(SYSDIR)/read.S \
              $(SYSDIR)/open.S $(SYSDIR)/close.S $(SYSDIR)/lseek.S \
              $(SYSDIR)/mmap.S $(SYSDIR)/munmap.S
EXTRA_wc   := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(LIBDIR)/open.S \
              $(LIBDIR)/close.S $(SYSDIR)/write.S $(SYSDIR)/read.S \
              $(SYSDIR)/open.S $(SYSDIR)/close.S
EXTRA_yes  := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(SYSDIR)/write.S
EXTRA_basename := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(SYSDIR)/write.S
EXTRA_dirname  := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(SYSDIR)/write.S
EXTRA_env      := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/execve.S \
                  $(SYSDIR)/write.S $(SYSDIR)/execve.S
EXTRA_sleep    := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/sleep.S \
                  $(SYSDIR)/write.S $(SYSDIR)/sleep.S
EXTRA_mkdir    := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/mkdir.S $(LIBDIR)/chmod.S \
                  $(SYSDIR)/write.S $(SYSDIR)/mkdir.S $(SYSDIR)/chmod.S
EXTRA_rmdir    := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/rmdir.S \
                  $(SYSDIR)/write.S $(SYSDIR)/rmdir.S
EXTRA_touch    := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/close.S \
                  $(LIBDIR)/create.S $(LIBDIR)/utimes.S $(SYSDIR)/write.S \
                  $(SYSDIR)/close.S $(SYSDIR)/create.S $(SYSDIR)/utimes.S
EXTRA_ln       := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/link.S \
                  $(LIBDIR)/symlink.S $(LIBDIR)/unlink.S $(LIBDIR)/statmode.S \
                  $(SYSDIR)/write.S \
                  $(SYSDIR)/link.S $(SYSDIR)/symlink.S $(SYSDIR)/unlink.S \
                  $(SYSDIR)/statmode.S
EXTRA_rm       := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/unlink.S \
                  $(LIBDIR)/opendir.S $(LIBDIR)/getdents.S $(LIBDIR)/close.S $(LIBDIR)/rmdir.S \
                  $(SYSDIR)/write.S $(SYSDIR)/unlink.S $(SYSDIR)/opendir.S \
                  $(SYSDIR)/getdents.S $(SYSDIR)/close.S $(SYSDIR)/rmdir.S
EXTRA_mv       := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/rename.S $(LIBDIR)/statmode.S \
                  $(SYSDIR)/write.S $(SYSDIR)/rename.S $(SYSDIR)/statmode.S
EXTRA_cp       := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(LIBDIR)/open.S \
                  $(LIBDIR)/close.S $(LIBDIR)/opendst.S $(LIBDIR)/opendir.S \
                  $(LIBDIR)/getdents.S $(LIBDIR)/mkdir.S $(LIBDIR)/statmode.S \
                  $(SYSDIR)/write.S \
                  $(SYSDIR)/read.S $(SYSDIR)/open.S $(SYSDIR)/close.S \
                  $(SYSDIR)/opendst.S $(SYSDIR)/opendir.S $(SYSDIR)/getdents.S \
                  $(SYSDIR)/mkdir.S $(SYSDIR)/statmode.S
EXTRA_chmod    := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/chmod.S $(LIBDIR)/statmode.S $(LIBDIR)/umask.S \
                  $(SYSDIR)/write.S $(SYSDIR)/chmod.S $(SYSDIR)/statmode.S $(SYSDIR)/umask.S
EXTRA_ls       := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/opendir.S $(LIBDIR)/close.S \
                  $(LIBDIR)/getdents.S $(SYSDIR)/write.S $(SYSDIR)/opendir.S \
                  $(SYSDIR)/close.S $(SYSDIR)/getdents.S
EXTRA_seq      := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(SYSDIR)/write.S
EXTRA_grep     := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(LIBDIR)/open.S $(LIBDIR)/close.S $(SYSDIR)/write.S $(SYSDIR)/read.S $(SYSDIR)/open.S $(SYSDIR)/close.S
EXTRA_find     := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/opendir.S $(LIBDIR)/close.S $(LIBDIR)/getdents.S $(SYSDIR)/write.S $(SYSDIR)/opendir.S $(SYSDIR)/close.S $(SYSDIR)/getdents.S
EXTRA_sort     := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(LIBDIR)/open.S $(LIBDIR)/close.S $(LIBDIR)/mmap.S $(LIBDIR)/munmap.S $(SYSDIR)/write.S $(SYSDIR)/read.S $(SYSDIR)/open.S $(SYSDIR)/close.S $(SYSDIR)/mmap.S $(SYSDIR)/munmap.S
EXTRA_tee      := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(LIBDIR)/close.S $(LIBDIR)/opendst.S $(LIBDIR)/openapp.S $(SYSDIR)/write.S $(SYSDIR)/read.S $(SYSDIR)/close.S $(SYSDIR)/opendst.S $(SYSDIR)/openapp.S
EXTRA_uniq     := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(LIBDIR)/open.S $(LIBDIR)/close.S $(LIBDIR)/mmap.S $(LIBDIR)/munmap.S $(SYSDIR)/write.S $(SYSDIR)/read.S $(SYSDIR)/open.S $(SYSDIR)/close.S $(SYSDIR)/mmap.S $(SYSDIR)/munmap.S
EXTRA_cut      := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(LIBDIR)/open.S $(LIBDIR)/close.S $(SYSDIR)/write.S $(SYSDIR)/read.S $(SYSDIR)/open.S $(SYSDIR)/close.S
EXTRA_tr       := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(SYSDIR)/write.S $(SYSDIR)/read.S
EXTRA_comm     := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S $(LIBDIR)/open.S $(LIBDIR)/close.S $(SYSDIR)/write.S $(SYSDIR)/read.S $(SYSDIR)/open.S $(SYSDIR)/close.S
EXTRA_printf   := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(SYSDIR)/write.S
EXTRA_test     := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/statmode.S $(LIBDIR)/lstatmode.S \
                  $(LIBDIR)/statsize.S $(LIBDIR)/access.S \
                  $(SYSDIR)/write.S $(SYSDIR)/statmode.S $(SYSDIR)/lstatmode.S \
                  $(SYSDIR)/statsize.S $(SYSDIR)/access.S
EXTRA_expr     := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(SYSDIR)/write.S

# Tool names; each maps to src/<name>/<name>.S and produces build/uolt-<name>.
# Add a tool by creating that source, appending its name here, and (if needed) an
# EXTRA_<name> line above.
TOOLNAMES := true false echo pwd cat head tail wc yes basename dirname sleep mkdir rmdir touch ln rm mv cp chmod ls seq grep find sort tee uniq env cut tr comm printf test expr
TOOLBINS  := $(addprefix $(BUILD)/uolt-,$(TOOLNAMES))

# --- UOLT extras: non-core, non-POSIX convenience tools (see constitution's
# Extras section). They reuse the same sys/ + $(LIBDIR)/ infrastructure but live
# under extras/<name>/<name>.S and are kept out of the POSIX-only core so the
# core stays a strict POSIX subset. Each still obeys every other principle.
EXTRA_column   := $(LIBDIR)/strlen.S $(LIBDIR)/write.S $(LIBDIR)/read.S \
                  $(LIBDIR)/mmap.S $(LIBDIR)/munmap.S \
                  $(SYSDIR)/write.S $(SYSDIR)/read.S \
                  $(SYSDIR)/mmap.S $(SYSDIR)/munmap.S
EXTRANAMES := column
EXTRABINS  := $(addprefix $(BUILD)/uolt-,$(EXTRANAMES))

.PHONY: all test bench clean install uninstall
all: $(TOOLBINS) $(EXTRABINS)

# One explicit rule per tool (robust across make versions). Each links its own
# source + COMMON + its EXTRA sources in a single clang invocation.
define TOOL_RULE
$(BUILD)/uolt-$(1): src/$(1)/$(ARCH)/$(1).S $$(COMMON) $$(EXTRA_$(1)) | $$(BUILD)
	$$(call LINK,src/$(1)/$(ARCH)/$(1).S $$(COMMON) $$(EXTRA_$(1)),$$@)
endef
$(foreach t,$(TOOLNAMES),$(eval $(call TOOL_RULE,$(t))))

# Same recipe for extras, but their source lives under extras/<name>/.
define EXTRA_RULE
$(BUILD)/uolt-$(1): extras/$(1)/$(ARCH)/$(1).S $$(COMMON) $$(EXTRA_$(1)) | $$(BUILD)
	$$(call LINK,extras/$(1)/$(ARCH)/$(1).S $$(COMMON) $$(EXTRA_$(1)),$$@)
endef
$(foreach t,$(EXTRANAMES),$(eval $(call EXTRA_RULE,$(t))))

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
	@sh tests/unit/env.sh
	@sh tests/differential/env.sh
	@sh tests/unit/cut.sh
	@sh tests/differential/cut.sh
	@sh tests/unit/tr.sh
	@sh tests/differential/tr.sh
	@sh tests/unit/comm.sh
	@sh tests/differential/comm.sh
	@sh tests/unit/printf.sh
	@sh tests/differential/printf.sh
	@sh tests/unit/test.sh
	@sh tests/differential/test.sh
	@sh tests/unit/expr.sh
	@sh tests/differential/expr.sh
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
	@sh tests/unit/seq.sh
	@sh tests/differential/seq.sh
	@sh tests/unit/grep.sh
	@sh tests/differential/grep.sh
	@sh tests/unit/find.sh
	@sh tests/differential/find.sh
	@sh tests/unit/sort.sh
	@sh tests/differential/sort.sh
	@sh tests/unit/tee.sh
	@sh tests/differential/tee.sh
	@sh tests/unit/uniq.sh
	@sh tests/differential/uniq.sh
	@sh tests/unit/column.sh
	@sh tests/differential/column.sh
	@sh tests/fuzz/column.sh
	@sh tests/trace/column.sh

bench: all
	@sh bench/run.sh

# Shadow the system coreutils without touching /usr/bin: symlink each tool into
# $(PREFIX)/bin under its bare name (uolt-cat -> cat). Put $(PREFIX)/bin ahead of
# /usr/bin in PATH to activate, remove it to deactivate - fully reversible. Never
# install into /usr/bin: these are POSIX subsets (no GNU flags) with documented
# bounds (sort caps at 1 MB, ls unsorted, tail/pipe caps at 64 KB), so they are a
# shadow for interactive/test use, not a system-wide coreutils replacement. The
# extras (EXTRANAMES) are shadowed the same way under their bare name - note
# `column` implements only the `-t` table mode, so shadowing bare `column`
# replaces the default terminal-fill mode too.
PREFIX ?= $(HOME)/.local
install: all
	@mkdir -p $(PREFIX)/bin
	@for t in $(TOOLNAMES) $(EXTRANAMES); do \
	  ln -sf $(abspath $(BUILD))/uolt-$$t $(PREFIX)/bin/$$t; \
	  echo "  $(PREFIX)/bin/$$t -> uolt-$$t"; \
	done
	@ln -sf $(abspath $(BUILD))/uolt-test $(PREFIX)/bin/[
	@echo "  $(PREFIX)/bin/[ -> uolt-test"
	@echo "Installed $(words $(TOOLNAMES)) core tools + $(words $(EXTRANAMES)) extras (+ the [ alias of test). Add to PATH: export PATH=\"$(PREFIX)/bin:$$PATH\""

# Remove only the symlinks we own, and only if they still point at our binaries -
# never delete a real file a user may have placed there.
uninstall:
	@for t in $(TOOLNAMES) $(EXTRANAMES) '['; do \
	  l=$(PREFIX)/bin/$$t; \
	  case "$$t" in '[') tgt=uolt-test;; *) tgt=uolt-$$t;; esac; \
	  if [ -L "$$l" ] && [ "$$(readlink "$$l")" = "$(abspath $(BUILD))/$$tgt" ]; then \
	    rm -f "$$l"; echo "  removed $$l"; \
	  fi; \
	done

clean:
	rm -rf $(BUILD)
