#!/usr/bin/env bash
set -euo pipefail

read -r -a cdxgen_cmd <<< "${CDXGEN:-cdxgen}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${OUT_DIR:-$(mktemp -d)}"
readonly out
readonly lockonly="$out/lockonly"

print_scopes() {
  node -e '
const bom = require(process.argv[1]);
for (const c of bom.components) {
  const optional = (c.properties || []).some(
    (p) => p.name === "cdx:npm:package:optional" && p.value === "true",
  );
  const occurrences = c.evidence?.occurrences?.length || 0;
  console.log(
    `${(c.scope || "-").padEnd(9)} ${`${c.group}/${c.name}`.padEnd(36)} npmOptional=${optional} occurrences=${occurrences}`,
  );
}' "$1"
}

run() {
  local label="$1"
  local dir="$2"
  shift 2
  printf '== %s\n' "$label"
  if ! "${cdxgen_cmd[@]}" --type js "$@" -o "$out/$label.json" "$dir" > "$out/$label.log" 2>&1; then
    echo "cdxgen failed, see $out/$label.log" >&2
    exit 1
  fi
  print_scopes "$out/$label.json"
  printf '\n'
}

if ! command -v "${cdxgen_cmd[0]}" > /dev/null; then
  echo "${cdxgen_cmd[0]} not found, put cdxgen on PATH or set CDXGEN" >&2
  exit 1
fi

if [[ ! -d "$here/node_modules" ]]; then
  echo "node_modules is missing, run 'npm ci' first" >&2
  exit 1
fi

rm -rf "$here/.chen"
mkdir -p "$lockonly"
cp -r "$here/package.json" "$here/package-lock.json" "$here/src" "$lockonly/"

run lockfile-only "$lockonly"
run lockfile-only-evidence "$lockonly" --evidence
run installed-evidence "$here" --evidence

printf 'BOMs and logs are in %s\n' "$out"
