#!/usr/bin/env bash
# Stage a Factorio mods dir for headless testing of Brave New MTS.
#
# usage: tools/rig/stage.sh <mods-dir> [--mts <zip-or-dir>] [--hooks] [--no-space-age]
#
#   <mods-dir>      created if missing. Old brave-new-mts_* / multi-team-support*
#                   entries in it are replaced; anything else there is left alone.
#   --mts PATH      MTS to stage instead of ~/.factorio/mods/multi-team-support_0.6.6.zip
#                   (a zip is copied, a directory is symlinked as multi-team-support).
#   --hooks         also inject the test-only prototypes in tools/rig/hooks/
#                   (bnm-rig-load, a constant electrical load) into the STAGED
#                   copy, required from the staged data.lua. Never touches the
#                   repo's mod code. Control-stage hooks are not needed: the
#                   /sc __brave-new-mts__ method reaches BNM's modules directly.
#   --no-space-age  mod-list.json disables space-age, quality and elevated-rails.
#
# BNM is staged as a COPY of the working tree (uncommitted edits included) named
# brave-new-mts_<version from info.json>, excluding .git .github .claude docs tools
# and editor files, i.e. roughly what the release zip ships.
set -euo pipefail

usage() { sed -n '2,20p' "$0" >&2; exit 1; }
[ $# -ge 1 ] || usage

MODS=$1; shift
MTS=$HOME/.factorio/mods/multi-team-support_0.6.6.zip
HOOKS=
SPACE_AGE=true
while [ $# -gt 0 ]; do
  case $1 in
    --mts) MTS=$2; shift 2 ;;
    --hooks) HOOKS=1; shift ;;
    --no-space-age) SPACE_AGE=false; shift ;;
    *) usage ;;
  esac
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
command -v jq >/dev/null || { echo "stage.sh: jq required" >&2; exit 1; }
VERSION=$(jq -r .version "$REPO/info.json")
NAME=$(jq -r .name "$REPO/info.json")
[ -e "$MTS" ] || { echo "stage.sh: MTS not found at $MTS" >&2; exit 1; }

mkdir -p "$MODS"
rm -rf "$MODS"/"$NAME"_* "$MODS"/"$NAME" "$MODS"/multi-team-support_* "$MODS"/multi-team-support

# MTS: a zip is copied as-is, a source dir is symlinked (live edits).
if [ -d "$MTS" ]; then
  ln -s "$(cd "$MTS" && pwd)" "$MODS/multi-team-support"
else
  cp "$MTS" "$MODS/"
fi

# BNM: a copy of the working tree.
DEST="$MODS/${NAME}_${VERSION}"
rsync -a \
  --exclude='.git' --exclude='.github' --exclude='.claude' \
  --exclude='docs' --exclude='tools' --exclude='build' \
  --exclude='*.zip' --exclude='*.code-workspace' --exclude='.luarc.json' \
  --exclude='*.sh' --exclude='*.py' \
  "$REPO/" "$DEST/"

if [ -n "$HOOKS" ]; then
  cp "$REPO/tools/rig/hooks/bnm_rig_data.lua" "$DEST/bnm_rig_data.lua"
  printf '\n-- injected by tools/rig/stage.sh --hooks (staged copy only)\nrequire("bnm_rig_data")\n' >> "$DEST/data.lua"
fi

cat > "$MODS/mod-list.json" <<JSON
{
  "mods": [
    { "name": "base", "enabled": true },
    { "name": "elevated-rails", "enabled": $SPACE_AGE },
    { "name": "quality", "enabled": $SPACE_AGE },
    { "name": "space-age", "enabled": $SPACE_AGE },
    { "name": "multi-team-support", "enabled": true },
    { "name": "$NAME", "enabled": true }
  ]
}
JSON

echo "staged $MODS:"
echo "  $(basename "$(ls -d "$MODS"/multi-team-support* | head -1)")"
echo "  ${NAME}_${VERSION}${HOOKS:+ (with test hooks)}"
echo "  space-age: $SPACE_AGE"
