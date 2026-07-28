#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${TEST_PORT:-18080}"
log_file="$(mktemp)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -f "$log_file"
}
trap cleanup EXIT

(
  cd /
  swipl -q -s "$repo_dir/src/server.pl" -- "--host=127.0.0.1" "--port=$port"
) >"$log_file" 2>&1 &
server_pid="$!"

for _ in {1..40}; do
  if curl --fail --silent "http://127.0.0.1:$port/healthz" >/dev/null; then
    break
  fi
  sleep 0.1
done

curl --fail --silent "http://127.0.0.1:$port/healthz" |
  jq -e '.status == "ok" and .runtime == "swi-prolog"' >/dev/null

curl --fail --silent \
  "http://127.0.0.1:$port/api/simulate?v2_percent=50&v3_percent=20&raw_route_percent=25" |
  jq -e '
    .cohorts.v1.percent == 30 and
    .cohorts.v2.percent == 50 and
    .cohorts.v3.percent == 20 and
    (.strategies[] | select(.id == "versioned") | .semantic_coverage_percent) == 100
  ' >/dev/null

curl --fail --silent "http://127.0.0.1:$port/" |
  grep -q "The data arrived"

curl --fail --silent --dump-header - --output /dev/null "http://127.0.0.1:$port/styles.css" |
  grep -qi "content-type: text/css"

curl --fail --silent --dump-header - --output /dev/null "http://127.0.0.1:$port/" |
  grep -qi "content-security-policy: default-src 'self'"

status="$(curl --silent --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:$port/missing")"
test "$status" = "404"

if ! swipl -q -s "$repo_dir/src/server.pl" -- "--port=$port" --healthcheck; then
  printf 'healthcheck command failed\n' >&2
  exit 1
fi

printf 'HTTP integration checks passed\n'
