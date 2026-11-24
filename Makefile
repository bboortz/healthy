# healthy — top-level Makefile.
# All variables forward to build.sh; see memory/workflow.md for the gate matrix.
#
#   make build                             # x86_64-linux, TLS on (default)
#   make build TLS=0                       # strip TLS code
#   make build CA=ca.pem                   # embed a private CA
#   make build TARGET=aarch64-linux        # cross-compile a specific target
#   make check                             # full local gate

ZIG      ?= zig
TARGET   ?= x86_64-linux
TLS      ?= 1
CA       ?=
OUT      ?= bin/hc-$(TARGET)
HC       ?= ./$(OUT)

# Pinned Zig version — match memory/project.md § Zig version pin.
ZIG_VERSION ?= 0.17.1

# System packages required to build + test + lint. Arch names.
# On other distros: shellcheck / openssl / python / pipx (names may differ).
SYSTEM_PKGS := openssl python shellcheck python-pipx

# Cross-targets built (but NOT executed) by `make cross`.
CROSS_TARGETS := x86_64-linux aarch64-linux riscv64-linux arm-linux-musleabihf x86-linux

# Size-budget baseline (README § Build). KB, stripped ReleaseSmall, baseline CPU.
# Breaching by >5% requires justification in the PR body.
SIZE_BUDGET_X86_64_TLS_KB   := 450
SIZE_BUDGET_X86_64_NOTLS_KB := 140

SHELL_FILES := scripts/build.sh scripts/verify-traceability.sh \
               scripts/verify-version-bumped.sh scripts/verify-changelog.sh \
               scripts/check-commit-msg.sh scripts/check-memory-size.sh \
               test/run.sh
ACCEPTANCE_TESTS := $(wildcard test/acceptance/test_HC_*.sh)

.PHONY: help tools build cross test test-acceptance lint zig-fmt shell-lint \
        verify-traceability verify-version-bumped verify-changelog \
        verify-index-status \
        check-docs \
        size check install-hooks clean distclean

help:
	@echo "healthy targets:"
	@echo "  tools               install Zig $(ZIG_VERSION) via pipx + check system deps"
	@echo "                        add SUDO=1 to let it run sudo pacman -S for missing pkgs"
	@echo "  build               build $(OUT) (TARGET=$(TARGET), TLS=$(TLS), CA=$(CA))"
	@echo "  cross               build every target in CROSS_TARGETS (build-only, not run)"
	@echo "  test                build + functional suite (test/run.sh, 28 cases)"
	@echo "  test-acceptance     run every test/acceptance/test_HC_*.sh"
	@echo "  lint                shellcheck on *.sh + zig fmt --check hc.zig"
	@echo "  size                print stripped sizes vs. README budget"
	@echo "  verify-traceability enforce story ↔ plan ↔ test ↔ CAP links"
	@echo "  verify-version-bumped  VERSION must differ from origin/main:VERSION (pre-push)"
	@echo "  verify-changelog    CHANGELOG.md must contain '## [v\$$(cat VERSION)]' (pre-push)"
	@echo "  check               lint + build + build (TLS=0) + cross + test + test-acceptance + verify"
	@echo "  install-hooks       install commit-msg + pre-commit + pre-push via pre-commit framework"
	@echo "  clean               rm bin/ hc-* *.o .zig-cache/ zig-out/"
	@echo ""
	@echo "Variables: TARGET=$(TARGET) TLS=$(TLS) CA=$(CA) OUT=$(OUT) ZIG=$(ZIG)"

# `make tools`              — install user-level deps (ziglang $(ZIG_VERSION) +
#                             pre-commit, both via pipx) and verify system deps.
#                             Missing system packages abort with the exact
#                             install command — no sudo surprises.
# `make tools SUDO=1`       — same, but also run `sudo pacman -S --needed <missing>`.
#                             Only Arch/pacman is handled automatically; on
#                             Debian/Fedora install the printed list manually.
tools:
	@echo "→ checking system packages ($(SYSTEM_PKGS))"
	@if ! command -v pacman >/dev/null 2>&1; then \
	  echo "  non-Arch host: install the equivalents of: $(SYSTEM_PKGS)"; \
	  echo "  (Debian: apt install openssl python3 shellcheck pipx)"; \
	  echo "  (Fedora: dnf install openssl python3 ShellCheck pipx)"; \
	else \
	  missing=""; \
	  for p in $(SYSTEM_PKGS); do \
	    pacman -Qi "$$p" >/dev/null 2>&1 || missing="$$missing $$p"; \
	  done; \
	  if [ -n "$$missing" ]; then \
	    echo "  missing:$$missing"; \
	    if [ "$(SUDO)" = 1 ]; then \
	      echo "→ sudo pacman -S --needed$$missing"; \
	      sudo pacman -S --needed $$missing; \
	    else \
	      echo "  install with: sudo pacman -S --needed$$missing"; \
	      echo "  (or re-run: make tools SUDO=1)"; \
	      exit 1; \
	    fi; \
	  else \
	    echo "  all system packages present"; \
	  fi; \
	fi
	@echo "→ ensuring ~/.local/bin on \$$PATH (via pipx ensurepath)"
	@pipx ensurepath >/dev/null 2>&1 || true
	@echo "→ installing ziglang==$(ZIG_VERSION) via pipx (exposes 'python-zig')"
	@venv="$$HOME/.local/share/pipx/venvs/ziglang"; \
	  pz="$$venv/bin/python-zig"; want="$(ZIG_VERSION)"; current=""; \
	  if [ -x "$$pz" ]; then current=$$("$$pz" version 2>/dev/null); fi; \
	  if [ "$$current" = "$$want" ]; then \
	    echo "  ziglang==$$want already installed in pipx venv"; \
	  else \
	    if [ -e "$$venv" ]; then \
	      echo "  installed version is '$$current', replacing with $$want"; \
	      pipx uninstall ziglang >/dev/null 2>&1 || true; \
	    fi; \
	    pipx install "ziglang==$$want"; \
	  fi
	@echo "→ symlinking ~/.local/bin/zig -> python-zig (so plain 'zig' works)"
	@if [ -e "$$HOME/.local/bin/zig" ] && [ ! -L "$$HOME/.local/bin/zig" ]; then \
	    echo "  skip: ~/.local/bin/zig exists as a regular file — remove it manually to let make manage it"; \
	  else \
	    ln -sf "$$HOME/.local/bin/python-zig" "$$HOME/.local/bin/zig"; \
	    echo "  ~/.local/bin/zig -> python-zig"; \
	  fi
	@echo "→ verifying zig is reachable"
	@if command -v zig >/dev/null 2>&1; then \
	    zig version | sed 's/^/  zig version: /'; \
	  elif [ -x "$$HOME/.local/bin/zig" ]; then \
	    echo "  installed at ~/.local/bin/zig but not on \$$PATH in this shell"; \
	    echo "  open a new shell (pipx ensurepath wrote to your shell rc), then re-run"; \
	    exit 1; \
	  else \
	    echo "  FAIL: zig not found after install"; exit 1; \
	  fi
	@echo "→ installing pre-commit via pipx (hook framework)"
	@if command -v pre-commit >/dev/null 2>&1; then \
	  echo "  pre-commit already present ($$(command -v pre-commit))"; \
	else \
	  pipx install pre-commit; \
	fi
	@pre-commit --version | sed 's/^/  /'
	@echo "tools: ok — next run: make install-hooks && make check"

build:
	@TARGET='$(TARGET)' TLS='$(TLS)' CA='$(CA)' OUT='$(OUT)' ZIG='$(ZIG)' scripts/build.sh

cross:
	@set -e; for t in $(CROSS_TARGETS); do \
	  echo "→ build $$t"; \
	  TARGET=$$t TLS=$(TLS) CA='$(CA)' ZIG='$(ZIG)' scripts/build.sh; \
	done

test: build
	@HC='$(HC)' ./test/run.sh

test-acceptance: build
	@if [ -z "$(ACCEPTANCE_TESTS)" ]; then \
	  echo "test-acceptance: no test/acceptance/test_HC_*.sh yet — skipping"; \
	else \
	  for t in $(ACCEPTANCE_TESTS); do \
	    echo "→ $$t"; \
	    HC='$(HC)' sh $$t || exit 1; \
	  done; \
	fi

zig-fmt:
	@echo "→ zig fmt --check"
	@$(ZIG) fmt --check hc.zig

shell-lint:
	@echo "→ shellcheck"
	@# Only check files that actually exist (acceptance dir may be empty).
	@files=""; for f in $(SHELL_FILES) $(ACCEPTANCE_TESTS); do \
	  [ -f "$$f" ] && files="$$files $$f"; \
	done; \
	if [ -n "$$files" ]; then shellcheck --severity=warning $$files; fi

lint: zig-fmt shell-lint

verify-traceability:
	@bash scripts/verify-traceability.sh

verify-version-bumped:
	@bash scripts/verify-version-bumped.sh

verify-changelog:
	@bash scripts/verify-changelog.sh

# SH-056 — INDEX ↔ frontmatter status drift (shepherd ref: PR #59).
# Byte-identical to shepherd/scripts/verify-index-status.sh.
verify-index-status:
	@scripts/verify-index-status.sh

# SH-055 — fleet-wide check-docs wrapper (shepherd ref: PR #58).
# Delegates to healthy's existing docs-drift targets; no new logic.
# SH-056 adds verify-index-status at the front.
check-docs: verify-index-status verify-traceability verify-version-bumped verify-changelog

size: build
	@echo "→ size budget (KB, stripped)"
	@tls_size=$$(stat -c%s $(OUT)); tls_kb=$$(( tls_size / 1024 )); \
	  echo "  $(OUT) TLS=$(TLS):  $$tls_kb KB (budget $(SIZE_BUDGET_X86_64_TLS_KB) KB)"; \
	  if [ "$(TARGET)" = x86_64-linux ] && [ "$(TLS)" = 1 ] && [ $$tls_kb -gt $(SIZE_BUDGET_X86_64_TLS_KB) ]; then \
	    echo "  FAIL: x86_64 TLS build exceeds budget"; exit 1; \
	  fi
	@TARGET=x86_64-linux TLS=0 OUT=bin/hc-x86_64-linux-notls scripts/build.sh >/dev/null
	@notls_size=$$(stat -c%s bin/hc-x86_64-linux-notls); notls_kb=$$(( notls_size / 1024 )); \
	  echo "  x86_64 TLS=0:  $$notls_kb KB (budget $(SIZE_BUDGET_X86_64_NOTLS_KB) KB)"; \
	  rm -f bin/hc-x86_64-linux-notls; \
	  if [ $$notls_kb -gt $(SIZE_BUDGET_X86_64_NOTLS_KB) ]; then \
	    echo "  FAIL: x86_64 TLS=0 build exceeds budget"; exit 1; \
	  fi

check: lint verify-traceability
	@# Build + test on x86_64 with TLS on, then re-build with TLS off.
	@$(MAKE) --no-print-directory build TARGET=x86_64-linux TLS=1
	@$(MAKE) --no-print-directory test  TARGET=x86_64-linux TLS=1
	@$(MAKE) --no-print-directory test-acceptance TARGET=x86_64-linux TLS=1
	@$(MAKE) --no-print-directory build TARGET=x86_64-linux TLS=0 OUT=bin/hc-x86_64-linux-notls
	@rm -f bin/hc-x86_64-linux-notls
	@$(MAKE) --no-print-directory cross
	@echo "check: ok"

install-hooks:
	@command -v pre-commit >/dev/null 2>&1 || { \
	  echo "pre-commit not installed — run 'make tools' first"; exit 1; }
	@# Defensively undo the HC-001 core.hooksPath setting so pre-commit's
	@# "Cowardly refusing to install hooks" path never triggers on upgraders.
	@git config --unset-all core.hooksPath 2>/dev/null || true
	@pre-commit install --hook-type commit-msg --hook-type pre-commit --hook-type pre-push
	@echo "install-hooks: ok (commit-msg + pre-commit + pre-push installed into .git/hooks/)"

clean:
	@rm -rf bin
	@rm -f hc-* hc_* *.o
	@rm -rf .zig-cache zig-out zig-pkg

distclean: clean
	@echo "distclean: ok"

##@ Shepherd dev-cycle contract (SH-014 / SH-019)
#
# Spec: https://github.com/bboortz/shepherd/blob/main/docs/specs/dev-cycle-contract.md
#
# Healthy is the reference implementation of the contract (SH-025 in the
# shepherd umbrella). Dev-cycle doc measured healthy at 3.0 / 3.7 / 1.5 min
# (PR / push / release) — already inside all three budgets. This PR adopts
# the shared target names so new repos can use healthy's Makefile as the
# template.

.PHONY: test-affected smoke release-artifacts \
        ci-branch ci-patch ci-release ci-nightly ci-nightly-body

# Contract entry points. test-affected is diff-aware via SH-037 (shepherd SH-036 pattern);
# smoke + release-artifacts stay as identity/direct aliases.
test-affected: build
	@sh scripts/test-affected.sh
smoke:         test             # exercises the `hc` binary via test-acceptance
release-artifacts: cross        # cross-compiles all targets (ReleaseSmall/ReleaseSafe)

# Tier bodies.
ci-branch:  lint test cross     # 5-min PR gate: lint + test + cross-build of all targets
ci-patch:   smoke                # post-merge smoke (fast)

# ci-release-promote: FF main to dev + tag from VERSION (SH-029).
# Must run on `dev`. Mutates working tree; CI only.
.PHONY: ci-release-promote
ci-release-promote:
	@current=$$(git branch --show-current); \
	 [ "$$current" = "dev" ] || { echo "ci-release-promote must run on 'dev', got '$$current'"; exit 1; }
	@[ -f VERSION ] || { echo "VERSION file missing — cannot determine tag"; exit 1; }
	@version=$$(cat VERSION | tr -d '[:space:]'); \
	 echo "SH-029 promote: dev → main as v$$version"; \
	 git fetch origin main && \
	 git checkout main && \
	 git merge --ff-only origin/dev && \
	 git tag "v$$version" HEAD && \
	 git push origin main && \
	 git push origin "v$$version" && \
	 git checkout dev

ci-release: ci-release-promote
	@echo "ci-release: healthy CD pipeline continues to tag + publish pre-built cross binaries"

ci-nightly: ci-nightly-body
ci-nightly-body: check           # nightly: lint + verify-traceability (healthy's existing full check)

##@ Shepherd fleet-tier hook wrappers (SH-042)
#
# Spec: https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-042-hook-tiers.md
#
# Canonical fleet entry points for git hooks. Repo-native step names stay in
# COMMIT_STEPS / PUSH_STEPS; the wrappers only depend on them. No step
# renames, no step moves — this is purely additive naming.
#
#   hook-commit  ~15s commit-stage gate  (pre-commit)
#   hook-push    ~2m  push-stage gate    (pre-push)

COMMIT_STEPS ?= zig-fmt shell-lint verify-traceability
PUSH_STEPS   ?= check-docs build test verify-version-bumped verify-changelog
BRANCH_STEPS ?= lint check-docs test cross

.PHONY: hook-commit hook-push
hook-commit: $(COMMIT_STEPS)
hook-push:   $(PUSH_STEPS)
