#!/bin/bash
# Kept for muscle memory: v2 builds with SwiftPM via build.sh. All flags are forwarded.
exec "$(cd "$(dirname "$0")" && pwd)/build.sh" "$@"
