#!/bin/bash
# Installs the rebuilt editor files (smooth trackpad pinch-to-zoom) into ONLYOFFICE.app.
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
    resign
    echo "Original files restored."
    exit 0
fi

BUILT="$(cat "$HERE/VERSION")"
v3() { echo "$1" | cut -d. -f1-3; }
if [ "$(v3 "$INSTALLED")" != "$(v3 "$BUILT")" ] && [ "$FORCE" = 0 ]; then
    echo "Version mismatch: ONLYOFFICE is $INSTALLED but this fix was built for $BUILT."
    echo "Run the 'Build macOS pinch-zoom fix' workflow with version $(v3 "$INSTALLED") and use that download."
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

if [ ! -d "$BACKUP" ]; then
    echo "Backing up originals to $BACKUP"
    for f in "${FILES[@]}"; do
        mkdir -p "$BACKUP/$(dirname "$f")"
        cp "$WEB/$f" "$BACKUP/$f"
    done
fi

for f in "${FILES[@]}"; do
    echo "Updating $f"
    $SUDO cp "$HERE/web-apps/$f" "$WEB/$f"
done

resign
echo "Done. Open ONLYOFFICE and try pinching on the trackpad."
echo "To undo: $0 --restore"
