:- module(schema_model, [
    default_params/1,
    normalize_params/2,
    simulate/2
]).

:- use_module(library(lists)).

default_params(_{
    total_events: 12000,
    v2_percent: 35,
    v3_percent: 25,
    error_percent: 8,
    slow_percent: 12,
    raw_route_percent: 18,
    slo_ms: 750,
    max_series: 500
}).

normalize_params(Input, Params) :-
    default_params(Defaults),
    param_int(Input, total_events, Defaults.total_events, 1000, 100000, Total),
    param_int(Input, v2_percent, Defaults.v2_percent, 0, 80, V2),
    V3Max is 95 - V2,
    param_int(Input, v3_percent, Defaults.v3_percent, 0, V3Max, V3),
    param_int(Input, error_percent, Defaults.error_percent, 0, 50, Error),
    param_int(Input, slow_percent, Defaults.slow_percent, 0, 50, Slow),
    param_int(Input, raw_route_percent, Defaults.raw_route_percent, 0, 100, RawRoute),
    param_int(Input, slo_ms, Defaults.slo_ms, 100, 2000, Slo),
    param_int(Input, max_series, Defaults.max_series, 25, 5000, MaxSeries),
    Params = _{
        total_events: Total,
        v2_percent: V2,
        v3_percent: V3,
        error_percent: Error,
        slow_percent: Slow,
        raw_route_percent: RawRoute,
        slo_ms: Slo,
        max_series: MaxSeries
    }.

param_int(Input, Key, Default, Min, Max, Value) :-
    (   get_dict(Key, Input, Candidate),
        number(Candidate)
    ->  Rounded is round(Candidate),
        Value is max(Min, min(Max, Rounded))
    ;   Value = Default
    ).

simulate(Input, Result) :-
    normalize_params(Input, Params),
    cohort_counts(Params, Cohorts),
    truth(Params, Cohorts, Truth),
    strategy_results(Params, Cohorts, Truth, Strategies),
    timeline(Params, Timeline),
    evidence(Params, Evidence),
    Result = _{
        experiment: "schema-drift",
        params: Params,
        cohorts: Cohorts,
        truth: Truth,
        strategies: Strategies,
        timeline: Timeline,
        evidence: Evidence,
        lesson: "An accepted event is not necessarily an understood event. Version the contract, normalize at the boundary, and retain the original evidence."
    }.

cohort_counts(Params, _{
    v1: _{events: V1Count, percent: V1Percent},
    v2: _{events: V2Count, percent: V2Percent},
    v3: _{events: V3Count, percent: V3Percent}
}) :-
    V2Percent = Params.v2_percent,
    V3Percent = Params.v3_percent,
    V1Percent is 100 - V2Percent - V3Percent,
    Total = Params.total_events,
    V2Count is round(Total * V2Percent / 100),
    V3Count is round(Total * V3Percent / 100),
    V1Count is Total - V2Count - V3Count.

truth(Params, Cohorts, _{
    total_events: Total,
    error_events: ErrorEvents,
    error_percent: ErrorPercent,
    slow_events: SlowEvents,
    slo_violations: SlowEvents,
    slow_percent: SlowPercent,
    mean_latency_ms: MeanLatency,
    p99_latency_ms: P99,
    route_series: 4,
    schema_versions: 3,
    drifted_events: Drifted,
    drifted_percent: DriftedPercent
}) :-
    Total = Params.total_events,
    ErrorPercent = Params.error_percent,
    SlowPercent = Params.slow_percent,
    ErrorEvents is round(Total * ErrorPercent / 100),
    SlowEvents is round(Total * SlowPercent / 100),
    MeanLatency is round((100 - SlowPercent) * 120 / 100 + SlowPercent * 1800 / 100),
    percentile_latency(SlowPercent, P99),
    Drifted is Cohorts.v2.events + Cohorts.v3.events,
    DriftedPercent is Cohorts.v2.percent + Cohorts.v3.percent.

percentile_latency(SlowPercent, 1800) :-
    SlowPercent >= 2,
    !.
percentile_latency(_, 120).

strategy_results(Params, Cohorts, Truth, [
    Lenient,
    Coerce,
    Strict,
    Versioned
]) :-
    proportional(Cohorts.v1.events, Params.error_percent, V1Errors),
    proportional(Cohorts.v1.events, Params.slow_percent, V1Slow),
    proportional(Cohorts.v2.events, Params.error_percent, V2Errors),
    proportional(Cohorts.v3.events, Params.slow_percent, V3Slow),
    RawRouteEvents is round(Cohorts.v2.events * Params.raw_route_percent / 100),
    ExplodedSeries is 4 + RawRouteEvents,
    semantic_state(Cohorts.v1.percent, 100, LenientState),
    cardinality_state(ExplodedSeries, Params.max_series, CoerceState),
    Lenient = _{
        id: "lenient",
        label: "Lenient ingest",
        description: "Store every payload, but query only the original field names.",
        accepted_events: Params.total_events,
        understood_events: Cohorts.v1.events,
        dropped_events: 0,
        semantic_coverage_percent: Cohorts.v1.percent,
        observed_error_events: V1Errors,
        observed_slo_violations: V1Slow,
        observed_mean_latency_ms: Truth.mean_latency_ms,
        route_series: 4,
        unknown_fields: 6,
        unit_violations: Cohorts.v2.events,
        type_violations: Cohorts.v2.events,
        state: LenientState,
        diagnosis: "Transport success hides semantic loss: v2 and v3 are stored but invisible to canonical queries."
    },
    CoerceUnderstood is Cohorts.v1.events + Cohorts.v2.events,
    CoerceCoverage is round(100 * CoerceUnderstood / Params.total_events),
    CoerceErrors is V1Errors + V2Errors,
    CoerceSlow is V1Slow + V3Slow,
    CoerceMean is round(
        (Cohorts.v1.percent + Cohorts.v3.percent) * Truth.mean_latency_ms / 100
        + Cohorts.v2.percent * 2 / 100
    ),
    Coerce = _{
        id: "coerce",
        label: "Best-effort coercion",
        description: "Rename familiar fields and cast strings, without a version-aware unit contract.",
        accepted_events: Params.total_events,
        understood_events: CoerceUnderstood,
        dropped_events: 0,
        semantic_coverage_percent: CoerceCoverage,
        observed_error_events: CoerceErrors,
        observed_slo_violations: CoerceSlow,
        observed_mean_latency_ms: CoerceMean,
        route_series: ExplodedSeries,
        unknown_fields: 3,
        unit_violations: Cohorts.v2.events,
        type_violations: 0,
        state: CoerceState,
        diagnosis: "The cast succeeds, but seconds are read as milliseconds and raw route IDs become metric labels."
    },
    Rejected is Cohorts.v2.events + Cohorts.v3.events,
    Strict = _{
        id: "strict",
        label: "Drop invalid",
        description: "Reject any event that does not match the original schema.",
        accepted_events: Cohorts.v1.events,
        understood_events: Cohorts.v1.events,
        dropped_events: Rejected,
        semantic_coverage_percent: Cohorts.v1.percent,
        observed_error_events: V1Errors,
        observed_slo_violations: V1Slow,
        observed_mean_latency_ms: Truth.mean_latency_ms,
        route_series: 4,
        unknown_fields: 0,
        unit_violations: 0,
        type_violations: 0,
        state: "clean / incomplete",
        diagnosis: "The dashboard stays tidy because the rollout is discarded before it can disagree."
    },
    Versioned = _{
        id: "versioned",
        label: "Versioned contract",
        description: "Select a decoder by schema version, normalize units and types, and retain raw evidence.",
        accepted_events: Params.total_events,
        understood_events: Params.total_events,
        dropped_events: 0,
        semantic_coverage_percent: 100,
        observed_error_events: Truth.error_events,
        observed_slo_violations: Truth.slo_violations,
        observed_mean_latency_ms: Truth.mean_latency_ms,
        route_series: 4,
        unknown_fields: 0,
        unit_violations: 0,
        type_violations: 0,
        state: "faithful",
        diagnosis: "Every version maps into one canonical model while the source payload remains available for audit."
    }.

proportional(Count, Percent, Result) :-
    Result is round(Count * Percent / 100).

semantic_state(Coverage, _, "blind") :-
    Coverage < 50,
    !.
semantic_state(Coverage, _, "partial") :-
    Coverage < 90,
    !.
semantic_state(_, _, "healthy").

cardinality_state(Series, Budget, "over budget") :-
    Series > Budget,
    !.
cardinality_state(_, _, "corrupted").

timeline(Params, Timeline) :-
    numlist(0, 11, Minutes),
    maplist(timeline_point(Params), Minutes, Timeline).

timeline_point(Params, Minute, _{
    minute: Minute,
    v1_percent: V1,
    v2_percent: V2,
    v3_percent: V3,
    lenient_coverage_percent: V1,
    coerce_semantic_percent: CoerceCoverage,
    versioned_coverage_percent: 100,
    coerced_route_series: Series
}) :-
    V2 is round(Params.v2_percent * Minute / 11),
    (   Minute < 5
    ->  V3 = 0
    ;   V3 is round(Params.v3_percent * (Minute - 4) / 7)
    ),
    V1 is 100 - V2 - V3,
    CoerceCoverage is 100 - V3,
    DriftedEvents is round(Params.total_events * V2 / 100),
    RawEvents is round(DriftedEvents * Params.raw_route_percent / 100),
    Series is 4 + RawEvents.

evidence(Params, [
    _{
        version: "v1",
        status: "canonical",
        payload: _{
            schema_version: 1,
            duration_ms: 1800,
            status_code: 500,
            route: "orders.show"
        },
        normalized: _{
            duration_ms: 1800,
            is_error: true,
            route: "orders.show"
        },
        finding: "Matches the original contract."
    },
    _{
        version: "v2",
        status: "unit + type + cardinality drift",
        payload: _{
            schema_version: 2,
            duration_s: 1.8,
            status: "500",
            endpoint: "/orders/884219"
        },
        normalized: _{
            duration_ms: 1800,
            is_error: true,
            route: "orders.show"
        },
        finding: "A generic cast cannot infer that 1.8 seconds means 1800 milliseconds or that the numeric path segment is an ID."
    },
    _{
        version: "v3",
        status: "field drift",
        payload: _{
            schema_version: 3,
            latency_ms: 1800,
            outcome: "error",
            route_name: "orders.show"
        },
        normalized: _{
            duration_ms: 1800,
            is_error: true,
            route: "orders.show"
        },
        finding: "The meaning survives only when the decoder knows the producer contract."
    },
    _{
        version: "contract",
        status: "boundary rule",
        payload: _{
            decoder: "schema_version",
            raw_event_retained: true,
            route_series_budget: Params.max_series
        },
        normalized: _{
            duration_unit: "ms",
            error_type: "boolean",
            route_shape: "low-cardinality"
        },
        finding: "Normalize explicitly, emit drift telemetry, and keep the original payload for forensics."
    }
]).
