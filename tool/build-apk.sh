#!/usr/bin/env bash
# The only way to build an APK of the wallet. Every build carries version, build number and commit.
#   tool/build-apk.sh          release: clean tree, on main, HEAD == origin/main. Builds and STOPS before signing:
#                              the result is dist/*.unsigned.apk, which is NOT installable as a release. The owner signs it
#                              with the YubiKey: tool/sign-apk-yubikey.sh dist/<that file>   (PIN + touch, interactive)
#   tool/build-apk.sh --test   test build of the current branch, signed with the throwaway TEST key (never a release)
# Output: dist/ibirapay-wallet-<version>-<channel>.<sha>+<build>.apk  (release: ...apk.unsigned.apk, then signed .apk)
set -euo pipefail
cd "$(dirname "$0")/.."
FLUTTER=${FLUTTER:-$HOME/opt/mobile/flutter/bin/flutter}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/opt/mobile/android-sdk}
export JAVA_HOME=${JAVA_HOME:-$HOME/opt/mobile/jdk}
export PATH="$JAVA_HOME/bin:$HOME/.cargo/bin:$PATH"
APKSIGNER=$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)
die() { echo "build-apk: $*" >&2; exit 1; }

mode=${1:-release}
[[ -z $(git status --porcelain) ]] || die "uncommitted changes: an APK must match one commit"
branch=$(git rev-parse --abbrev-ref HEAD)
sha=$(git rev-parse --short=7 HEAD)
version=$(sed -n 's/^version: \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' pubspec.yaml)
[[ -n $version ]] || die "pubspec.yaml has no 'version: X.Y.Z'"

case $mode in
  release)
    [[ $branch == main ]] || die "release only from main (you are on $branch); use --test"
    git fetch -q origin
    [[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || die "main differs from origin/main"
    channel=main
    ;;
  --test) channel=test-${branch//\//-} ;;
  *) die "usage: tool/build-apk.sh [--test]" ;;
esac

# the build number counts commits on this branch (origin/main once the remote exists)
ref=HEAD; git rev-parse -q --verify origin/main >/dev/null && ref=origin/main
build=$(git rev-list --count "$ref")
name="$version-$channel.$sha"

# A release build is harder to read back into source: Dart symbol names go (--obfuscate), kept privately in
# debug-info/ (gitignored, not shipped) so a real crash report can still be mapped back with `flutter symbolize`.
# A --test build skips this: it is never the artifact to reverse, and keeping symbols makes test crashes readable.
obfuscate=(); [[ $mode == release ]] && obfuscate=(--obfuscate --split-debug-info="debug-info/$name")
"$FLUTTER" build apk --release --target-platform android-arm,android-arm64 --build-name="$name" --build-number="$build" \
  --dart-define=APP_VERSION="$version" --dart-define=APP_COMMIT="$sha" --dart-define=APP_CHANNEL="$channel" "${obfuscate[@]}"

mkdir -p dist
out="dist/ibirapay-wallet-$name+$build.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$out"

if [[ $mode == --test ]]; then
  ks=$HOME/.config/ibirapay-wallet/test-keystore.p12
  [[ -f $ks ]] || die "missing $ks (throwaway test key)"
  "$APKSIGNER" sign --ks "$ks" --ks-pass file:"$HOME/.config/ibirapay-wallet/test-keystore.pass" "$out"
else
  # The release key lives in the YubiKey and the PIN/touch are the owner's: this script never signs a release.
  # Flutter's gradle output carries the debug signature; rename so it cannot be mistaken for a release.
  mv "$out" "$out.unsigned.apk"
  echo "built (NOT signed for release): $out.unsigned.apk"
  echo "sign it, in your own terminal:  tool/sign-apk-yubikey.sh $out.unsigned.apk"
  exit 0
fi
"$APKSIGNER" verify --print-certs "$out" | head -3
echo "$out"
