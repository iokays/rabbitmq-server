-module(rabbit_msg_store_vhost_sup).

-behaviour(supervisor2).

-export([start_link/4, init/1, add_vhost/2, client_init/5, start_vhost/5, successfully_recovered_state/2]).

start_link(Name, Dir, ClientRefs, StartupFunState) ->
    supervisor2:start_link({local, Name}, ?MODULE,
                           [Name, Dir, ClientRefs, StartupFunState]).

init([Name, Dir, ClientRefs, StartupFunState]) ->
    {ok, {{simple_one_for_one, 0, 1},
        [{rabbit_msg_store_vhost, {rabbit_msg_store_vhost_sup, start_vhost, 
                                   [Name, Dir, ClientRefs, StartupFunState]},
           transient, infinity, supervisor, [rabbit_msg_store]}]}}.


add_vhost(Name, VHost) ->
    supervisor2:start_child(Name, [VHost]).

start_vhost(Name, Dir, ClientRefs, StartupFunState, VHost) ->
    VHostName = get_vhost_name(Name, VHost),
    VHostDir = get_vhost_dir(Dir, VHost),
    ok = rabbit_file:ensure_dir(VHostDir),
    rabbit_msg_store:start_link(VHostName, VHostDir, 
                                ClientRefs, StartupFunState).


client_init(Server, Ref, MsgOnDiskFun, CloseFDsFun, VHost) ->
    VHostName = maybe_start_vhost(Server, VHost),
    rabbit_msg_store:client_init(VHostName, Ref, MsgOnDiskFun, CloseFDsFun).

maybe_start_vhost(Server, VHost) ->
    VHostName = get_vhost_name(Server, VHost),
    Trace = try throw(42) catch 42 -> erlang:get_stacktrace() end,
    case whereis(VHostName) of
        undefined -> add_vhost(Server, VHost);
        _         -> ok
    end,
    VHostName.

get_vhost_name(Name, VHost) ->
    VhostEncoded = encode_vhost(VHost),
    binary_to_atom(<<(atom_to_binary(Name, utf8))/binary, "_", VhostEncoded/binary>>, utf8).

get_vhost_dir(Dir, VHost) ->
    VhostEncoded = encode_vhost(VHost),
    binary_to_list(filename:join([Dir, VhostEncoded])).

encode_vhost(VHost) ->
    base64:encode(VHost).

successfully_recovered_state(Name, VHost) ->
    VHostName = get_vhost_name(Name, VHost),
    rabbit_msg_store:successfully_recovered_state(VHostName).

% force_recovery
% transform_dir