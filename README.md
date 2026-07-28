# Schema Drift Lab

An interactive observability experiment about a failure mode that looks harmless in
transport metrics: telemetry payloads keep arriving while their meaning changes.

Three producer versions describe the same request with different field names, types,
units, and route shapes. The lab evaluates four ingestion policies against one
deterministic ground truth:

- **Lenient ingest** stores everything while canonical queries understand only v1.
- **Best-effort coercion** casts values but reads seconds as milliseconds and admits
  raw resource IDs as metric labels.
- **Drop invalid** keeps the dashboard clean by rejecting the rollout.
- **Versioned contract** selects an explicit decoder, normalizes to one model, emits
  drift signals, and retains the original payload.

The simulation and HTTP service are implemented in **SWI-Prolog**, a deliberate
addition to the language mix in the [telemetry.sh labs](https://github.com/telemetry-sh).
The browser UI is dependency-free HTML, CSS, and JavaScript.

## Run it

Requirements:

- SWI-Prolog 9+
- `jq` and `curl` for the checks

```sh
make run
```

Open <http://localhost:8080>. Every control change calls the Prolog model through
`GET /api/simulate`.

Run the full native check suite:

```sh
make check
```

Or use the production container:

```sh
docker build -t schema-drift-lab .
docker run --rm -p 8080:8080 schema-drift-lab
```

## Try the API

```sh
curl --silent \
  'http://localhost:8080/api/simulate?v2_percent=50&v3_percent=20&raw_route_percent=25' |
  jq '.strategies[] | {label, semantic_coverage_percent, route_series, state}'
```

The model clamps inputs to safe bounds and returns:

- the producer cohort mix;
- the actual error, latency, SLO, and schema-drift totals;
- observed results for all four ingestion strategies;
- rollout timeline points for the coverage chart;
- representative raw and normalized evidence.

For a machine-readable default run without starting the server:

```sh
swipl -q -s src/server.pl -- --json | jq
```

## What to investigate

Start with the default 40% v1 / 35% v2 / 25% v3 deployment:

1. **Lenient ingest reports 100% acceptance and 40% semantic coverage.** The
   transport path is healthy; most events are absent from the canonical query.
2. **Coercion accepts all events but corrupts latency and route cardinality.** A
   successful string-to-number cast does not identify a unit, and a raw path is not
   a safe metric dimension.
3. **Strict rejection makes the surviving data look consistent.** Rejection volume
   is itself production telemetry and belongs next to the dashboard.
4. **The versioned decoder matches ground truth.** It makes the transformation
   inspectable and preserves source evidence for later forensics.

Move the rollout sliders and watch the failure appear as a divergence between
events stored, events understood, and truth recovered. Increasing **Raw route IDs
in v2** demonstrates how the same schema change can also exceed a metric-series
budget.

## Why telemetry.sh

Schema drift is rarely diagnosable from a single aggregate. The useful investigation
joins several kinds of evidence:

- producer `schema_version` and deployment revision;
- canonical and raw field presence;
- unit and type violation counters;
- rejected-event volume;
- distinct route-series growth;
- traces retaining the original attributes.

telemetry.sh is designed for this kind of cross-signal investigation: compare the
rollout cohorts, isolate the producer revision, and inspect the payload behind the
aggregate instead of guessing from a smooth dashboard.

## Project structure

```text
src/model.pl          deterministic schema-drift model
src/server.pl         SWI-Prolog HTTP server and CLI
public/               interactive experiment
tests/model_tests.pl  unit tests for model invariants
tests/http_test.sh    API, static asset, and relocated-CWD checks
tests/container_test.sh
.github/workflows/ci.yml
```

## Safety

The experiment is synthetic. It does not need credentials, contact external
services, or ingest real telemetry. The server runs as an unprivileged container
user and sends a restrictive Content Security Policy.

## License

[MIT](LICENSE)
