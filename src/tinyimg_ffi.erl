-module(tinyimg_ffi).
-export([is_tty/0, system_cpus/0, monotonic_ms/0, unique_id/0, terminal_columns/0]).

is_tty() ->
    case io:columns() of
        {ok, _} -> true;
        _ -> false
    end.

system_cpus() ->
    case erlang:system_info(logical_processors) of
        N when is_integer(N), N > 0 -> N;
        _ -> 1
    end.

monotonic_ms() ->
    erlang:monotonic_time(millisecond).

unique_id() ->
    erlang:unique_integer([positive]).

terminal_columns() ->
    case io:columns() of
        {ok, N} when is_integer(N), N > 0 -> N;
        _ -> 80
    end.
