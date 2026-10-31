#!/bin/bash
# Installs the macOS trackpad fixes into ONLYOFFICE.app:
#   - smooth pinch-to-zoom (rebuilt editor UI files in web-apps/)
#   - smooth scrolling (patches in sdkjs/*.diff, applied to the app's own sdk-all.js)
#
#   ./install.sh                     install into /Applications/ONLYOFFICE.app
#   ./install.sh /path/to/ONLYOFFICE.app
#   ./install.sh --restore           put the original files back
#   ./install.sh --force             skip the version check
#
# Originals are backed up to ~/Library/Application Support/ONLYOFFICE-pinch-fix-backup/<version>.
# After copying, the app is re-signed ad hoc so macOS still opens it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/ONLYOFFICE.app"
FORCE=0
RESTORE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        --restore) RESTORE=1 ;;
        *.app|*.app/) APP="${arg%/}" ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

WEB="$APP/Contents/Resources/editors/web-apps"
SDK="$APP/Contents/Resources/editors/sdkjs"
SDK_PRODUCTS="word cell slide visio"
[ -d "$WEB" ] || { echo "Can't find the editor files in $APP (expected $WEB)."; exit 1; }

if pgrep -f "$APP/Contents/MacOS" >/dev/null 2>&1; then
    echo "Please quit ONLYOFFICE first."; exit 1
fi

INSTALLED="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
BACKUP="$HOME/Library/Application Support/ONLYOFFICE-pinch-fix-backup/$INSTALLED"

SUDO=""
[ -w "$WEB" ] || SUDO="sudo"

resign() {
    echo "Re-signing $APP (ad hoc)..."
    $SUDO xattr -cr "$APP"
    $SUDO codesign --force --deep --sign - "$APP"
}

FILES=()
while IFS= read -r f; do FILES+=("${f#./}"); done < "$HERE/FILES"

if [ "$RESTORE" = 1 ]; then
    [ -d "$BACKUP" ] || { echo "No backup for version $INSTALLED at $BACKUP"; exit 1; }
    for f in "${FILES[@]}"; do
        [ -f "$BACKUP/$f" ] && $SUDO cp "$BACKUP/$f" "$WEB/$f"
    done
    for p in $SDK_PRODUCTS; do
        [ -f "$BACKUP/sdkjs/$p/sdk-all.js" ] && $SUDO cp "$BACKUP/sdkjs/$p/sdk-all.js" "$SDK/$p/sdk-all.js"
    done
    resign
    echo "Original files restored."
    exit 0
fi

BUILT="$(cat "$HERE/VERSION")"
v3() { echo "$1" | cut -d. -f1-3; }
if [ "$(v3 "$INSTALLED")" != "$(v3 "$BUILT")" ] && [ "$FORCE" = 0 ]; then
    echo "Version mismatch: ONLYOFFICE is $INSTALLED but this fix was built for $BUILT."
    echo "Run the 'Build macOS trackpad fix' workflow with version $(v3 "$INSTALLED") and use that download."
    echo "(Or rerun with --force if you're sure.)"
    exit 1
fi

# Check every target exists before touching anything.
for f in "${FILES[@]}"; do
    if [ ! -f "$WEB/$f" ]; then
        echo "This ONLYOFFICE build doesn't have $f where expected; nothing was changed."
        exit 1
    fi
done

# Prepare the patched sdkjs bundles in a temp folder first, so nothing in the
# app changes unless every patch applies.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SDK_UPDATES=()
for p in $SDK_PRODUCTS; do
    src="$SDK/$p/sdk-all.js"
    [ -f "$src" ] || continue
    # always patch the pristine original if we have it
    [ -f "$BACKUP/sdkjs/$p/sdk-all.js" ] && src="$BACKUP/sdkjs/$p/sdk-all.js"
    mkdir -p "$TMP/$p"
    cp "$src" "$TMP/$p/sdk-all.js"
    for d in "$HERE"/sdkjs/*.diff; do
        # the PDF viewer only exists in the document bundle
        [ "$(basename "$d")" = "pdf-viewer.diff" ] && [ "$p" != "word" ] && continue
        if ! patch --dry-run -s -f "$TMP/$p/sdk-all.js" < "$d" >/dev/null 2>&1; then
            echo "Couldn't apply $(basename "$d") to $p/sdk-all.js (unexpected ONLYOFFICE build); nothing was changed."
            exit 1
        fi
        patch -s -f "$TMP/$p/sdk-all.js" < "$d" >/dev/null
    done
    rm -f "$TMP/$p/"*.orig "$TMP/$p/"*.rej
    SDK_UPDATES+=("$p")
done

# Back up originals (only the first time we see each file).
for f in "${FILES[@]}"; do
    if [ ! -f "$BACKUP/$f" ]; then
        mkdir -p "$BACKUP/$(dirname "$f")"
        cp "$WEB/$f" "$BACKUP/$f"
    fi
done
for p in ${SDK_UPDATES[@]+"${SDK_UPDATES[@]}"}; do
    if [ ! -f "$BACKUP/sdkjs/$p/sdk-all.js" ]; then
        mkdir -p "$BACKUP/sdkjs/$p"
        cp "$SDK/$p/sdk-all.js" "$BACKUP/sdkjs/$p/sdk-all.js"
    fi
done
echo "Originals are backed up in $BACKUP"

for f in "${FILES[@]}"; do
    echo "Updating $f"
    $SUDO cp "$HERE/web-apps/$f" "$WEB/$f"
done
for p in ${SDK_UPDATES[@]+"${SDK_UPDATES[@]}"}; do
    echo "Updating sdkjs/$p/sdk-all.js"
    $SUDO cp "$TMP/$p/sdk-all.js" "$SDK/$p/sdk-all.js"
done

resign
echo "Done. Open ONLYOFFICE and try pinching and scrolling on the trackpad."
echo "To undo: $0 --restore"
