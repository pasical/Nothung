#!/bin/zsh

# Development-only fallback for machines that have Command Line Tools but no
# full Xcode installation. This validates the critical cleaning path and builds
# an ad-hoc Mac Catalyst app from the same SwiftUI sources as the iOS target.
# It is not an iOS Simulator, Action Extension, Archive, or distribution check.

set -euo pipefail

launch_app=false
case "${1:-}" in
  ""|--no-launch)
    ;;
  --launch)
    launch_app=true
    ;;
  *)
    print -u2 "Usage: $0 [--launch|--no-launch]"
    exit 64
    ;;
esac

script_path=${0:A}
script_dir=${script_path:h}
project_root=${script_dir:h}
build_root=$(mktemp -d "${TMPDIR:-/tmp}/nothung-dev.XXXXXX")
module_cache="$build_root/ModuleCache"
modules_dir="$build_root/Modules"
objects_dir="$build_root/Objects"
app_bundle="$build_root/NothungDev.app"
app_executable="$app_bundle/Contents/MacOS/NothungDev"

mkdir -p \
  "$module_cache" \
  "$modules_dir" \
  "$objects_dir" \
  "$app_bundle/Contents/MacOS" \
  "$app_bundle/Contents/Resources"

swiftc_path=$(xcrun --find swiftc)
architecture=$(uname -m)
case "$architecture" in
  arm64|x86_64)
    ;;
  *)
    print -u2 "Unsupported development architecture: $architecture"
    exit 1
    ;;
esac

catalyst_minimum=17.0
catalyst_target="$architecture-apple-ios${catalyst_minimum}-macabi"
probe_source="$build_root/SDKProbe.swift"
print 'import SwiftUI' > "$probe_source"

typeset -a sdk_candidates
if [[ -n "${NOTHUNG_SDK_PATH:-}" ]]; then
  sdk_candidates+=("$NOTHUNG_SDK_PATH")
fi

active_sdk=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
if [[ -n "$active_sdk" ]]; then
  sdk_candidates+=("$active_sdk")
fi

# The CLT bundle can contain an active SDK whose Swift interfaces are slightly
# newer than the compiler. Prefer a known older fallback before probing the rest.
known_fallback=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
if [[ -d "$known_fallback" ]]; then
  sdk_candidates+=("$known_fallback")
fi

for candidate in /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk(N); do
  sdk_candidates+=("$candidate")
done

sdk_path=""
integer probe_index=0
for candidate in "${sdk_candidates[@]}"; do
  (( probe_index += 1 ))
  frameworks="$candidate/System/iOSSupport/System/Library/Frameworks"
  if [[ ! -d "$frameworks" ]]; then
    continue
  fi

  probe_cache="$build_root/SDKProbeCache-$probe_index"
  mkdir -p "$probe_cache"
  if "$swiftc_path" \
      -sdk "$candidate" \
      -target "$catalyst_target" \
      -module-cache-path "$probe_cache" \
      -Fsystem "$frameworks" \
      -typecheck "$probe_source" \
      >/dev/null 2>&1; then
    sdk_path="$candidate"
    break
  fi
done

if [[ -z "$sdk_path" ]]; then
  print -u2 "No installed macOS SDK can type-check SwiftUI for Mac Catalyst."
  print -u2 "Install a matching Xcode/Command Line Tools pair, or set NOTHUNG_SDK_PATH."
  exit 1
fi

frameworks="$sdk_path/System/iOSSupport/System/Library/Frameworks"
ios_support_swift="$sdk_path/System/iOSSupport/usr/lib/swift"
sdk_settings="$sdk_path/SDKSettings.plist"
catalyst_sdk=$(plutil -extract SupportedTargets.iosmac.DefaultDeploymentTarget raw -o - "$sdk_settings")

print "Using SDK: $sdk_path"
print "Build workspace: $build_root"

core_source="$project_root/Packages/NothungCore/Sources/NothungCore/NothungCleaner.swift"
validation_source="$project_root/Packages/NothungCore/Validation/main.swift"
validation_binary="$build_root/NothungCoreValidation"

"$swiftc_path" \
  -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  "$core_source" \
  "$validation_source" \
  -o "$validation_binary"
"$validation_binary"

core_module="$modules_dir/NothungCore.swiftmodule"
core_object="$objects_dir/NothungCore.o"
"$swiftc_path" \
  -sdk "$sdk_path" \
  -target "$catalyst_target" \
  -module-cache-path "$module_cache" \
  -Fsystem "$frameworks" \
  -parse-as-library \
  -module-name NothungCore \
  -emit-module \
  -emit-module-path "$core_module" \
  -emit-object \
  "$core_source" \
  -o "$core_object"

"$swiftc_path" \
  -sdk "$sdk_path" \
  -target "$catalyst_target" \
  -module-cache-path "$module_cache" \
  -Fsystem "$frameworks" \
  -I "$ios_support_swift" \
  -L "$ios_support_swift" \
  -I "$modules_dir" \
  -parse-as-library \
  -module-name NothungDev \
  -emit-executable \
  "$project_root/iOS/Shared/NothungTheme.swift" \
  "$project_root/iOS/Shared/NothungMark.swift" \
  "$project_root/iOS/Shared/NothungCleaning.swift" \
  "$project_root/iOS/NothungApp/RedirectResolver.swift" \
  "$project_root/iOS/NothungApp/CleanerViewModel.swift" \
  "$project_root/iOS/NothungApp/ContentView.swift" \
  "$project_root/iOS/NothungApp/NothungApp.swift" \
  "$core_object" \
  -Xlinker -platform_version \
  -Xlinker mac-catalyst \
  -Xlinker "$catalyst_minimum" \
  -Xlinker "$catalyst_sdk" \
  -o "$app_executable"

info_plist="$app_bundle/Contents/Info.plist"
cp "$project_root/iOS/NothungApp/Info.plist" "$info_plist"
plutil -replace CFBundleDevelopmentRegion -string zh-Hans "$info_plist"
plutil -replace CFBundleExecutable -string NothungDev "$info_plist"
plutil -replace CFBundleIdentifier -string dev.nothung.local "$info_plist"
plutil -replace CFBundleName -string NothungDev "$info_plist"
plutil -replace CFBundlePackageType -string APPL "$info_plist"
plutil -replace CFBundleShortVersionString -string 0.1.0 "$info_plist"
plutil -replace CFBundleVersion -string 1 "$info_plist"
plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' "$info_plist"
plutil -insert LSMinimumSystemVersion -string 14.0 "$info_plist"
cp "$project_root/iOS/NothungApp/PrivacyInfo.xcprivacy" \
  "$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy"

plutil -lint "$info_plist"
codesign --force --sign - --timestamp=none "$app_bundle"
codesign --verify --deep --strict --verbose=2 "$app_bundle"

build_info=$(xcrun vtool -show-build "$app_executable")
linked_libraries=$(otool -L "$app_executable")
if [[ "$build_info" != *"platform MACCATALYST"* || \
      "$build_info" != *"minos $catalyst_minimum"* ]]; then
  print -u2 "$build_info"
  print -u2 "Unexpected Mach-O platform metadata."
  exit 1
fi
if [[ "$linked_libraries" != *"/System/iOSSupport/System/Library/Frameworks/UIKit.framework"* || \
      "$linked_libraries" != *"/System/iOSSupport/System/Library/Frameworks/SwiftUI.framework"* ]]; then
  print -u2 "$linked_libraries"
  print -u2 "The app did not link the expected Catalyst UI frameworks."
  exit 1
fi

print "Development validation passed."
print "App: $app_bundle"
print "Platform: Mac Catalyst $catalyst_minimum (SDK $catalyst_sdk)"

if $launch_app; then
  open "$app_bundle"
  print "Launch requested."
else
  print "Run again with --launch to open the temporary app."
fi
