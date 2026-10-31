#!/bin/bash
# Installs the rebuilt editor UI (smooth trackpad pinch-to-zoom) into ONLYOFFICE.app.
#
#   ./install.sh                     install into /Applications/ONLYOFFICE.app
#   ./install.sh /path/to/ONLYOFFICE.app
#   ./install.sh --restore           put the original files back from the backup
#   ./install.sh --force ...         skip the version check
#
# The original files are backed up to ~/Library/Application Support/ONLYOFFICE-pinch-fix-backup.
# After copying, the app is re-signed ad hoc so macOS still launches it.
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

EDITORS="documenteditor spreadsheeteditor presentationeditor pdfeditor visioeditor"
APPS_DIR="$APP/Contents/Resources/editors/web-apps/apps"
BACKUP="$HOME/Library/Application Support/ONLYOFFICE-pinch-fix-backup"

[ -d "$APPS_DIR" ] || { echo "Can't find editor files in $APP (expected $APPS_DIR)."; exit 1; }

if pgrep -f "$APP/Contents/MacOS" >/dev/null 2>&1; then
    echo "Please quit ONLYOFFICE first."; exit 1
fi

SUDO=""
[ -w "$APPS_DIR" ] || SUDO="sudo"

resign() {
    echo "Re-signing $APP (ad hoc)..."
    $SUDO xattr -cr "$APP"
    $SUDO codesign --force --deep --sign - "$APP"
}

if [ "$RESTORE" = 1 ]; then
    [ -d "$BACKUP" ] || { echo "No backup found at $BACKUP"; exit 1; }
    for ed in $EDITORS; do
        [ -d "$BACKUP/$ed/main" ] && $SUDO rsync -a --delete "$BACKUP/$ed/main/" "$APPS_DIR/$ed/main/"
    done
    resign
    echo "Original editor files restored."
    exit 0
fi

INSTALLED="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
BUILT="$(cat "$HERE/VERSION")"
v3() { echo "$1" | cut -d. -f1-3; }
if [ "$(v3 "$INSTALLED")" != "$(v3 "$BUILT")" ] && [ "$FORCE" = 0 ]; then
    echo "Version mismatch: ONLYOFFICE is $INSTALLED but this fix was built for $BUILT."
    echo "Rebuild it for your version (Actions > Build macOS pinch-zoom fix > version $INSTALLED),"
    echo "or rerun with --force if you know what you're doing."
    exit 1
fi

if [ ! -d "$BACKUP" ]; then
    echo "Backing up original files to $BACKUP"
    mkdir -p "$BACKUP"
    for ed in $EDITORS; do
        [ -d "$APPS_DIR/$ed/main" ] && mkdir -p "$BACKUP/$ed" && cp -R "$APPS_DIR/$ed/main" "$BACKUP/$ed/main"
    done
fi

for ed in $EDITORS; do
    if [ -d "$APPS_DIR/$ed/main" ] && [ -d "$HERE/web-apps/apps/$ed/main" ]; then
        echo "Updating $ed"
        $SUDO rsync -a "$HERE/web-apps/apps/$ed/main/" "$APPS_DIR/$ed/main/"
    fi
done

resign
echo "Done. Start ONLYOFFICE and try pinching on the trackpad."
