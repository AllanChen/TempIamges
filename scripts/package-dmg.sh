#!/bin/bash
set -e

VERSION="1.0.0-beta.1"
APP_NAME="Glance"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
VOL_NAME="${APP_NAME} ${VERSION}"

echo "Building ${DMG_NAME}..."

# 确保 .app 存在
if [ ! -d "Glance.app" ]; then
    echo "Error: Glance.app not found in current directory"
    exit 1
fi

# 清理旧文件
rm -f "${DMG_NAME}"

# 方法1: 使用 create-dmg（如果有的话）
if command -v create-dmg > /dev/null 2>&1; then
    echo "Using create-dmg..."
    create-dmg \
        --volname "${VOL_NAME}" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --app-drop-link 450 185 \
        "${DMG_NAME}" \
        "Glance.app"
else
    # 方法2: 使用 hdiutil（无需额外安装）
    echo "create-dmg not found, using hdiutil..."
    
    # 创建临时目录
    TMP_DIR=$(mktemp -d)
    cp -R "Glance.app" "${TMP_DIR}/"
    
    # 创建 Applications 链接
    ln -s /Applications "${TMP_DIR}/Applications"
    
    # 打包成 DMG
    hdiutil create \
        -volname "${VOL_NAME}" \
        -srcfolder "${TMP_DIR}" \
        -ov \
        -format UDZO \
        "${DMG_NAME}"
    
    # 清理临时目录
    rm -rf "${TMP_DIR}"
fi

echo ""
echo "✅ DMG created: ${DMG_NAME}"
ls -lh "${DMG_NAME}"

# 计算 sha256
echo ""
echo "sha256:"
shasum -a 256 "${DMG_NAME}"
