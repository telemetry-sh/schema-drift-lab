:- module(server, [main/0]).

:- use_module(library(http/http_server)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_open)).
:- use_module(library(http/json)).
:- use_module(library(readutil)).
:- use_module(model).

:- dynamic public_directory/1.
:- dynamic source_directory/1.

:- prolog_load_context(directory, SourceDir),
   asserta(source_directory(SourceDir)).

:- http_handler(root(.), index_handler, [methods([get])]).
:- http_handler(root('index.html'), index_handler, [methods([get])]).
:- http_handler(root('app.js'), javascript_handler, [methods([get])]).
:- http_handler(root('styles.css'), stylesheet_handler, [methods([get])]).
:- http_handler(root(healthz), health_handler, [methods([get])]).
:- http_handler(root(api/simulate), simulate_handler, [methods([get])]).

:- initialization(main, main).

main :-
    current_prolog_flag(argv, Args),
    (   memberchk('--json', Args)
    ->  run_json,
        halt(0)
    ;   memberchk('--healthcheck', Args)
    ->  (   run_healthcheck(Args)
        ->  halt(0)
        ;   halt(1)
        )
    ;   catch(run_server(Args), Error, fatal_server_error(Error))
    ).

run_json :-
    default_params(Params),
    simulate(Params, Result),
    json_write_dict(current_output, Result, [width(0)]),
    nl.

run_server(Args) :-
    option_value(Args, '--host=', '0.0.0.0', Host),
    environment_or_option_port(Args, Port),
    configure_public_directory(Args),
    http_server_options(Host, Port, ServerOptions),
    http_server(http_dispatch, ServerOptions),
    format(user_error, 'schema-drift-lab listening on http://~w:~d~n', [Host, Port]),
    thread_get_message(_).

http_server_options('0.0.0.0', Port, [port(Port), workers(8)]) :-
    !.
http_server_options(Host, Port, [port(Port), workers(8), ip(Host)]).

fatal_server_error(Error) :-
    print_message(error, Error),
    halt(1).

run_healthcheck(Args) :-
    environment_or_option_port(Args, Port),
    format(atom(URL), 'http://127.0.0.1:~d/healthz', [Port]),
    catch(
        setup_call_cleanup(
            http_open(URL, Stream, [status_code(Status), timeout(2)]),
            read_string(Stream, _, Body),
            close(Stream)
        ),
        _,
        fail
    ),
    Status =:= 200,
    sub_string(Body, _, _, _, "\"ok\""),
    !.

environment_or_option_port(Args, Port) :-
    (   option_value(Args, '--port=', _, PortAtom)
    ->  atom_number(PortAtom, Port)
    ;   getenv('PORT', PortEnv),
        atom_number(PortEnv, Port)
    ->  true
    ;   Port = 8080
    ).

configure_public_directory(Args) :-
    retractall(public_directory(_)),
    (   option_value(Args, '--public-dir=', _, Public)
    ->  absolute_file_name(Public, Absolute, [file_type(directory), access(read)])
    ;   source_directory(Source),
        directory_file_path(Source, '..', Parent),
        directory_file_path(Parent, public, Candidate),
        absolute_file_name(Candidate, Absolute, [file_type(directory), access(read)])
    ),
    asserta(public_directory(Absolute)).

option_value([Arg|_], Prefix, _, Value) :-
    atom_concat(Prefix, Value, Arg),
    !.
option_value([_|Rest], Prefix, Default, Value) :-
    option_value(Rest, Prefix, Default, Value).
option_value([], _, Default, Default) :-
    nonvar(Default).

index_handler(_) :-
    serve_public_file('index.html', 'text/html; charset=utf-8').

javascript_handler(_) :-
    serve_public_file('app.js', 'text/javascript; charset=utf-8').

stylesheet_handler(_) :-
    serve_public_file('styles.css', 'text/css; charset=utf-8').

serve_public_file(Name, ContentType) :-
    public_directory(Public),
    directory_file_path(Public, Name, Path),
    setup_call_cleanup(
        open(Path, read, Stream, [encoding(utf8)]),
        read_string(Stream, _, Content),
        close(Stream)
    ),
    response_headers(ContentType),
    format('~s', [Content]).

health_handler(_) :-
    json_response(_{
        status: "ok",
        service: "schema-drift-lab",
        runtime: "swi-prolog"
    }).

simulate_handler(Request) :-
    http_parameters(Request, [
        total_events(Total, [integer, default(12000)]),
        v2_percent(V2, [integer, default(35)]),
        v3_percent(V3, [integer, default(25)]),
        error_percent(Error, [integer, default(8)]),
        slow_percent(Slow, [integer, default(12)]),
        raw_route_percent(RawRoute, [integer, default(18)]),
        slo_ms(Slo, [integer, default(750)]),
        max_series(MaxSeries, [integer, default(500)])
    ]),
    Input = _{
        total_events: Total,
        v2_percent: V2,
        v3_percent: V3,
        error_percent: Error,
        slow_percent: Slow,
        raw_route_percent: RawRoute,
        slo_ms: Slo,
        max_series: MaxSeries
    },
    simulate(Input, Result),
    json_response(Result).

json_response(Dict) :-
    response_headers('application/json; charset=utf-8'),
    json_write_dict(current_output, Dict, [width(0)]).

response_headers(ContentType) :-
    format('Content-type: ~w~n', [ContentType]),
    format('Cache-Control: no-store~n', []),
    format('Content-Security-Policy: default-src ''self''; script-src ''self''; style-src ''self''; img-src ''self'' data:; object-src ''none''; base-uri ''none''; frame-ancestors ''none''~n', []),
    format('Referrer-Policy: no-referrer~n', []),
    format('X-Content-Type-Options: nosniff~n', []),
    format('X-Frame-Options: DENY~n~n', []).
