# Aether - Cross-Platform Build Makefile
# Usage: make <target>
# See doc/CONTRIBUTING.md for details

.PHONY: help

help: ## Show available targets
	@echo "Aether Cross-Platform Build System"
	@echo ""
	@echo "Apple (iOS/macOS/Watch/Widget):"
	@echo "  make build-ios        Build iOS (simulator)"
	@echo "  make build-macos      Build macOS"
	@echo "  make build-watch      Build watchOS (simulator)"
	@echo "  make build-widget     Build Widget Extension (simulator)"
	@echo "  make test-ios         Run iOS UT + UIT"
	@echo "  make test-macos       Run macOS UT"
	@echo "  make test-unit        Run iOS UT only"
	@echo "  make run-ios          Build and launch iOS simulator"
	@echo ""
	@echo "Android:"
	@echo "  make build-android        Build debug APK"
	@echo "  make build-android-release Build release APK"
	@echo "  make test-android         Run Android tests"
	@echo ""
	@echo "Windows:"
	@echo "  make build-windows     Build Windows (requires pwsh on PATH)"
	@echo "  make publish-windows   Publish Windows (self-contained)"
	@echo "  make test-windows      Run Windows tests"
	@echo ""
	@echo "Rust:"
	@echo "  make build-rust-apple  Build Rust xcframework (Apple)"
	@echo "  make build-rust-wasm    Build Rust WASM"
	@echo "  make test-rust          Run Rust tests + fmt + clippy"
	@echo ""
	@echo "General:"
	@echo "  make clean             Clean build artifacts"
	@echo "  make all               Build Apple + Android"

# ============================================================
# Apple (iOS / macOS / Watch / Widget)
# ============================================================

.PHONY: build-ios build-macos build-watch build-widget test-ios test-macos test-unit run-ios

build-ios:
	@./scripts/build.sh build-ios

build-macos:
	@./scripts/build.sh build-macos

build-watch:
	@./scripts/build.sh build-watch

build-widget:
	@./scripts/build.sh build-widget

test-ios:
	@./scripts/build.sh test-ios

test-macos:
	@./scripts/build.sh test-macos

test-unit:
	@./scripts/build.sh test-unit

run-ios:
	@./scripts/build.sh run-ios

# ============================================================
# Android
# ============================================================

.PHONY: build-android build-android-release test-android

build-android:
	@./scripts/build-android.sh build-android

build-android-release:
	@./scripts/build-android.sh build-android-release

test-android:
	@./scripts/build-android.sh test-android

# ============================================================
# Windows
# ============================================================

.PHONY: build-windows publish-windows test-windows

build-windows:
	@pwsh -NoProfile -File scripts/build-windows.ps1 -Command build

publish-windows:
	@pwsh -NoProfile -File scripts/build-windows.ps1 -Command publish

test-windows:
	@pwsh -NoProfile -File scripts/build-windows.ps1 -Command test

# ============================================================
# Rust Core
# ============================================================

.PHONY: build-rust-apple build-rust-wasm test-rust

build-rust-apple:
	@cd rust && ./scripts/build-apple.sh

build-rust-wasm:
	@cd rust && ./scripts/build-wasm.sh

test-rust:
	@cd rust && cargo test -p aether-core && cargo fmt --all -- --check && cargo clippy --all-targets -- -D warnings

# ============================================================
# General
# ============================================================

.PHONY: clean all

clean:
	@./scripts/build.sh clean
	@rm -rf build/

all: build-ios build-macos build-android
	@echo "All platform builds completed."
