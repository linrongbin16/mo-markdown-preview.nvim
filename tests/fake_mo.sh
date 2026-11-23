#!/usr/bin/env bash
set -u

log="${MO_FAKE_LOG:-/dev/null}"
printf '%s\n' "$@" >> "$log"

if [ "${MO_FAKE_FAIL:-0}" = "1" ]; then
  echo "fake mo failure" >&2
  exit 1
fi

last=""
for arg in "$@"; do
  last="$arg"
done

clear=0
port="6275"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --clear) clear=1 ;;
    --port)
      if [ "$#" -ge 2 ]; then
        port="$2"
        shift
      fi
      ;;
  esac
  shift
done

# mo --clear asks on stderr and reads the answer from stdin. A closed stdin is
# EOF, which mo treats as "canceled", so the fake behaves the same way: a clear
# only succeeds when the plugin actually wrote an accepting answer.
if [ "$clear" = "1" ]; then
  case "${MO_FAKE_CLEAR:-}" in
    canceled)
      echo "mo: clear saved session for port $port? [Y/n] mo: canceled" >&2
      exit 0
      ;;
    nosession)
      echo "mo: no saved session for port $port" >&2
      exit 0
      ;;
  esac

  echo "mo: clear saved session for port $port? [Y/n] " >&2
  if IFS= read -r answer; then
    printf '%s' "$answer" > "${log}.stdin"
    case "$answer" in
      "" | y | Y | yes | YES | Yes)
        echo "mo: cleared session and restarted server on port $port" >&2
        exit 0
        ;;
    esac
  else
    printf '%s' "" > "${log}.stdin"
  fi
  echo "mo: canceled" >&2
  exit 0
fi

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

# mo exits 0 with an empty file list when its server rejects a file. The only
# trace of the rejection is the "added 0 item(s)" line on stderr.
if [ "${MO_FAKE_EMPTY:-0}" = "1" ]; then
  printf '{\n'
  printf '  "url": "http://localhost:6275",\n'
  printf '  "files": []\n'
  printf '}\n'
  echo "mo: added 0 item(s) to http://localhost:6275" >&2
  exit 0
fi

# The same empty result, but mo printed nothing that explains it.
if [ "${MO_FAKE_SILENT:-0}" = "1" ]; then
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
