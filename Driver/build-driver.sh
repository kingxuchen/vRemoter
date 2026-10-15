#!/bin/zsh
set -euo pipefail

SOURCE_DRIVER="/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DRIVER="$BUILD_DIR/vRemoteDriver.driver"
EXECUTABLE="$OUTPUT_DRIVER/Contents/MacOS/BlackHole"
PLIST="$OUTPUT_DRIVER/Contents/Info.plist"

if [[ ! -d "$SOURCE_DRIVER" ]]; then
  print -u2 "Missing source driver: $SOURCE_DRIVER"
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
ditto "$SOURCE_DRIVER" "$OUTPUT_DRIVER"
rm -rf "$OUTPUT_DRIVER/Contents/_CodeSignature"

# Keep every binary replacement exactly the same byte length. This lets the
# proof of concept reuse the installed universal BlackHole binary without Xcode.
perl -0777 -pi -e '
  my $x86TransportSeen = 0;
  my $armTransportSeen = 0;
  s/audio\.existential\.BlackHole2ch/audio.local.vRemoteDriver2chXX/g;
  s/BlackHole%ich_UID/vRemoteDr%ich_UID/g;
  s/BlackHole%ich_2_UID/vRemoteDr%ich_2_UID/g;
  s/BlackHole%ich_ModelUID/vRemoteDr%ich_ModelUID/g;
  s/BlackHole Box/vRemoteDr Box/g;
  s/BlackHole %ich/vRemoteDr %ich/g;
  s/triv/(++$x86TransportSeen == 2) ? " bsu" : "triv"/ge;
  s/(\x88\x4e\x8e\x52\x28\xcd\xae\x72)/
    (++$armTransportSeen == 2)
      ? "\x08\x44\x8c\x52\x68\xae\xae\x72"
      : $1
  /gex;
' "$EXECUTABLE"

# The factory UUID is chosen by BlackHole's own release and changes between
# versions, so read it from the driver that is actually installed instead of
# hardcoding one. A pinned UUID builds fine against the version it was written
# for and then fails on every other machine.
SOURCE_FACTORY=$(plutil -convert json -o - "$PLIST" | python3 -c '
import json, sys
print(next(iter(json.load(sys.stdin)["CFPlugInFactories"])))
')
TARGET_FACTORY="B7C4C615-9E72-4C83-A329-71C4E50E4A91"
AUDIO_TYPE="443ABAB8-E7B3-491A-B985-BEB9187030DB"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier audio.local.vRemoteDriver2chXX" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName vRemote Driver" "$PLIST"

if [[ "$SOURCE_FACTORY" != "$TARGET_FACTORY" ]]; then
  /usr/libexec/PlistBuddy -c "Delete :CFPlugInFactories:$SOURCE_FACTORY" "$PLIST" \
    || print "note: no factory $SOURCE_FACTORY to replace"
  /usr/libexec/PlistBuddy -c "Delete :CFPlugInTypes:$AUDIO_TYPE:0" "$PLIST" \
    || print "note: no type entry $AUDIO_TYPE:0 to replace"
  /usr/libexec/PlistBuddy \
    -c "Add :CFPlugInFactories:$TARGET_FACTORY string BlackHole_Create" "$PLIST"
  /usr/libexec/PlistBuddy \
    -c "Add :CFPlugInTypes:$AUDIO_TYPE:0 string $TARGET_FACTORY" "$PLIST"
fi

codesign --force --deep --sign - --timestamp=none "$OUTPUT_DRIVER"

print "Built: $OUTPUT_DRIVER"
print "Bundle ID: $(defaults read "$PLIST" CFBundleIdentifier)"
print "Factory UUID: $TARGET_FACTORY (was $SOURCE_FACTORY)"
print "Architectures: $(lipo -archs "$EXECUTABLE")"
codesign --verify --deep --strict --verbose=2 "$OUTPUT_DRIVER"
