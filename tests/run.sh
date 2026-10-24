#!/usr/bin/env sh
# Run every headless test. Exits non-zero if any test fails.
set -eu

cd "$(dirname "$0")/.."

status=0
for test in tests/[0-9][0-9]_*.lua; do
  printf '%s ... ' "$(basename "$test" .lua)"
  if out=$(nvim --headless --clean -l "$test" 2>&1); then
    printf '%s\n' "$(printf '%s' "$out" | grep '^ok ' || echo ok)"
  else
    status=1
    printf 'FAILED\n'
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
done

exit $status
