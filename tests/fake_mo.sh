#!/usr/bin/env bash
set -u

log="${MO_FAKE_LOG:-/dev/null}"
printf '%s\n' "$@" >> "$log"

if [ "${MO_FAKE_FAIL:-0}" = "1" ]; then
  echo "fake mo failure" >&2
  exit 1
fi

for last; do :; done
if [ -z "${last:-}" ]; then
  echo "fake mo: missing file argument" >&2
  exit 2
fi

if [ "${MO_FAKE_MULTI:-0}" = "1" ]; then
  printf '{\n'
  printf '  "url": "http://localhost:6275",\n'
  printf '  "files": [\n'
  printf '    {"url": "http://localhost:6275/?file=other", "name": "other.md", "path": "/tmp/other.md"},\n'
  printf '    {"url": "http://localhost:6275/?file=match", "name": "%s", "path": "%s"}\n' "$(basename "$last")" "$last"
  printf '  ]\n'
  printf '}\n'
  exit 0
fi

# mo exits 0 with an empty file list when it rejects a file (binary, unreadable).
if [ "${MO_FAKE_EMPTY:-0}" = "1" ]; then
  printf '{\n'
  printf '  "url": "http://localhost:6275",\n'
  printf '  "files": []\n'
  printf '}\n'
  exit 0
fi

printf '{\n'
printf '  "url": "http://localhost:6275",\n'
printf '  "files": [\n'
printf '    {"url": "http://localhost:6275/?file=fake", "name": "%s", "path": "%s"}\n' "$(basename "$last")" "$last"
printf '  ]\n'
printf '}\n'
