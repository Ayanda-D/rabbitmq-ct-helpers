%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is RabbitMQ Management Console.
%%
%%   The Initial Developer of the Original Code is GoPivotal, Inc.
%%   Copyright (c) 2010-2012 GoPivotal, Inc.  All rights reserved.
%%

-module(rabbit_mgmt_test_util).

-include("rabbit_mgmt_test.hrl").

-compile([nowarn_export_all, export_all]).

reset_management_settings(Config) ->
    rabbit_ct_broker_helpers:rpc(Config, 0, application, set_env,
                                 [rabbit, collect_statistics_interval, 5000]),
    Config.

merge_stats_app_env(Config, Interval, SampleInterval) ->
    Config1 = rabbit_ct_helpers:merge_app_env(
        Config, {rabbit, [{collect_statistics_interval, Interval}]}),
    rabbit_ct_helpers:merge_app_env(
      Config1, {rabbitmq_management_agent, [{sample_retention_policies,
                       [{global,   [{605, SampleInterval}]},
                        {basic,    [{605, SampleInterval}]},
                        {detailed, [{10, SampleInterval}]}] }]}).
http_get_from_node(Config, Node, Path) ->
    {ok, {{_HTTP, CodeAct, _}, Headers, ResBody}} =
        req(Config, Node, get, Path, [auth_header("guest", "guest")]),
    assert_code(?OK, CodeAct, "GET", Path, ResBody),
    decode(?OK, Headers, ResBody).


http_get(Config, Path) ->
    http_get(Config, Path, ?OK).

http_get(Config, Path, CodeExp) ->
    http_get(Config, Path, "guest", "guest", CodeExp).

http_get(Config, Path, User, Pass, CodeExp) ->
    {ok, {{_HTTP, CodeAct, _}, Headers, ResBody}} =
        req(Config, 0, get, Path, [auth_header(User, Pass)]),
    assert_code(CodeExp, CodeAct, "GET", Path, ResBody),
    decode(CodeExp, Headers, ResBody).

http_put(Config, Path, List, CodeExp) ->
    http_put_raw(Config, Path, format_for_upload(List), CodeExp).

http_put(Config, Path, List, User, Pass, CodeExp) ->
    http_put_raw(Config, Path, format_for_upload(List), User, Pass, CodeExp).

http_post(Config, Path, List, CodeExp) ->
    http_post_raw(Config, Path, format_for_upload(List), CodeExp).

http_post(Config, Path, List, User, Pass, CodeExp) ->
    http_post_raw(Config, Path, format_for_upload(List), User, Pass, CodeExp).

http_post_accept_json(Config, Path, List, CodeExp) ->
    http_post_accept_json(Config, Path, List, "guest", "guest", CodeExp).

http_post_accept_json(Config, Path, List, User, Pass, CodeExp) ->
    http_post_raw(Config, Path, format_for_upload(List), User, Pass, CodeExp,
          [{"Accept", "application/json"}]).

req(Config, Type, Path, Headers) ->
    req(Config, 0, Type, Path, Headers).

req(Config, Node, Type, Path, Headers) ->
    httpc:request(Type, {uri_base_from(Config, Node) ++ Path, Headers}, ?HTTPC_OPTS, []).

req(Config, Node, Type, Path, Headers, Body) ->
    httpc:request(Type, {uri_base_from(Config, Node) ++ Path, Headers, "application/json", Body},
                  ?HTTPC_OPTS, []).

uri_base_from(Config, Node) ->
    Port = mgmt_port(Config, Node),
    Prefix = get_uri_prefix(Config),
    Uri = rabbit_mgmt_format:print("http://localhost:~w~s/api", [Port, Prefix]),
    binary_to_list(Uri).

get_uri_prefix(Config) ->
    ErlNodeCnf = proplists:get_value(erlang_node_config, Config, []),
    MgmtCnf = proplists:get_value(rabbitmq_management, ErlNodeCnf, []),
    proplists:get_value(path_prefix, MgmtCnf, "").

auth_header(Username, Password) ->
    {"Authorization",
     "Basic " ++ binary_to_list(base64:encode(Username ++ ":" ++ Password))}.

amqp_port(Config) ->
    config_port(Config, tcp_port_amqp).

mgmt_port(Config, Node) ->
    config_port(Config, Node, tcp_port_mgmt).

config_port(Config, PortKey) ->
    config_port(Config, 0, PortKey).

config_port(Config, Node, PortKey) ->
    rabbit_ct_broker_helpers:get_node_config(Config, Node, PortKey).

http_put_raw(Config, Path, Body, CodeExp) ->
    http_upload_raw(Config, put, Path, Body, "guest", "guest", CodeExp, []).

http_put_raw(Config, Path, Body, User, Pass, CodeExp) ->
    http_upload_raw(Config, put, Path, Body, User, Pass, CodeExp, []).


http_post_raw(Config, Path, Body, CodeExp) ->
    http_upload_raw(Config, post, Path, Body, "guest", "guest", CodeExp, []).

http_post_raw(Config, Path, Body, User, Pass, CodeExp) ->
    http_upload_raw(Config, post, Path, Body, User, Pass, CodeExp, []).

http_post_raw(Config, Path, Body, User, Pass, CodeExp, MoreHeaders) ->
    http_upload_raw(Config, post, Path, Body, User, Pass, CodeExp, MoreHeaders).


http_upload_raw(Config, Type, Path, Body, User, Pass, CodeExp, MoreHeaders) ->
    {ok, {{_HTTP, CodeAct, _}, Headers, ResBody}} =
    req(Config, 0, Type, Path, [auth_header(User, Pass)] ++ MoreHeaders, Body),
    assert_code(CodeExp, CodeAct, Type, Path, ResBody),
    decode(CodeExp, Headers, ResBody).

http_delete(Config, Path, CodeExp) ->
    http_delete(Config, Path, "guest", "guest", CodeExp).

http_delete(Config, Path, User, Pass, CodeExp) ->
    {ok, {{_HTTP, CodeAct, _}, Headers, ResBody}} =
        req(Config, 0, delete, Path, [auth_header(User, Pass)]),
    assert_code(CodeExp, CodeAct, "DELETE", Path, ResBody),
    decode(CodeExp, Headers, ResBody).

format_for_upload(none) ->
    <<"">>;
format_for_upload(List) ->
    iolist_to_binary(mochijson2:encode({struct, List})).

assert_code(CodesExpected, CodeAct, Type, Path, Body) when is_list(CodesExpected) ->
    case lists:member(CodeAct, CodesExpected) of
        true ->
            ok;
        false ->
            error({expected, CodesExpected, got, CodeAct, type, Type,
                   path, Path, body, Body})
    end;
assert_code(CodeExp, CodeAct, Type, Path, Body) ->
    case CodeExp of
        CodeAct -> ok;
        _       -> error({expected, CodeExp, got, CodeAct, type, Type,
                          path, Path, body, Body})
    end.

decode(?OK, _Headers,  ResBody) -> cleanup(mochijson2:decode(ResBody));
decode(_,    Headers, _ResBody) -> Headers.

cleanup(L) when is_list(L) ->
    [cleanup(I) || I <- L];
cleanup({struct, I}) ->
    cleanup(I);
cleanup({K, V}) when is_binary(K) ->
    {list_to_atom(binary_to_list(K)), cleanup(V)};
cleanup(I) ->
    I.

assert_list(Exp, Act) ->
    case length(Exp) == length(Act) of
        true  -> ok;
        false -> error({expected, Exp, actual, Act})
    end,
    [case length(lists:filter(fun(ActI) -> test_item(ExpI, ActI) end, Act)) of
         1 -> ok;
         N -> error({found, N, ExpI, in, Act})
     end || ExpI <- Exp].

assert_item(Exp, Act) ->
    case test_item0(Exp, Act) of
        [] -> ok;
        Or -> error(Or)
    end.

test_item(Exp, Act) ->
    case test_item0(Exp, Act) of
        [] -> true;
        _  -> false
    end.

test_item0(Exp, Act) ->
    [{did_not_find, ExpI, in, Act} || ExpI <- Exp,
                                      not lists:member(ExpI, Act)].

assert_keys(Exp, Act) ->
    case test_key0(Exp, Act) of
        [] -> ok;
        Or -> error(Or)
    end.

test_key0(Exp, Act) ->
    [{did_not_find, ExpI, in, Act} || ExpI <- Exp,
                                      not proplists:is_defined(ExpI, Act)].
assert_no_keys(NotExp, Act) ->
    case test_no_key0(NotExp, Act) of
        [] -> ok;
        Or -> error(Or)
    end.

test_no_key0(Exp, Act) ->
    [{invalid_key, ExpI, in, Act} || ExpI <- Exp,
                                      proplists:is_defined(ExpI, Act)].
