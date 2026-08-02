#!/usr/bin/env bash
# Sync (or verify) skills/cardog/SKILL.md against the live surface.
#
# The source of truth is generated inside the cardog.app application from
# @cardog/contracts and @cardog/entities and served at https://cardog.app/skill.md,
# indexed with a sha256 digest at https://cardog.app/.well-known/skills/index.json.
# This repo is a distribution mirror. It must never drift.
#
#   scripts/sync.sh          overwrite the repo copy with the live artifact
#   scripts/sync.sh --check  exit 1 if the repo copy differs from the live artifact
#
# Both modes verify the served artifact against the advertised digest first,
# so a corrupted or partially-deployed surface can never be mirrored in.
set -euo pipefail
cd "$(dirname "$0")/.."

SKILL_URL="https://cardog.app/skill.md"
INDEX_URL="https://cardog.app/.well-known/skills/index.json"
DEST="skills/cardog/SKILL.md"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsS "$SKILL_URL" -o "$tmp"

advertised="$(curl -fsS "$INDEX_URL" | grep -o 'sha256:[a-f0-9]\{64\}' | head -1)"
actual="sha256:$(shasum -a 256 "$tmp" | cut -d' ' -f1)"
if [ "$advertised" != "$actual" ]; then
  echo "INTEGRITY FAILURE: $SKILL_URL hashes to $actual but $INDEX_URL advertises $advertised" >&2
  exit 2
fi

if [ "${1:-}" = "--check" ]; then
  if ! diff -u "$DEST" "$tmp"; then
    echo "DRIFT: $DEST differs from $SKILL_URL (digest-verified $actual)" >&2
    echo "Run scripts/sync.sh and commit the result." >&2
    exit 1
  fi
  echo "OK: $DEST matches $SKILL_URL ($actual)"
else
  cp "$tmp" "$DEST"
  echo "Synced $DEST from $SKILL_URL ($actual)"
fi
