%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 2005-2009. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%
%%
-module(httpd_block).

-include("test_server.hrl").
-include("test_server_line.hrl").

%% General testcases bodies called from httpd_SUITE
-export([block_disturbing_idle/4, block_non_disturbing_idle/4,
	 block_503/4, block_disturbing_active/4, 
	 block_non_disturbing_active/4, 
	 block_disturbing_active_timeout_not_released/4, 
	 block_disturbing_active_timeout_released/4, 
	 block_non_disturbing_active_timeout_not_released/4,
	 block_non_disturbing_active_timeout_released/4,
	 disturbing_blocker_dies/4,
	 non_disturbing_blocker_dies/4, restart_no_block/4,
	 restart_disturbing_block/4, restart_non_disturbing_block/4
	]).

%% Help functions 
-export([do_block_server/4, do_block_nd_server/5, do_long_poll/6]).

-define(report(Label, Content), 
	inets:report_event(20, Label, test_case, 
			   [{module, ?MODULE}, {line, ?LINE} | Content])).


%%-------------------------------------------------------------------------
%% Test cases starts here.
%%-------------------------------------------------------------------------
block_disturbing_idle(_Type, Port, Host, Node) ->
    unblocked = get_admin_state(Node, Host, Port),
    block_server(Node, Host, Port),
    blocked = get_admin_state(Node, Host, Port),
    unblock_server(Node, Host, Port),
    unblocked = get_admin_state(Node, Host, Port).
%%--------------------------------------------------------------------
block_non_disturbing_idle(_Type, Port, Host, Node) ->
    unblocked = get_admin_state(Node, Host, Port),
    block_nd_server(Node, Host, Port),
    blocked = get_admin_state(Node, Host, Port),
    unblock_server(Node, Host, Port),
    unblocked = get_admin_state(Node, Host, Port).
%%--------------------------------------------------------------------
block_503(Type, Port, Host, Node) ->
    Req = "GET / HTTP/1.0\r\ndummy-host.ericsson.se:\r\n\r\n",
    unblocked = get_admin_state(Node, Host, Port),
    ok = httpd_test_lib:verify_request(Type, Host, Port, Node, Req, 
				  [{statuscode, 200},
				   {version, "HTTP/1.0"}]),
    ok = block_server(Node, Host, Port),
    blocked = get_admin_state(Node, Host, Port),
    ok = httpd_test_lib:verify_request(Type, Host, Port, Node, Req,  
				  [{statuscode, 503},
				   {version, "HTTP/1.0"}]),
    ok = unblock_server(Node, Host, Port),
    unblocked = get_admin_state(Node, Host, Port),
    ok = httpd_test_lib:verify_request(Type, Host, Port, Node, Req, 
				  [{statuscode, 200},
				   {version, "HTTP/1.0"}]).
%%--------------------------------------------------------------------
block_disturbing_active(Type, Port, Host, Node) ->
    process_flag(trap_exit, true),
    Pid = long_poll(Type, Host, Port, Node, 200, 60000),
    test_server:sleep(15000),
    block_server(Node, Host, Port),
    await_suite_failed_process_exit(Pid, "poller", 60000,
				    connection_closed),
    blocked = get_admin_state(Node, Host, Port),
    process_flag(trap_exit, false),
    ok.
%%--------------------------------------------------------------------
block_non_disturbing_active(Type, Port, Host, Node) ->
    process_flag(trap_exit, true),
    Poller = long_poll(Type, Host, Port, Node, 200, 60000),
    test_server:sleep(15000),
    ok = block_nd_server(Node, Host, Port),
    await_normal_process_exit(Poller, "poller", 60000),
    blocked = get_admin_state(Node, Host, Port),
    process_flag(trap_exit, false),
    ok.

%%--------------------------------------------------------------------
block_disturbing_active_timeout_not_released(Type, Port, Host, Node) ->
    process_flag(trap_exit, true),
    Poller = long_poll(Type, Host, Port, Node, 200, 60000),
    test_server:sleep(15000),
    Blocker = blocker(Node, Host, Port, 50000),
    await_normal_process_exit(Blocker, "blocker", 50000),
    await_normal_process_exit(Poller, "poller", 30000),
    blocked = get_admin_state(Node, Host, Port),
    process_flag(trap_exit, false),
    ok.

%%--------------------------------------------------------------------
block_disturbing_active_timeout_released(Type, Port, Host, Node) ->
    process_flag(trap_exit, true),
    Poller = long_poll(Type, Host, Port, Node, 200, 40000),
    test_server:sleep(5000),
    Blocker = blocker(Node, Host, Port, 10000),
    await_normal_process_exit(Blocker, "blocker", 15000),
    await_suite_failed_process_exit(Poller, "poller", 40000, 
					  connection_closed),
    blocked = get_admin_state(Node, Host, Port),
    process_flag(trap_exit, false),
    ok.
%%--------------------------------------------------------------------
block_non_disturbing_active_timeout_not_released(Type, Port, Host, Node) ->
    process_flag(trap_exit, true),
    Poller = long_poll(Type, Host, Port, Node, 200, 60000),
    test_server:sleep(5000),
    ok = block_nd_server(Node, Host, Port, 40000),
    await_normal_process_exit(Poller, "poller", 60000),
    blocked = get_admin_state(Node, Host, Port),
    process_flag(trap_exit, false),
    ok.

%%--------------------------------------------------------------------
block_non_disturbing_active_timeout_released(Type, Port, Host, Node) ->
    process_flag(trap_exit, true),
    Poller = long_poll(Type, Host, Port, Node, 200, 45000),
    test_server:sleep(5000),
    Blocker = blocker_nd(Node, Host, Port ,10000, {error,timeout}),
    await_normal_process_exit(Blocker, "blocker", 15000),
    await_normal_process_exit(Poller, "poller", 50000),
    unblocked = get_admin_state(Node, Host, Port),
    process_flag(trap_exit, false),
    ok.
%%--------------------------------------------------------------------
disturbing_blocker_dies(Type, Port, Host, Node) ->
    process_flag(trap_exit, true),
    Poller = long_poll(Type, Host, Port, Node, 200, 60000),
    test_server:sleep(5000),
    Blocker = blocker(Node, Host, Port, 10000),
    test_server:sleep(5000),
    exit(Blocker,simulate_blocker_crash),
    await_normal_process_exit(Poller, "poller", 60000),
    unblocked = get_admin_state(Node, Host, Port),
    process_flag(trap_exit, false),
    ok.

%%--------------------------------------------------------------------
non_disturbing_blocker_dies(Type, Port, Host, Node) ->
    process_flag(trap_exit, true),
    Poller = long_poll(Type, Host, Port, Node, 200, 60000),
    test_server:sleep(5000),  
    Blocker = blocker_nd(Node, Host, Port, 10000, ok),
    test_server:sleep(5000),
    exit(Blocker, simulate_blocker_crash),
    await_normal_process_exit(Poller, "poller", 60000),
    unblocked = get_admin_state(Node, Host, Port),
    process_flag(trap_exit, false),
    ok.
%%--------------------------------------------------------------------
restart_no_block(_, Port, Host, Node) ->
    {error,_Reason} = restart_server(Node, Host, Port).

%%--------------------------------------------------------------------
restart_disturbing_block(_, Port, Host, Node) ->
    ?report("restart_disturbing_block - get_admin_state (unblocked)", []),
    unblocked = get_admin_state(Node, Host, Port),
    ?report("restart_disturbing_block - block_server", []),
    ok = block_server(Node, Host, Port),
    ?report("restart_disturbing_block - restart_server", []),
    ok = restart_server(Node, Host, Port),
    ?report("restart_disturbing_block - unblock_server", []),
    ok = unblock_server(Node, Host, Port),
    ?report("restart_disturbing_block - get_admin_state (unblocked)", []),
    unblocked = get_admin_state(Node, Host, Port).

%%--------------------------------------------------------------------
restart_non_disturbing_block(_, Port, Host, Node) ->
    ?report("restart_non_disturbing_block - get_admin_state (unblocked)", []),
    unblocked = get_admin_state(Node, Host, Port),
    ?report("restart_non_disturbing_block - block_nd_server", []),
    ok = block_nd_server(Node, Host, Port),
    ?report("restart_non_disturbing_block - restart_server", []),
    ok = restart_server(Node, Host, Port),
    ?report("restart_non_disturbing_block - unblock_server", []),
    ok = unblock_server(Node, Host, Port),
    ?report("restart_non_disturbing_block - get_admin_state (unblocked)", []),
    unblocked = get_admin_state(Node, Host, Port).

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------
blocker(Node, Host, Port, Timeout) ->
    spawn_link(?MODULE, do_block_server,[Node, Host, Port,Timeout]).

do_block_server(Node, Host, Port, Timeout) ->
    ok = block_server(Node, Host, Port, Timeout),
    exit(normal).

blocker_nd(Node, Host, Port, Timeout, Reply) ->
    spawn_link(?MODULE, do_block_nd_server,
	       [Node, Host, Port, Timeout, Reply]).

do_block_nd_server(Node, Host, Port, Timeout, Reply) ->
    Reply = block_nd_server(Node, Host, Port, Timeout),
    exit(normal).

restart_server(Node, _Host, Port) ->
    Addr = undefined, 
    rpc:call(Node, httpd, restart, [Addr, Port]).

block_server(Node, _Host,  Port) ->
    Addr = undefined, 
    rpc:call(Node, httpd, block, [Addr, Port]).

block_server(Node, _Host, Port, Timeout) ->
    Addr = undefined, 
    rpc:call(Node, httpd, block, [Addr, Port, disturbing, Timeout]).

block_nd_server(Node, _Host, Port) ->
    Addr = undefined, 
    rpc:call(Node, httpd, block, [Addr, Port, non_disturbing]).

block_nd_server(Node, _Host, Port, Timeout) ->
    Addr = undefined, 
    rpc:call(Node, httpd, block, [Addr, Port, non_disturbing, Timeout]).

unblock_server(Node, _Host, Port) ->
    Addr = undefined, 
    rpc:call(Node, httpd, unblock, [Addr, Port]).

get_admin_state(Node,_Host,Port) ->
    Addr = undefined, 
    rpc:call(Node, httpd, get_admin_state, [Addr, Port]).

await_normal_process_exit(Pid, Name, Timeout) ->
    receive
	{'EXIT', Pid, normal} ->
	    ok;
	{'EXIT', Pid, Reason} ->
	    Err = 
		lists:flatten(
		  io_lib:format("expected normal exit, "
				"unexpected exit of ~s process: ~p",
				[Name, Reason])),
	    test_server:fail(Err)
    after Timeout ->
	   test_server:fail("timeout while waiting for " ++ Name)
    end.

await_suite_failed_process_exit(Pid, Name, Timeout, Why) ->
    receive 
	{'EXIT', Pid, {suite_failed, Why}} ->
	    ok;
	{'EXIT', Pid, Reason} ->
	    Err = 
		lists:flatten(
		  io_lib:format("expected connection_closed, "
				"unexpected exit of ~s process: ~p",
				[Name, Reason])),
	    test_server:fail(Err)
    after Timeout ->
	    test_server:fail("timeout while waiting for " ++ Name)
    end.
	  
long_poll(Type, Host, Port, Node, StatusCode, Timeout) ->
    spawn_link(?MODULE, do_long_poll, [Type, Host, Port, Node, 
				       StatusCode, Timeout]).

do_long_poll(Type, Host, Port, Node, StatusCode, Timeout) ->
    Mod  = "httpd_example",
    Func = "delay",
    Req  = lists:flatten(io_lib:format("GET /eval?" ++ Mod ++ ":" ++ Func ++ 
				       "(~p) HTTP/1.0\r\n\r\n",[30000])),
    case httpd_test_lib:verify_request(Type, Host, Port, Node, Req, 
			      [{statuscode, StatusCode},
			       {version, "HTTP/1.0"}], Timeout) of
	ok ->
	    exit(normal);
	Reason ->
	    test_server:fail(Reason)
    end.





