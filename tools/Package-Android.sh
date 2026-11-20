#!/usr/bin/env bash
set -euo pipefail

version_entry="$(sed -n 's/^version: //p' mobile/pubspec.yaml)"
if [[ ! "$version_entry" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)$ ]]; then
  echo "::error::Expected an Android version in MAJOR.MINOR.PATCH+BUILD format."
  exit 1
fi
version="${BASH_REMATCH[1]}"
build="${BASH_REMATCH[2]}"
name="TapMyPC-Android-$version-build$build"
apk="$PWD/mobile/build/app/outputs/flutter-apk/app-release.apk"
tools="$(find "$ANDROID_HOME/build-tools" -name apksigner -print | sort -V | tail -1)"
[[ -x "$tools" ]]
build_tools="$(dirname "$tools")"

badging="$("$build_tools/aapt" dump badging "$apk")"
if ! grep -Fq "package: name='dev.tapmypc.tapmypc_mobile' versionCode='$build' versionName='$version'" <<< "$badging"; then
  echo "::error::APK package name or version differs from the project metadata."
  exit 1
fi
signatures="$("$build_tools/apksigner" verify --print-certs-pem "$apk")"
actual_signers="$(printf '%s\n' "$signatures" | python3 -c '
import hashlib
import re
import ssl
import sys

certificates = re.findall(r"-----BEGIN CERTIFICATE-----\s+[\s\S]*?-----END CERTIFICATE-----", sys.stdin.read())
fingerprints = {hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert)).hexdigest() for cert in certificates}
print("\n".join(sorted(fingerprints)))
')"
if [[ "$actual_signers" != "$ANDROID_SIGNER_SHA256" ]]; then
  echo "::error::APK signer does not match the selected keystore. Expected $ANDROID_SIGNER_SHA256. Found: $actual_signers"
  exit 1
fi
unzip -tq "$apk"
unzip -p "$apk" lib/arm64-v8a/libapp.so > /dev/null

# Apply the patch outside the repository so git apply processes upstream paths.
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
repo="$PWD"
patch="$repo/mobile/novnc-stream-settings.patch"
npm install --prefix "$work" --no-audit --no-fund --no-save --package-lock=false \
  '@novnc/novnc@1.7.0' 'esbuild@0.28.0'
mv "$work/node_modules/@novnc/novnc" "$work/noVNC"
(
  cd "$work/noVNC"
  git apply --unidiff-zero "$patch"
  "$work/node_modules/.bin/esbuild" core/rfb.js --bundle --format=esm --target=es2022 \
    --minify --outfile="$work/novnc.js"
)
cmp "$work/novnc.js" mobile/android/app/src/main/assets/remote-desktop/novnc.js
unzip -p "$apk" assets/remote-desktop/novnc.js | cmp "$work/novnc.js" -

mkdir -p dist
cp "$apk" "dist/$name.apk"
cp LICENSE "dist/$name-LICENSE.txt"
cp "$patch" "$work/"
cat > "$work/BUILD.txt" <<'SOURCE'
This is the corresponding noVNC source for the TapMyPC Android APK.
The patch is already applied. License and authorship notices are in noVNC/.

From the noVNC directory, run:
npx --yes --package=esbuild@0.28.0 esbuild core/rfb.js --bundle --format=esm --target=es2022 --minify --outfile=../novnc.js
SOURCE
(
  cd "$work"
  zip -qr "$repo/dist/$name-noVNC-source.zip" noVNC novnc-stream-settings.patch BUILD.txt
)
unzip -tq "dist/$name-noVNC-source.zip"
printf 'release_tag=android-v%s+%s\n' "$version" "$build" >> "$GITHUB_OUTPUT"
printf 'Packaged Android %s (build %s), and verified its APK signer and noVNC source.\n' "$version" "$build"
