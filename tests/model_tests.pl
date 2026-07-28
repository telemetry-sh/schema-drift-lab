:- begin_tests(schema_model).

:- use_module('../src/model').

strategy(Result, Id, Strategy) :-
    member(Strategy, Result.strategies),
    Strategy.id == Id,
    !.

test(defaults_are_deterministic) :-
    default_params(Params),
    simulate(Params, Result),
    assertion(Result.truth.total_events =:= 12000),
    assertion(Result.cohorts.v1.events =:= 4800),
    assertion(Result.cohorts.v2.events =:= 4200),
    assertion(Result.cohorts.v3.events =:= 3000),
    assertion(Result.truth.error_events =:= 960),
    assertion(Result.truth.slo_violations =:= 1440).

test(lenient_acceptance_is_not_semantic_coverage) :-
    default_params(Params),
    simulate(Params, Result),
    strategy(Result, "lenient", Lenient),
    assertion(Lenient.accepted_events =:= 12000),
    assertion(Lenient.understood_events =:= 4800),
    assertion(Lenient.semantic_coverage_percent =:= 40),
    assertion(Lenient.state == "blind").

test(coercion_corrupts_units_and_cardinality) :-
    default_params(Params),
    simulate(Params, Result),
    strategy(Result, "coerce", Coerce),
    assertion(Coerce.unit_violations =:= 4200),
    assertion(Coerce.route_series =:= 760),
    assertion(Coerce.observed_mean_latency_ms < Result.truth.mean_latency_ms),
    assertion(Coerce.state == "over budget").

test(versioned_contract_matches_truth) :-
    default_params(Params),
    simulate(Params, Result),
    strategy(Result, "versioned", Versioned),
    assertion(Versioned.semantic_coverage_percent =:= 100),
    assertion(Versioned.observed_error_events =:= Result.truth.error_events),
    assertion(Versioned.observed_slo_violations =:= Result.truth.slo_violations),
    assertion(Versioned.route_series =:= Result.truth.route_series),
    assertion(Versioned.state == "faithful").

test(parameters_are_clamped_and_rollout_keeps_v1) :-
    normalize_params(_{
        total_events: 4,
        v2_percent: 99,
        v3_percent: 99,
        error_percent: -2,
        max_series: 99999
    }, Params),
    assertion(Params.total_events =:= 1000),
    assertion(Params.v2_percent =:= 80),
    assertion(Params.v3_percent =:= 15),
    assertion(Params.error_percent =:= 0),
    assertion(Params.max_series =:= 5000).

test(timeline_reaches_requested_rollout) :-
    default_params(Params),
    simulate(Params, Result),
    last(Result.timeline, Final),
    assertion(Final.v2_percent =:= 35),
    assertion(Final.v3_percent =:= 25),
    assertion(Final.v1_percent =:= 40),
    assertion(Final.versioned_coverage_percent =:= 100).

:- end_tests(schema_model).
