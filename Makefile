.PHONY: run test check container-test

PORT ?= 8080

run:
	swipl -q -s src/server.pl -- --port=$(PORT)

test:
	swipl -q -g run_tests -t halt tests/model_tests.pl

check: test
	swipl -q -s src/server.pl -- --json | jq -e '.experiment == "schema-drift"' >/dev/null
	./tests/http_test.sh

container-test:
	./tests/container_test.sh
