#!/bin/bash
# 墨读 - 启动脚本
# 用法: ./run.sh [debug|release]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

MODE="${1:-release}"

if [ "$MODE" = "debug" ]; then
    echo "🚀 启动 Debug 模式..."
    swift run
else
    APP_NAME="墨读"
    APP_BUNDLE="/Applications/${APP_NAME}.app"

    if [ -d "$APP_BUNDLE" ]; then
        echo "🚀 启动 ${APP_NAME}..."
        open "$APP_BUNDLE"
    else
        echo "⚙️  构建并启动..."
        swift build -c release || exit 1
        mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
        cp ".build/release/${APP_NAME}" "$APP_BUNDLE/Contents/MacOS/"
        cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/" 2>/dev/null
        cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.openclaw.modu</string>
    <key>CFBundleVersion</key>
    <string>1.0.10</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.10</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>${APP_NAME} © 2026 浙江嘉瑞成律师事务所 · 金莉珊律师</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown 文档</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>public.plain-text</string>
            </array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>net.daringfireball.markdown</string>
            <key>UTTypeDescription</key>
            <string>Markdown 文档</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.plain-text</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>md</string>
                    <string>markdown</string>
                    <string>mdown</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>text/markdown</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST
        codesign --force --sign - "$APP_BUNDLE"
        open "$APP_BUNDLE"
    fi
fi
