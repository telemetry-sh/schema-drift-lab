#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="schema-drift-lab:test"
container="schema-drift-lab-test-$$"

cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build --tag "$image" "$repo_dir"

set +e
preflight="$(docker run --rm "$image" --json 2>&1)"
preflight_status="$?"
set -e
printf '%s\n' "$preflight"
test "$preflight_status" = "0"
printf '%s\n' "$preflight" |
  jq -e '.experiment == "schema-drift" and .truth.total_events == 12000' >/dev/null

docker run --detach --name "$container" "$image" >/dev/null

for _ in {1..40}; do
  if [[ "$(docker inspect --format '{{.State.Running}}' "$container")" != "true" ]]; then
    docker logs "$container"
    exit 1
  fi
  if docker exec "$container" swipl -q -s /app/src/server.pl -- --port=8080 --healthcheck; then
    break
  fi
  sleep 0.25
done

docker exec "$container" swipl -q -s /app/src/server.pl -- --port=8080 --healthcheck
test "$(docker inspect --format '{{.State.Health.Status}}' "$container")" = "healthy"

printf 'Container checks passed\n'
