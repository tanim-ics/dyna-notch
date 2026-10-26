#!/bin/bash
# Builds, installs and also packs DynaNotch.dmg. All flags are forwarded to build.sh.
exec "$(cd "$(dirname "$0")" && pwd)/build.sh" --dmg "$@"
