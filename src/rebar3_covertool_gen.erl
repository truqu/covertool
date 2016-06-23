-module(rebar3_covertool_gen).

%% rebar3 plugin callbacks
-export([init/1, do/1, format_error/1]).

-include("covertool.hrl").
-include_lib("kernel/include/file.hrl").


%% ===================================================================
%% Rebar3 plugin callbacks
%% ===================================================================
init( State ) ->
    Options = [{module, ?MODULE},
               {namespace, covertool},
               {name, generate},
               {deps, [{default,app_discovery}]},
               {example, "rebar3 covertool generate"},
               {short_desc, "generate Cobertura output"},
               {desc, "Process the rebar3 cover generated .coverdata files, and produce an Cobertura XML into the _build/test/covertool/ directory for each application in the rebar3 project."},
               {profiles, [test]}],
    NewState = rebar_state:add_provider(State, providers:create(Options)),
    {ok, NewState}.


do(State) ->
    OutputFiles = output_files(),
    InputFiles = input_files(),
    Apps = rebar_state:project_apps(State),
    generate( OutputFiles, InputFiles, Apps ),
    {ok, State}.


format_error(Reason) ->
    io_lib:format("~p", [Reason]).


%% ===================================================================
%% Internal Functions
%% ===================================================================
output_files() ->
    filelib:wildcard( outdir() ++ "/*.xml" ).


input_files() ->
    CoverDataFiles = ["eunit.coverdata", "ct.coverdata"],
    [["_build/test/cover/" | File] || File <- CoverDataFiles].


generate( OutputFiles, InputFiles, Apps ) ->
    %% blow away any output files (if present), and make directory exist
    [file:delete( File ) || File <- OutputFiles],
    filelib:ensure_dir( outdir() ++  "/dummy" ),
    case generate_init( InputFiles, "_build/test/covertool.log" ) of
        {ok, LogFile} -> generate_apps( Apps, LogFile );
        Otherwise -> Otherwise
    end.

generate_init( InputFiles, LogFilePath ) ->
    case rebar_covertool:cover_init( LogFilePath ) of
        {ok, LogFile} ->
            generate_import( InputFiles, LogFile );
        Otherwise -> Otherwise
    end.

generate_import( [File | T], LogFile ) ->
    rebar_api:info( "Importing file ~s", [File] ),
    case cover:import( File ) of
        ok ->
            generate_import( T, LogFile );
        Otherwise ->
            rebar_api:info( "Error parsing file ~s", [File] ),
            rebar_api:info( "Error ~p", [Otherwise] ),
            generate_import( T, LogFile )
    end;
generate_import( [], LogFile ) ->
    {ok, LogFile}.


generate_apps( Apps, LogFile ) ->
    Result = lists:foldl( fun generate_app/2, ok, Apps ),
    file:close( LogFile ),
    Result.

generate_app( App, Result ) ->
    AppName = binary_to_atom( rebar_app_info:name( App ), latin1 ),
    OutputFile = outdir() ++ "/" ++ atom_to_list(AppName) ++ ".covertool.xml",
    SourceDir = filename:join( rebar_app_info:dir( App ), "src/" ),
    Config = #config{ appname = AppName,  output = OutputFile,
                      sources = [SourceDir] },
    case covertool:generate_report( Config, cover:imported_modules() ) of
        ok -> Result;
        Otherwise -> Otherwise
    end.

outdir() ->
    "_build/test/covertool".
