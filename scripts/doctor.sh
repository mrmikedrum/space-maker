#!/usr/bin/env bash
# Runs the Doctor through Launch Services (so permissions are Space Maker's own, not the terminal's)
# and prints the report. Pass --build to rebuild the app first.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "${1:-}" == "--build" || ! -d "build/Space Maker.app" ]] && scripts/build-app.sh >/dev/null
open -W -n "build/Space Maker.app" --args --doctor
cat "$HOME/Library/Logs/SpaceMaker/doctor-latest.md"
