#!/usr/bin/env bash
#
# build-aether-sdk-xcframework.sh
#
# Builds AetherSDK as an XCFramework with three slices:
#   - ios-arm64           (iOS device)
#   - ios-arm64-simulator (iOS Simulator)
#   - macos-arm64         (macOS)
#
# Usage:
#   ./scripts/build-aether-sdk-xcframework.sh [output-dir]
#
# Requirements:
#   - Xcode 15+ (this script does NOT work with Command Line Tools alone)
#   - swift-tools-version 5.9+
#
# Output:
#   AetherSDK.xcframework in the specified output directory (default: build/)

set -euo pipefail

# Configuration
PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)/Packages/AetherCore"
OUTPUT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/build}"
PRODUCT_NAME="AetherSDK"
DERIVED_DATA="$(mktemp -d)"

echo "==> Package directory: $PACKAGE_DIR"
echo "==> Output directory: $OUTPUT_DIR"
echo "==> DerivedData: $DERIVED_DATA"

# Verify Xcode is available
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild not found. Install Xcode 15+ to build XCFramework."
    exit 1
fi

# Step 1: Archive for each platform
ARCHIVES=()
SLICES=()

build_archive() {
    local platform="$1"
    local archive_name="$2"
    local destination="$3"
    local archive_path="$DERIVED_DATA/${archive_name}.xcarchive"

    echo ""
    echo "==> Building $archive_name ($platform)"
    xcrun xcodebuild archive \
        -workspace "$PACKAGE_DIR/Package.swift" \
        -scheme "$PRODUCT_NAME" \
        -destination "$destination" \
        -archivePath "$archive_path" \
        -derivedDataPath "$DERIVED_DATA" \
        -skipPackagePluginValidation \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        2>&1 | tail -20

    if [ ! -d "$archive_path" ]; then
        echo "error: Archive for $archive_name failed"
        exit 1
    fi

    ARCHIVES+=("$archive_path")
    SLICES+=("-$archive_name")
}

# iOS device (arm64)
build_archive "iOS Device" "ios-arm64" "generic/platform=iOS"

# iOS Simulator (arm64)
build_archive "iOS Simulator" "ios-arm64-simulator" "generic/platform=iOS Simulator"

# macOS (arm64)
build_archive "macOS" "macos-arm64" "generic/platform=macOS"

# Step 2: Create XCFramework
XCFRAMEWORK_PATH="$OUTPUT_DIR/${PRODUCT_NAME}.xcframework"
rm -rf "$XCFRAMEWORK_PATH"
mkdir -p "$OUTPUT_DIR"

echo ""
echo "==> Creating XCFramework at $XCFRAMEWORK_PATH"

XCFRAMEWORK_ARGS=()
for archive in "${ARCHIVES[@]}"; do
    XCFRAMEWORK_ARGS+=("-archive" "$archive" "-framework" "$PRODUCT_NAME")
done

xcrun xcodebuild -createXCFramework \
    "${XCFRAMEWORK_ARGS[@]}" \
    -output "$XCFRAMEWORK_PATH" \
    2>&1 | tail -20

# Step 3: Verify slices
echo ""
echo "==> XCFramework slices:"
find "$XCFRAMEWORK_PATH" -maxdepth 1 -type d -name "*.xcframework" -prune -o -name "*.framework" -print | sort

echo ""
echo "==> Done. XCFramework: $XCFRAMEWORK_PATH"

# Cleanup
rm -rf "$DERIVED_DATA"
