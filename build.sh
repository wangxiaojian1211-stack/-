#!/bin/bash
# Build script for 系统状态监视器 (System Monitor)
# Creates macOS app bundle and DMG installer

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="系统状态监视器"
BUNDLE_DIR="$SCRIPT_DIR/build/${APP_NAME}.app"
DMG_PATH="$SCRIPT_DIR/build/SystemMonitor.dmg"
EXECUTABLE_NAME="SystemMonitor"
SOURCES_DIR="$SCRIPT_DIR/Sources"
RESOURCES_DIR="$SCRIPT_DIR/Resources"

echo "============================================"
echo "  系统状态监视器 - 构建脚本"
echo "============================================"
echo ""

# ---- Clean ----
rm -rf "$SCRIPT_DIR/build"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

# ---- Copy Info.plist ----
cp "$RESOURCES_DIR/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
find "$RESOURCES_DIR" -maxdepth 1 -type f -name "*.icns" -exec cp {} "$BUNDLE_DIR/Contents/Resources/" \;

# ---- Find sources ----
SWIFT_FILES=$(find "$SOURCES_DIR" -name "*.swift" | sort)
SWIFT_FILE_ARGS=()
while IFS= read -r f; do
    SWIFT_FILE_ARGS+=("$f")
done <<< "$SWIFT_FILES"
echo "源文件:"
echo "$SWIFT_FILES" | while read f; do echo "  $f"; done

# ---- Compile ----
echo ""
echo "[1/3] 编译中..."
UNIVERSAL_TMP="$SCRIPT_DIR/build/universal"
mkdir -p "$UNIVERSAL_TMP"

if swiftc -target x86_64-apple-macos12.0 \
        -o "$UNIVERSAL_TMP/${EXECUTABLE_NAME}-x86_64" \
        -framework AppKit \
        -framework Foundation \
        -framework IOKit \
        "${SWIFT_FILE_ARGS[@]}" 2>&1 && \
   swiftc -target arm64-apple-macos12.0 \
        -o "$UNIVERSAL_TMP/${EXECUTABLE_NAME}-arm64" \
        -framework AppKit \
        -framework Foundation \
        -framework IOKit \
        "${SWIFT_FILE_ARGS[@]}" 2>&1 && \
   lipo -create \
        "$UNIVERSAL_TMP/${EXECUTABLE_NAME}-x86_64" \
        "$UNIVERSAL_TMP/${EXECUTABLE_NAME}-arm64" \
        -output "$BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"; then
    echo "  ✓ Universal 2 编译完成"
else
    echo "  ! Universal 2 编译失败，退回当前架构编译"
    swiftc \
        -o "$BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME" \
        -framework AppKit \
        -framework Foundation \
        -framework IOKit \
        "${SWIFT_FILE_ARGS[@]}" 2>&1
fi

rm -rf "$UNIVERSAL_TMP"

chmod +x "$BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME"
echo "  ✓ 编译完成 ($(du -h "$BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME" | cut -f1), $(file "$BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_NAME" | cut -d: -f2- | xargs))"

# ---- Create DMG ----
echo ""
echo "[2/3] 创建 DMG 安装镜像..."

DMG_STAGING="/tmp/dmg_staging_$$"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$BUNDLE_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_PATH"

# Create blank image, mount, copy, convert to compressed
TEMP_DMG="/tmp/temp_rw_$$.dmg"
MOUNT_POINT="/tmp/systemmonitor_dmg_mount_$$"
hdiutil create -volname "SystemMonitor" -size 15m -layout NONE -fs "HFS+" -type UDIF "$TEMP_DMG" > /dev/null 2>&1

mkdir -p "$MOUNT_POINT"
hdiutil attach -nobrowse -noautoopen -mountpoint "$MOUNT_POINT" "$TEMP_DMG" > /dev/null 2>&1

cp -R "$DMG_STAGING/系统状态监视器.app" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"

hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1

hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" > /dev/null 2>&1

# Cleanup
rm -f "$TEMP_DMG"
rm -rf "$DMG_STAGING"
rm -rf "$MOUNT_POINT"

echo "  ✓ DMG 创建完成 ($(du -h "$DMG_PATH" | cut -f1))"

# ---- Done ----
echo ""
echo "============================================"
echo "  构建完成！"
echo "============================================"
echo ""
echo "  App:   $BUNDLE_DIR"
echo "  DMG:   $DMG_PATH"
echo ""
echo "  运行 App:"
echo "    open \"$BUNDLE_DIR\""
echo ""
echo "  安装: 双击 DMG 文件，将 App 拖入"
echo "        Applications 文件夹即可"
echo ""
