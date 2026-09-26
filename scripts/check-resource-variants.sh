#!/usr/bin/env bash
# Terraform cannot make lifecycle.ignore_changes conditional, so a file may
# declare the same resource twice with identical bodies and create exactly one
# of them. This check fails when the two bodies drift apart in anything other
# than their count and ignore_changes lines.
#
# Usage: check-resource-variants.sh <file> <resource_type> <name_a> <name_b>
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <file> <resource_type> <name_a> <name_b>" >&2
  exit 2
fi

file="$1"
type="$2"
name_a="$3"
name_b="$4"

extract() {
  awk -v type="$type" -v name="$1" '
    $0 ~ "^resource \"" type "\" \"" name "\" \\{" { inside = 1; next }
    inside && /^\}/ { inside = 0 }
    inside && $1 == "count" { next }
    inside && $1 == "ignore_changes" { next }
    inside { print }
  ' "$file"
}

for name in "$name_a" "$name_b"; do
  if [[ -z "$(extract "$name")" ]]; then
    echo "error: resource \"$type\" \"$name\" was not found in $file" >&2
    exit 1
  fi
done

if diff <(extract "$name_a") <(extract "$name_b") >/dev/null; then
  echo "ok: $type.$name_a and $type.$name_b in $file are identical apart from count and ignore_changes"
else
  echo "error: the two $type variants in $file have drifted:" >&2
  diff <(extract "$name_a") <(extract "$name_b") >&2 || true
  exit 1
fi
