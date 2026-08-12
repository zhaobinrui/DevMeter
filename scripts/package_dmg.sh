#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_ROOT="${SCRIPT_DIR:h}"
readonly PROJECT_PATH="${PROJECT_ROOT}/CodexMeter.xcodeproj"
readonly SCHEME="CodexMeter"
readonly OUTPUT_DIR="${CODEXMETER_OUTPUT_DIR:-${PROJECT_ROOT}/dist}"
readonly SIGN_IDENTITY="${CODEXMETER_SIGN_IDENTITY:--}"

for tool in xcodebuild codesign hdiutil ditto plutil; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        print -u2 "缺少打包工具：${tool}"
        exit 1
    fi
done

work_dir="$(mktemp -d "${TMPDIR%/}/CodexMeter-package.XXXXXX")"
cleanup() {
    if [[ -n "${work_dir:-}" && -d "${work_dir}" ]]; then
        rm -rf -- "${work_dir}"
    fi
}
trap cleanup EXIT INT TERM

readonly DERIVED_DATA="${work_dir}/DerivedData"
readonly STAGING_DIR="${work_dir}/staging"
readonly STAGED_APP="${STAGING_DIR}/CodexMeter.app"
readonly DMG_SOURCE_DIR="${work_dir}/dmg"

print "[1/5] 构建 CodexMeter Release…"
xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    build

readonly BUILT_APP="${DERIVED_DATA}/Build/Products/Release/CodexMeter.app"
if [[ ! -d "${BUILT_APP}" ]]; then
    print -u2 "未找到构建产物：${BUILT_APP}"
    exit 1
fi

print "[2/5] 准备并签名应用…"
mkdir -p "${STAGING_DIR}"
ditto "${BUILT_APP}" "${STAGED_APP}"

# 先递归签署 Sparkle 等嵌套代码，再为 Widget 和主应用恢复各自 entitlement。
codesign \
    --force \
    --deep \
    --sign "${SIGN_IDENTITY}" \
    --options runtime \
    --timestamp=none \
    "${STAGED_APP}"

widget_path="${STAGED_APP}/Contents/PlugIns/CodexMeterWidget.appex"
if [[ -d "${widget_path}" ]]; then
    codesign \
        --force \
        --sign "${SIGN_IDENTITY}" \
        --options runtime \
        --timestamp=none \
        --entitlements "${PROJECT_ROOT}/CodexMeterWidget/CodexMeterWidget.entitlements" \
        "${widget_path}"
fi

codesign \
    --force \
    --sign "${SIGN_IDENTITY}" \
    --options runtime \
    --timestamp=none \
    --entitlements "${PROJECT_ROOT}/CodexMeter/CodexMeter.entitlements" \
    "${STAGED_APP}"

codesign --verify --deep --strict --verbose=2 "${STAGED_APP}"

version="$(plutil -extract CFBundleShortVersionString raw "${STAGED_APP}/Contents/Info.plist")"
if [[ -z "${version}" ]]; then
    print -u2 "无法从应用读取版本号"
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"
readonly DMG_PATH="${OUTPUT_DIR}/CodexMeter-${version}.dmg"

print "[3/5] 创建安装盘内容…"
mkdir -p "${DMG_SOURCE_DIR}"
ditto "${STAGED_APP}" "${DMG_SOURCE_DIR}/CodexMeter.app"
ln -s /Applications "${DMG_SOURCE_DIR}/Applications"

print "[4/5] 生成 DMG…"
hdiutil create \
    -volname "CodexMeter ${version}" \
    -srcfolder "${DMG_SOURCE_DIR}" \
    -format UDZO \
    -ov \
    "${DMG_PATH}"

print "[5/5] 验证 DMG…"
hdiutil verify "${DMG_PATH}"

print
print "打包完成：${DMG_PATH}"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    print "签名方式：ad-hoc（适合这台 Mac 上个人安装，不适合公开分发）"
else
    print "签名方式：${SIGN_IDENTITY}"
fi
