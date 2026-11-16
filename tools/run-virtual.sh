#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Opens the latest Debug build of X1 Scan on the VIRTUAL X1, with a preview
# started automatically, for screenshots and checks. Never the real scanner:
# the source is forced to the virtual X1 for this launch, and the automatic
# preview only runs on the virtual X1 (AppModel.startPreview).
#
#   tools/run-virtual.sh [--dark | --light] [--fr | --en] [--build] [--app PATH]
#
#   --dark / --light   appearance for this launch (default: the app's setting)
#   --fr / --en        interface language for this launch (default: the app's setting)
#   --build            build Debug first, into app/build (ignored by git)
#   --app PATH         use this "X1 Scan.app" instead of searching
#
# Without --app, the most recent Debug build among Xcode's DerivedData and
# app/build is used. Appearance and language apply to this launch only. The
# app saves its window and panel layout as usual, and remembers the virtual
# X1 as the last source used (Settings > Scanner, "last source" starts there
# next time). Quit X1 Scan first: a running instance would ignore the options.

set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
appearance=""
language=""
build=0
app=""

usage() {
    sed -n '9,15p' "$0" >&2
    exit "${1:-2}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dark) appearance=dark ;;
        --light) appearance=light ;;
        --fr) language=fr ;;
        --en) language=en ;;
        --build) build=1 ;;
        --app) [ $# -ge 2 ] || usage; app=$2; shift ;;
        -h|--help) usage 0 ;;
        *) echo "run-virtual: unknown option $1" >&2; usage ;;
    esac
    shift
done

if [ "$build" -eq 1 ]; then
    echo "run-virtual: building Debug into app/build…" >&2
    (cd "$repo/app" && xcodebuild -project X1Scan.xcodeproj -scheme X1Scan -configuration Debug \
        -derivedDataPath "$repo/app/build" CODE_SIGNING_ALLOWED=NO build -quiet) \
        || { echo "run-virtual: build failed" >&2; exit 1; }
fi

if [ -z "$app" ]; then
    # Most recent "X1 Scan.app" of a Debug build, by modification time.
    app=$( { ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/X1Scan-*/Build/Products/Debug/"X1 Scan.app" \
                    "$repo"/app/build/Build/Products/Debug/"X1 Scan.app" 2>/dev/null; } | head -n 1)
fi
if [ -z "$app" ] || [ ! -d "$app" ]; then
    echo "run-virtual: no Debug build of X1 Scan found. Build it in Xcode, or run: $0 --build" >&2
    exit 1
fi

case "$app" in
    */Debug/*) ;;
    *) echo "run-virtual: $app is not a Debug build: no automatic preview (debug only)." >&2 ;;
esac

if pgrep -x "X1 Scan" > /dev/null; then
    echo "run-virtual: X1 Scan is already running; quit it first (the options would be ignored)." >&2
    exit 1
fi

args=(-StartupSource virtual -X1ScanAutoPreview YES)
[ -n "$appearance" ] && args+=(-Appearance "$appearance")
[ -n "$language" ] && args+=(-AppleLanguages "($language)")

echo "run-virtual: $app" >&2
exec open -n "$app" --args "${args[@]}"
