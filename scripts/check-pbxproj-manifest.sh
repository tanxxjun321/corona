#!/usr/bin/env bash
# Reconcile the .swift file list referenced by Corona.xcodeproj/project.pbxproj
# with the .swift files that actually exist under Sources/.
#
# The pbxproj stores each source file as a bare filename (the parent PBXGroup
# supplies the directory), and no two files under Sources/ share a basename,
# so comparing sorted basename lists is sufficient to catch drift in either
# direction: a new file SPM would pick up but the pbxproj misses, or a deleted
# file the pbxproj still references.
set -euo pipefail

cd "$(dirname "$0")/.."

PBXPROJ="Corona.xcodeproj/project.pbxproj"

pbxproj_files="$(mktemp)"
disk_files="$(mktemp)"
trap 'rm -f "$pbxproj_files" "$disk_files"' EXIT

grep -o 'path = [^;]*\.swift' "$PBXPROJ" \
  | sed 's/^path = //' \
  | sort -u > "$pbxproj_files"

find Sources -name '*.swift' -type f \
  | sed 's|.*/||' \
  | sort -u > "$disk_files"

status=0

# In pbxproj but not on disk: stale references to deleted files.
missing_on_disk="$(comm -23 "$pbxproj_files" "$disk_files")"
if [[ -n "$missing_on_disk" ]]; then
  status=1
  echo "error: pbxproj references files missing from Sources/:" >&2
  echo "$missing_on_disk" | sed 's/^/  - /' >&2
fi

# On disk but not in pbxproj: new files the Xcode target would not compile.
missing_in_pbxproj="$(comm -13 "$pbxproj_files" "$disk_files")"
if [[ -n "$missing_in_pbxproj" ]]; then
  status=1
  echo "error: Sources/ files not referenced by pbxproj:" >&2
  echo "$missing_in_pbxproj" | sed 's/^/  - /' >&2
fi

if [[ "$status" -ne 0 ]]; then
  echo "pbxproj manifest is out of sync with Sources/; update Corona.xcodeproj/project.pbxproj." >&2
  exit 1
fi

echo "pbxproj manifest is in sync with Sources/ ($(wc -l < "$disk_files" | tr -d ' ') files)."
