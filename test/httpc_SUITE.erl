%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 2004-2009. All Rights Reserved.
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

-module(httpc_SUITE).
-author('ingela@erix.ericsson.se').

-include("test_server.hrl").
-include("test_server_line.hrl").

-include_lib("kernel/include/file.hrl").

%% Note: This directive should only be used in test suites.
-compile(export_all).

%% Test server specific exports
-define(PROXY_URL, "http://www.erlang.org").
-define(PROXY, "www-proxy.ericsson.se").
-define(PROXY_PORT, 8080).
-define(IP_PORT, 8998).
-define(SSL_PORT, 8999).
-define(NOT_IN_USE_PORT, 8997).
-define(LOCAL_HOST, {127,0,0,1}).
-define(IPV6_LOCAL_HOST, "0:0:0:0:0:0:0:1").
-define(URL_START, "http://localhost:").
-define(SSL_URL_START, "https://localhost:").
-define(CR, $\r).
-define(LF, $\n).
-define(HTTP_MAX_HEADER_SIZE, 10240).


%%--------------------------------------------------------------------
%% all(Arg) -> [Doc] | [Case] | {skip, Comment}
%% Arg - doc | suite
%% Doc - string()
%% Case - atom() 
%%	Name of a test case function. 
%% Comment - string()
%% Description: Returns documentation/test cases in this test suite
%%		or a skip tuple if the platform is not supported.  
%%--------------------------------------------------------------------
all(doc) ->
    ["Test the http client in the intes application."];
all(suite) ->
    [
     proxy_options, 
     proxy_head, 
     proxy_get, 
     proxy_trace, 
     proxy_post,
     proxy_put, 
     proxy_delete,
     proxy_auth,
     proxy_headers,
     proxy_emulate_lower_versions,
     http_options, 
     http_head, 
     http_get, 
     http_post,
     http_dummy_pipe,
     http_inets_pipe,
     http_trace,
     http_async,
     http_save_to_file,
     http_save_to_file_async,
     http_headers,
     http_headers_dummy,
     http_bad_response,
     ssl_head, 
     ssl_get, 
     ssl_trace, 
     http_redirect, 
     http_redirect_loop,
     http_internal_server_error,
     http_userinfo,
     http_cookie,
     http_server_does_not_exist,
     http_invalid_http,
     http_emulate_lower_versions,
     http_relaxed,
     page_does_not_exist, 
     proxy_page_does_not_exist, 
     proxy_https_not_supported,
     http_stream,
     http_stream_once,
     proxy_stream,
     parse_url,
     options,
     ipv6,
     headers_as_is,
     tickets
    ].
 
%%--------------------------------------------------------------------
%% Function: init_per_suite(Config) -> Config
%% Config - [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Description: Initiation before the whole suite
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    PrivDir = ?config(priv_dir, Config),
    DataDir = ?config(data_dir, Config),
    ServerRoot = filename:join(PrivDir, "server_root"),
    DocRoot = filename:join(ServerRoot, "htdocs"),
    IpConfFile = integer_to_list(?IP_PORT) ++ ".conf",
    SslConfFile = integer_to_list(?SSL_PORT) ++ ".conf",
    
    setup_server_dirs(ServerRoot, DocRoot, DataDir),
    create_config(IpConfFile, ip_comm, ?IP_PORT, PrivDir, ServerRoot, 
		  DocRoot, DataDir),
    create_config(SslConfFile, ssl, ?SSL_PORT, PrivDir, ServerRoot, 
		  DocRoot, DataDir),

    Cgi = case test_server:os_type() of
	      {win32, _} ->
		  filename:join([ServerRoot, "cgi-bin", "cgi_echo.exe"]);
	      _ ->
		  filename:join([ServerRoot, "cgi-bin", "cgi_echo"])
	  end,
    
    {ok, FileInfo} = file:read_file_info(Cgi),
    ok = file:write_file_info(Cgi, 
			      FileInfo#file_info{mode = 8#00755}),

    [{server_root, ServerRoot}, {doc_root, DocRoot},
     {local_port, ?IP_PORT}, {local_ssl_port, ?SSL_PORT}
	 | Config].

%%--------------------------------------------------------------------
%% Function: end_per_suite(Config) -> _
%% Config - [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Description: Cleanup after the whole suite
%%--------------------------------------------------------------------
end_per_suite(Config) ->
    PrivDir = ?config(priv_dir, Config), 	
    inets_test_lib:del_dirs(PrivDir),
    application:stop(inets),
    application:stop(ssl),
    ok.

%%--------------------------------------------------------------------
%% Function: init_per_testcase(Case, Config) -> Config
% Case - atom()
%%   Name of the test case that is about to be run.
%% Config - [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% Description: Initiation before each test case
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_testcase(Case, Config) ->
    io:format(user, "~n~n*** INIT ~w:~w ***~n~n", [?MODULE,Case]),
    PrivDir = ?config(priv_dir, Config),
    application:stop(inets),
    Dog = test_server:timetrap(inets_test_lib:minutes(10)),
    TmpConfig = lists:keydelete(watchdog, 1, Config),
    IpConfFile = integer_to_list(?IP_PORT) ++ ".conf",
    SslConfFile = integer_to_list(?SSL_PORT) ++ ".conf",

    NewConfig = 
	case atom_to_list(Case) of
	    "ssl" ++ _ ->
		application:stop(ssl),
		TmpConfig2 = 
		    lists:keydelete(local_ssl_server, 1, TmpConfig),
		Server = 
		    %% Will start inets 
		inets_test_lib:start_http_server(
		  filename:join(PrivDir,
				SslConfFile)),
		[{watchdog, Dog}, {local_ssl_server, Server} | TmpConfig2];
	    "proxy" ++ Rest ->
		   case Rest of			       
		       "_https_not_supported" ->	
			   inets:start(),
			   case (catch application:start(ssl)) of
			       ok ->
				   [{watchdog, Dog} | TmpConfig];
			       _ ->
				  [{skip, 
				    "SSL does not seem to be supported"} 
				   | TmpConfig]
			   end;
		       _ ->
			   case is_proxy_available(?PROXY, ?PROXY_PORT) of
			       true ->
				   inets:start(),
				   [{watchdog, Dog} | TmpConfig];
			       false ->
				   [{skip, "Failed to contact proxy"} | 
				    TmpConfig]
			   end
		   end;
	    _ -> 
		TmpConfig2 = lists:keydelete(local_server, 1, TmpConfig),
		Server = 
		    %% Will start inets 
		    inets_test_lib:start_http_server(
		      filename:join(PrivDir, IpConfFile)),
		[{watchdog, Dog}, {local_server, Server} | TmpConfig2]
	end,
    
    http:set_options([{proxy, {{?PROXY, ?PROXY_PORT}, 
			       ["localhost", ?IPV6_LOCAL_HOST]}}]),
    inets:enable_trace(max, io),
    NewConfig.

%%--------------------------------------------------------------------
%% Function: end_per_testcase(Case, Config) -> _
%% Case - atom()
%%   Name of the test case that is about to be run.
%% Config - [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Description: Cleanup after each test case
%%--------------------------------------------------------------------
end_per_testcase(http_save_to_file, Config) ->
    PrivDir = ?config(priv_dir, Config), 	
    FullPath = filename:join(PrivDir, "dummy.html"),
    file:delete(FullPath),
    finish(Config);
	
end_per_testcase(_, Config) ->
    finish(Config).

finish(Config) ->
    Dog = ?config(watchdog, Config),
    case Dog of 
	undefined ->
	    ok;
	_ ->
	    test_server:timetrap_cancel(Dog)
    end.

%%-------------------------------------------------------------------------
%% Test cases starts here.
%%-------------------------------------------------------------------------

tickets(doc) ->
    ["."];
tickets(suite) ->
    [
     hexed_query_otp_6191, 
     empty_body_otp_6243, 
     empty_response_header_otp_6830, 
     transfer_encoding_otp_6807,
     proxy_not_modified_otp_6821, 
     no_content_204_otp_6982,
     missing_CR_otp_7304,
     otp_7883,
     otp_8154
    ].


%%-------------------------------------------------------------------------

http_options(doc) ->
    ["Test http options request against local server."];
http_options(suite) ->
    [];
http_options(Config) when is_list(Config) ->
    {skip, "Not supported by httpd"}.

http_head(doc) ->
    ["Test http head request against local server."];
http_head(suite) ->
    [];
http_head(Config) when is_list(Config) ->
    case ?config(local_server, Config) of 
	ok ->
	    Port = ?config(local_port, Config),
	    URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    case http:request(head, {URL, []}, [], []) of
		{ok, {{_,200,_}, [_ | _], []}} ->
		    ok;
		{ok, WrongReply} ->
		    test_server:fail({wrong_reply, WrongReply});
		Error ->
		    test_server:fail({failed, Error})
	    end;
	  _ ->
	      {skip, "Failed to start local http-server"}
      end.  
%%-------------------------------------------------------------------------
http_get(doc) ->
    ["Test http get request against local server"];
http_get(suite) ->
    [];
http_get(Config) when is_list(Config) ->
  case ?config(local_server, Config) of 
	ok ->
	  Port = ?config(local_port, Config),
	  URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	  Timeout = timer:seconds(1), 
	  ConnTimeout = Timeout + timer:seconds(1), 
	  {ok, {{_,200,_}, [_ | _], Body = [_ | _]}} =
	      http:request(get, {URL, []}, 
			   [{timeout, Timeout}, {connect_timeout, ConnTimeout}], []),
	  %% eqvivivalent to http:request(get, {URL, []}, [], []),
	  inets_test_lib:check_body(Body),
	  {ok, {{_,200,_}, [_ | _], Bin}} =
	      http:request(get, {URL, []}, [], [{body_format, binary}]),
	  case Bin of
	      Bin when is_binary(Bin) ->
		  ok;
	      _ ->
		  test_server:fail(body_format_not_binary)
	  end;
      _ ->
	  {skip, "Failed to start local http-server"}
  end.  

%%-------------------------------------------------------------------------
http_post(doc) ->
    ["Test http post request against local server. We do in this case"
    " only care about the client side of the the post. The server"
    " script will not actually use the post data."];
http_post(suite) ->
    [];
http_post(Config) when is_list(Config) ->
  case ?config(local_server, Config) of 
      ok -> 
	  Port = ?config(local_port, Config),
	  
	  URL = case test_server:os_type() of
		    {win32, _} ->
			?URL_START ++ integer_to_list(Port) ++ 
			    "/cgi-bin/cgi_echo.exe";
		    _ ->
			?URL_START ++ integer_to_list(Port) ++ 
			    "/cgi-bin/cgi_echo"	       
		
		end,
	  %% Cgi-script expects the body length to be 100 
	  Body = lists:duplicate(100, "1"),
	  
	  {ok, {{_,200,_}, [_ | _], [_ | _]}} =
	      http:request(post, {URL, [{"expect","100-continue"}],
				  "text/plain", Body}, [], []),
      
	  {ok, {{_,504,_}, [_ | _], []}} =
	      http:request(post, {URL, [{"expect","100-continue"}],
				  "text/plain", "foobar"}, [], []);
      _ ->
	  {skip, "Failed to start local http-server"}
  end.  

%%-------------------------------------------------------------------------
http_emulate_lower_versions(doc) ->
    ["Perform request as 0.9 and 1.0 clients."];
http_emulate_lower_versions(suite) ->
    [];
http_emulate_lower_versions(Config) when is_list(Config) ->
    case ?config(local_server, Config) of 
	ok ->
	    Port = ?config(local_port, Config),
	    URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    {ok, Body0} =
  		http:request(get, {URL, []}, [{version, "HTTP/0.9"}], []),
	    inets_test_lib:check_body(Body0),
 	    {ok, {{"HTTP/1.0", 200, _}, [_ | _], Body1 = [_ | _]}} =
		http:request(get, {URL, []}, [{version, "HTTP/1.0"}], []),
	    inets_test_lib:check_body(Body1),
	    {ok, {{"HTTP/1.1", 200, _}, [_ | _], Body2 = [_ | _]}} =
		http:request(get, {URL, []}, [{version, "HTTP/1.1"}], []),
	    inets_test_lib:check_body(Body2);
        _->
	    {skip, "Failed to start local http-server"}
    end.

%%-------------------------------------------------------------------------
http_relaxed(doc) ->
    ["Test relaxed mode"];
http_relaxed(suite) ->
    [];
http_relaxed(Config) when is_list(Config) ->
    ok = http:set_options([{ipv6, disabled}]), % also test the old option 
    %% ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
	       {port, ServerPort} ->
		   ServerPort
	   end,
    
    URL = ?URL_START ++ integer_to_list(Port) ++ 
	"/missing_reason_phrase.html",
        
    {error, Reason} =
	http:request(get, {URL, []}, [{relaxed, false}], []),

    test_server:format("Not relaxed: ~p~n", [Reason]),
    
    {ok, {{_, 200, _}, [_ | _], [_ | _]}} =
	http:request(get, {URL, []}, [{relaxed, true}], []),

    DummyServerPid ! stop,
    ok = http:set_options([{ipv6, enabled}]),   
    %% ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.


%%-------------------------------------------------------------------------
http_dummy_pipe(doc) ->
    ["Test pipelining code."];
http_dummy_pipe(suite) ->
    [];
http_dummy_pipe(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
	       {port, ServerPort} ->
			   ServerPort
	   end,
   
    URL = ?URL_START ++ integer_to_list(Port) ++ "/foobar.html",

    test_pipeline(URL),

    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.

http_inets_pipe(doc) ->
    ["Test pipelining code."];
http_inets_pipe(suite) ->
    [];
http_inets_pipe(Config) when is_list(Config) ->
    
    case ?config(local_server, Config) of 
	ok ->
	  Port = ?config(local_port, Config),
	  URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    test_pipeline(URL); 
	_ ->
	    {skip, "Failed to start local http-server"}
    end.

test_pipeline(URL) ->
    
    http:set_options([{pipeline_timeout, 50000}]),
    
    {ok, RequestId1} = 
	http:request(get, {URL, []}, [], [{sync, false}]),
    test_server:format("RequestId1: ~p~n", [RequestId1]),

    %% Make sure pipeline is initiated
    test_server:sleep(4000),

    {ok, RequestId2} = 
	http:request(get, {URL, []}, [], [{sync, false}]),
    test_server:format("RequestId2: ~p~n", [RequestId2]),

    {ok, {{_,200,_}, [_ | _], [_ | _]}}
	= http:request(get, {URL, []}, [], []),
    receive 
	{http, {RequestId1, {{_, 200, _}, _, _}}} ->
	    receive
		{http, {RequestId2, {{_, 200, _}, _, _}}} ->
		    ok;
		{http, Msg1} ->
		    test_server:fail(Msg1)
	    end;
	{http, {RequestId2, {{_, 200, _}, _, _}}} ->
	    receive
		{http, {RequestId1, {{_, 200, _}, _, _}}} ->
		    ok;
		{http, Msg2} ->
		    test_server:fail(Msg2)
		    end; 
	{http, Msg3} ->
		    test_server:fail(Msg3)
    end,
    
    {ok, RequestId3} = 
		http:request(get, {URL, []}, [], [{sync, false}]),
    test_server:format("RequestId3: ~p~n", [RequestId3]),
    {ok, RequestId4} = 
	http:request(get, {URL, []}, [], [{sync, false}]),
    test_server:format("RequestId4: ~p~n", [RequestId4]),
    ok = http:cancel_request(RequestId3),
    receive 
	{http, {RequestId3, _}} ->
		    test_server:fail(http_cancel_request_failed)
    after 3000 ->
	    ok
    end,
    Body = 
	receive 
	   Res = {http, {RequestId4, {{_, 200, _}, _, BinBody4}}} ->
		test_server:format(" Receive : ~p~n", [Res]),
		BinBody4;
	    {http, Msg4} ->
		test_server:fail(Msg4)
	end,
    inets_test_lib:check_body(binary_to_list(Body)),
   
    receive 
	{http, Any} ->
	    test_server:fail({unexpected_message, Any})
    after 500 ->
	    ok
    end.    
%%-------------------------------------------------------------------------
http_trace(doc) ->
    ["Perform a TRACE request that goes through a proxy."];
http_trace(suite) ->
    [];
http_trace(Config) when is_list(Config) ->
    case ?config(local_server, Config) of 
	ok ->
	    Port = ?config(local_port, Config),
	    URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    case http:request(trace, {URL, []}, [], []) of
		{ok, {{_,200,_}, [_ | _], "TRACE /dummy.html" ++ _}} ->
		    ok;
		{ok, {{_,200,_}, [_ | _], WrongBody}} ->
		    test_server:fail({wrong_body, WrongBody});
		{ok, WrongReply} ->
		    test_server:fail({wrong_reply, WrongReply});
		Error ->
		    test_server:fail({failed, Error})
	    end;
	_ ->
	    {skip, "Failed to start local http-server"}
    end.  
%%-------------------------------------------------------------------------
http_async(doc) ->
    ["Test an asynchrony http request."];
http_async(suite) ->
    [];
http_async(Config) when is_list(Config) ->
    case ?config(local_server, Config) of 
	ok ->
	    Port = ?config(local_port, Config),
	    URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    {ok, RequestId} = 
		http:request(get, {URL, []}, [], [{sync, false}]),
	    
	    Body = 
		receive 
		    {http, {RequestId, {{_, 200, _}, _, BinBody}}} ->
			BinBody;
		    {http, Msg} ->
			test_server:fail(Msg)
		end,
	    
	    inets_test_lib:check_body(binary_to_list(Body)),
	    
	    {ok, NewRequestId} = 
		http:request(get, {URL, []}, [], [{sync, false}]),
	    ok = http:cancel_request(NewRequestId),
	    receive 
		{http, {NewRequestId, _NewResult}} ->
		    test_server:fail(http_cancel_request_failed)
	    after 3000 ->
		    ok
	    end;
	_ ->
	    {skip, "Failed to start local http-server"}
    end.  

%%-------------------------------------------------------------------------
http_save_to_file(doc) ->
    ["Test to save the http body to a file"];
http_save_to_file(suite) ->
    [];
http_save_to_file(Config) when is_list(Config) ->
    case ?config(local_server, Config) of 
	ok ->
	    PrivDir = ?config(priv_dir, Config),
	    FilePath = filename:join(PrivDir, "dummy.html"),
	    Port = ?config(local_port, Config),
	    URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    {ok, saved_to_file} 
		= http:request(get, {URL, []}, [], [{stream, FilePath}]),
	    {ok, Bin} = file:read_file(FilePath), 
	    {ok, {{_,200,_}, [_ | _], Body}} = http:request(URL),
	    Bin == Body;
	_ ->
	    {skip, "Failed to start local http-server"}
    end.  


%%-------------------------------------------------------------------------
http_save_to_file_async(doc) ->
    ["Test to save the http body to a file"];
http_save_to_file_async(suite) ->
    [];
http_save_to_file_async(Config) when is_list(Config) ->
    case ?config(local_server, Config) of 
	ok ->
	    PrivDir = ?config(priv_dir, Config),
	    FilePath = filename:join(PrivDir, "dummy.html"),
	    Port = ?config(local_port, Config),
	    URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    {ok, RequestId} = http:request(get, {URL, []}, [], 
					   [{stream, FilePath}, 
					    {sync, false}]),
	    receive
		{http, {RequestId, saved_to_file}} ->
		    ok;
		{http, Msg} ->
		    test_server:fail(Msg)
	    end,

	    {ok, Bin} = file:read_file(FilePath), 
	    {ok, {{_,200,_}, [_ | _], Body}} = http:request(URL),
	    Bin == Body;
	_ ->
	    {skip, "Failed to start local http-server"}
    end.  
%%-------------------------------------------------------------------------
http_headers(doc) ->
    ["Use as many request headers as possible not used in proxy_headers"];
http_headers(suite) ->
    [];
http_headers(Config) when is_list(Config) ->
    
    case ?config(local_server, Config) of 
	ok ->
	    Port = ?config(local_port, Config),
	    URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    DocRoot = ?config(doc_root, Config),
	    {ok, FileInfo} = 
		file:read_file_info(filename:join([DocRoot,"dummy.html"])),
	    CreatedSec = 
		calendar:datetime_to_gregorian_seconds(
		  FileInfo#file_info.mtime),
	    
	    Mod = httpd_util:rfc1123_date(
		    calendar:gregorian_seconds_to_datetime(
		      CreatedSec-1)),
	    
	    Date = httpd_util:rfc1123_date({date(), time()}),
	    
	    {ok, {{_,200,_}, [_ | _], [_ | _]}} =
		http:request(get, {URL, [{"If-Modified-Since",
					  Mod}, 
					 {"From","webmaster@erlang.se"},
					 {"Date", Date}
					]}, [], []),
	    
	    Mod1 =  httpd_util:rfc1123_date(
		      calendar:gregorian_seconds_to_datetime(
			CreatedSec+1)),
	    
	    {ok, {{_,200,_}, [_ | _], [_ | _]}} =
		http:request(get, {URL, [{"If-UnModified-Since",
					  Mod1}
					]}, [], []),
	    
	    Tag = httpd_util:create_etag(FileInfo),
	    
	    
	    {ok, {{_,200,_}, [_ | _], [_ | _]}} =
		http:request(get, {URL, [{"If-Match",
					  Tag}
					]}, [], []),

	    {ok, {{_,200,_}, [_ | _], _}} =
		     http:request(get, {URL, [{"If-None-Match",
					       "NotEtag,NeihterEtag"},
					      {"Connection", "Close"}
					     ]}, [], []),
	    ok;
		     _ ->
	    {skip, "Failed to start local http-server"}
    end.

%%-------------------------------------------------------------------------
http_headers_dummy(doc) ->
    ["Test the code for handling headers we do not want/can send "
     "to a real server. Note it is not logical to send"
     "all of these headers together, we only want to test that" 
     "the code for handling headers will not crash."];
http_headers_dummy(suite) ->
    [];
http_headers_dummy(Config) when is_list(Config) -> 
    ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
	       {port, ServerPort} ->
			   ServerPort
	   end,
    
    URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy_headers.html",
    
    Foo = http_chunk:encode("foobar") ++ 
	binary_to_list(http_chunk:encode_last()),
    FooBar =  Foo ++ "\r\n\r\nOther:inets_test\r\n\r\n",

    UserPasswd = base64:encode_to_string("Alladin:Sesame"),
    Auth = "Basic " ++ UserPasswd,

    %% The dummy server will ignore the headers, we only want to test
    %% that the client header-handling code. This would not
    %% be a vaild http-request!
    {ok, {{_,200,_}, [_ | _], [_|_]}} = 
	http:request(post, 
		     {URL, 
		      [{"Via",
			"1.0 fred, 1.1 nowhere.com (Apache/1.1)"}, 
		       {"Warning","1#pseudonym foobar"},
		       {"Vary","*"},
		       {"Upgrade","HTTP/2.0"},
		       {"Pragma", "1#no-cache"},
		       {"Cache-Control", "no-cache"},
		       {"Connection", "close"},
		       {"Date", "Sat, 29 Oct 1994 19:43:31 GMT"},
		       {"Accept", " text/plain; q=0.5, text/html"},
		       {"Accept-Language", "en"},
		       {"Accept-Encoding","chunked"},
		       {"Accept-Charset", "ISO8859-1"},
		       {"Authorization", Auth},
		       {"Expect", "1#100-continue"},
		       {"User-Agent","inets"},
		       {"Transfer-Encoding","chunked"},
		       {"Range", " bytes=0-499"},
		       {"If-Range", "Sat, 29 Oct 1994 19:43:31 GMT"},
		       {"If-Match", "*"},
		       {"Content-Type", "text/plain"},
		       {"Content-Encoding", "chunked"},
		       {"Content-Length", "6"},
		       {"Content-Language", "en"},
		       {"Content-Location", "http://www.foobar.se"},
		       {"Content-MD5", 
			"104528739076276072743283077410617235478"},
		       {"Content-Range", "bytes 0-499/1234"},
		       {"Allow", "GET"},
		       {"Proxy-Authorization", Auth},
		       {"Expires", "Sat, 29 Oct 1994 19:43:31 GMT"},
		       {"Upgrade", "HTTP/2.0"},
		       {"Last-Modified", "Sat, 29 Oct 1994 19:43:31 GMT"},
		       {"Trailer","1#User-Agent"}
		      ], "text/plain", FooBar}, 
		     [], []),
    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.
    

%%-------------------------------------------------------------------------
http_bad_response(doc) ->
    ["Test what happens when the server does not follow the protocol"];
http_bad_response(suite) ->
    [];
http_bad_response(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
	       {port, ServerPort} ->
		   ServerPort
	   end,
    
    URL = ?URL_START ++ integer_to_list(Port) ++ "/missing_crlf.html",
    
    URL1 = ?URL_START ++ integer_to_list(Port) ++ "/wrong_statusline.html",
    
    {error, timeout} = http:request(get, {URL, []}, [{timeout, 400}], []),
      
    {error, Reason} = http:request(URL1),
    
    test_server:format("Wrong Statusline: ~p~n", [Reason]),

    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.


%%-------------------------------------------------------------------------
ssl_head(doc) ->
    ["Same as http_head/1 but over ssl sockets."];
ssl_head(suite) ->
    [];
ssl_head(Config) when is_list(Config) ->   
    case ?config(local_ssl_server, Config) of 
 	ok ->
	    DataDir = ?config(data_dir, Config),
	    Port = ?config(local_ssl_port, Config),
	    URL = ?SSL_URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    CertFile = filename:join(DataDir, "ssl_client_cert.pem"),
	    SSLOptions = [{certfile, CertFile}, {keyfile, CertFile}],
	    {ok, {{_,200, _}, [_ | _], []}} =
		http:request(head, {URL, []}, [{ssl, SSLOptions}], []);
 	{ok, _} ->
 	    {skip, "Failed to start local http-server"};
 	_ ->
 	    {skip, "Failed to start SSL"}
    end.  
%%-------------------------------------------------------------------------
ssl_get(doc) ->
    ["Same as http_get/1 but over ssl sockets."];
ssl_get(suite) ->
    [];
ssl_get(Config) when is_list(Config) ->
    case ?config(local_ssl_server, Config) of 
	ok ->
	    DataDir = ?config(data_dir, Config),
 	    Port = ?config(local_ssl_port, Config),
	    URL = ?SSL_URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    CertFile = filename:join(DataDir, "ssl_client_cert.pem"),
	    SSLOptions = [{certfile, CertFile}, {keyfile, CertFile}],
	     {ok, {{_,200, _}, [_ | _], Body = [_ | _]}} =
		 http:request(get, {URL, []}, [{ssl, SSLOptions}], []),
	     inets_test_lib:check_body(Body);
	 {ok, _} ->
	     {skip, "Failed to start local http-server"}; 
	 _ ->
	     {skip, "Failed to start SSL"}
     end.
%%-------------------------------------------------------------------------
ssl_trace(doc) ->
    ["Same as http_trace/1 but over ssl sockets."];
ssl_trace(suite) ->
    [];
ssl_trace(Config) when is_list(Config) ->
    case ?config(local_ssl_server, Config) of 
	ok ->
	    DataDir = ?config(data_dir, Config),
 	    Port = ?config(local_ssl_port, Config),
	    URL = ?SSL_URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    CertFile = filename:join(DataDir, "ssl_client_cert.pem"),
	    SSLOptions = [{certfile, CertFile}, {keyfile, CertFile}],
	    case http:request(trace, {URL, []}, [{ssl, SSLOptions}], []) of
		{ok, {{_,200, _}, [_ | _], "TRACE /dummy.html" ++ _}} ->
		    ok;
		{ok, {{_,200,_}, [_ | _], WrongBody}} ->
		    test_server:fail({wrong_body, WrongBody});
		{ok, WrongReply} ->
		    test_server:fail({wrong_reply, WrongReply});
		Error ->
		    test_server:fail({failed, Error})
	    end;
	{ok, _} ->
	    {skip, "Failed to start local http-server"}; 
	_ ->
	    {skip, "Failed to start SSL"}
    end.
%%-------------------------------------------------------------------------
http_redirect(doc) ->
    ["Test redirect with dummy server as httpd does not implement"
     " server redirect"];
http_redirect(suite) ->
    [];
http_redirect(Config) when is_list(Config) ->
    case ?config(local_server, Config) of 
	ok ->
	    ok = http:set_options([{ipfamily, inet}]),
	    DummyServerPid = dummy_server(self(), ipv4),
	    
	    Port = receive 
		       {port, ServerPort} ->
			   ServerPort
		   end,
    
	    URL300 = ?URL_START ++ integer_to_list(Port) ++ "/300.html",
    
	    {ok, {{_,200,_}, [_ | _], [_|_]}} 
 		= http:request(get, {URL300, []}, [], []),
	    
	    {ok, {{_,300,_}, [_ | _], _}} 
		= http:request(get, {URL300, []}, [{autoredirect, false}],
			       []),

	    URL301 = ?URL_START ++ integer_to_list(Port) ++ "/301.html",


	    {ok, {{_,200,_}, [_ | _], [_|_]}} 
 		= http:request(get, {URL301, []}, [], []),
	    
	    {ok, {{_,200,_}, [_ | _], []}} 
 		= http:request(head, {URL301, []}, [], []),
	    
	    {ok, {{_,301,_}, [_ | _], [_|_]}} 
 		= http:request(post, {URL301, [],"text/plain", "foobar"},
			       [], []),

	    URL302 = ?URL_START ++ integer_to_list(Port) ++ "/302.html",
	 
	    {ok, {{_,200,_}, [_ | _], [_|_]}} 
 		= http:request(get, {URL302, []}, [], []),	 
	    
	    {ok, {{_,200,_}, [_ | _], []}} 
 		= http:request(head, {URL302, []}, [], []),	 
	    
	    {ok, {{_,302,_}, [_ | _], [_|_]}} 
 		= http:request(post, {URL302, [],"text/plain", "foobar"},
			       [], []),
   
	    URL307 = ?URL_START ++ integer_to_list(Port) ++ "/307.html",

	    {ok, {{_,200,_}, [_ | _], [_|_]}} 
 		= http:request(get, {URL307, []}, [], []),
	
	    {ok, {{_,200,_}, [_ | _], []}} 
 		= http:request(head, {URL307, []}, [], []),
	    
	    {ok, {{_,307,_}, [_ | _], [_|_]}} 
 		= http:request(post, {URL307, [],"text/plain", "foobar"},
			       [], []),
	    
	    DummyServerPid ! stop,
	    ok = http:set_options([{ipfamily, inet6fb4}]);   % ********** ipfamily = inet6 *************
	_ ->
	    {skip, "Failed to start local http-server"}
    end.


%%-------------------------------------------------------------------------
http_redirect_loop(doc) ->
    ["Test redirect loop detection"];
http_redirect_loop(suite) ->
    [];
http_redirect_loop(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
 	       {port, ServerPort} ->
 		   ServerPort
 	   end,
    
    URL = ?URL_START ++ integer_to_list(Port) ++ "/redirectloop.html",
    
    {ok, {{_,300,_}, [_ | _], _}} 
 	= http:request(get, {URL, []}, [], []),
    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.

%%-------------------------------------------------------------------------
http_internal_server_error(doc) ->
    ["Test 50X codes"];
http_internal_server_error(suite) ->
    [];
http_internal_server_error(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
 	       {port, ServerPort} ->
 		   ServerPort
 	   end,
    
    URL500 = ?URL_START ++ integer_to_list(Port) ++ "/500.html",
    
    {ok, {{_,500,_}, [_ | _], _}} 
 	= http:request(get, {URL500, []}, [], []),


    URL503 = ?URL_START ++ integer_to_list(Port) ++ "/503.html",

    %% Used to be able to make the service available after retry.
    ets:new(unavailable, [named_table, public, set]),
    ets:insert(unavailable, {503, unavailable}),
    
    {ok, {{_,200, _}, [_ | _], [_|_]}} =
	http:request(get, {URL503, []}, [], []),
    
    ets:insert(unavailable, {503, long_unavailable}),

    {ok, {{_,503, _}, [_ | _], [_|_]}} =
	http:request(get, {URL503, []}, [], []),

    ets:delete(unavailable),
    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.


%%-------------------------------------------------------------------------
http_userinfo(doc) ->
    ["Test user info e.i. http://user:passwd@host:port/"];
http_userinfo(suite) ->
    [];
http_userinfo(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),

    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
 	       {port, ServerPort} ->
 		   ServerPort
 	   end,
    
    URLAuth = "http://alladin:sesame@localhost:" 
	++ integer_to_list(Port) ++ "/userinfo.html",
    
    {ok, {{_,200,_}, [_ | _], _}} 
 	= http:request(get, {URLAuth, []}, [], []),

    URLUnAuth = "http://alladin:foobar@localhost:" 
	++ integer_to_list(Port) ++ "/userinfo.html",
    
    {ok, {{_,401, _}, [_ | _], _}} =
	http:request(get, {URLUnAuth, []}, [], []),
    
    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.


%%-------------------------------------------------------------------------
http_cookie(doc) ->
    ["Test cookies."];
http_cookie(suite) ->
    [];
http_cookie(Config) when is_list(Config) ->
    ok = http:set_options([{cookies, enabled}, {ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
 	       {port, ServerPort} ->
 		   ServerPort
 	   end,
    
    URLStart = ?URL_START  
	++ integer_to_list(Port),
    
    URLCookie = URLStart ++ "/cookie.html",
   
    {ok, {{_,200,_}, [_ | _], [_|_]}} 
 	= http:request(get, {URLCookie, []}, [], []),

    ets:new(cookie, [named_table, public, set]),
    ets:insert(cookie, {cookies, true}),

    {ok, {{_,200,_}, [_ | _], [_|_]}} 
 	= http:request(get, {URLStart ++ "/", []}, [], []),
    
    ets:delete(cookie),

    ok = http:set_options([{cookies, disabled}, {ipfamily, inet6fb4}]), % ********** ipfamily = inet6 *************
    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),                      % ********** ipfamily = inet6************
    ok.

%%-------------------------------------------------------------------------
proxy_options(doc) ->
    ["Perform a OPTIONS request that goes through a proxy."];
proxy_options(suite) ->
    [];
proxy_options(Config) when is_list(Config) ->
    case ?config(skip, Config) of 
        undefined ->
	    case http:request(options, {?PROXY_URL, []}, [], []) of
		{ok, {{_,200,_}, Headers, _}} ->
		    case lists:keysearch("allow", 1, Headers) of
			{value, {"allow", _}} ->
			    ok;
			_ ->
			    test_server:fail(http_options_request_failed)
		    end;
		Unexpected ->
		    test_server:fail({unexpected_result, Unexpected})
	    end;
	Reason ->
	    {skip, Reason}
    end.


%%-------------------------------------------------------------------------
proxy_head(doc) ->
     ["Perform a HEAD request that goes through a proxy."];
proxy_head(suite) ->
    [];
proxy_head(Config) when is_list(Config) ->
    case ?config(skip, Config) of 
	undefined ->
	    case http:request(head, {?PROXY_URL, []}, [], []) of
		{ok, {{_,200, _}, [_ | _], []}} ->
		    ok;
		Unexpected ->
		    test_server:fail({unexpected_result, Unexpected})
	    end;
	Reason ->
	    {skip, Reason}
    end.


%%-------------------------------------------------------------------------
proxy_get(doc) ->
    ["Perform a GET request that goes through a proxy."];
proxy_get(suite) ->
    [];
proxy_get(Config) when is_list(Config) ->
    case ?config(skip, Config) of 
	undefined ->
	    case http:request(get, {?PROXY_URL, []}, [], []) of
		{ok, {{_,200,_}, [_ | _], Body = [_ | _]}} ->
		    inets_test_lib:check_body(Body);
		Unexpected ->
		    test_server:fail({unexpected_result, Unexpected})
	    end;
	Reason ->
	    {skip, Reason}
    end.

%%-------------------------------------------------------------------------
proxy_emulate_lower_versions(doc) ->
    ["Perform requests as 0.9 and 1.0 clients."];
proxy_emulate_lower_versions(suite) ->
    [];
proxy_emulate_lower_versions(Config) when is_list(Config) ->
    case ?config(skip, Config) of 
	undefined ->
	    {ok, Body0 = [_| _]} = http:request(get, {?PROXY_URL, []}, 
						[{version, "HTTP/0.9"}], []),
	    inets_test_lib:check_body(Body0),
	    
	    %% We do not check the version here as many servers
	    %% do not behave according to the rfc and send
	    %% 1.1 in its response.
	    {ok,{{_, 200, _}, [_ | _], Body1 = [_ | _]}} = 
		http:request(get, {?PROXY_URL, []}, 
			     [{version, "HTTP/1.0"}], []),
	    inets_test_lib:check_body(Body1),
			     	    
	    {ok, {{"HTTP/1.1", 200, _}, [_ | _], Body2 = [_ | _]}} =
		http:request(get, {?PROXY_URL, []}, 
			     [{version, "HTTP/1.1"}], []),
	    inets_test_lib:check_body(Body2);
	Reason ->
	    {skip, Reason}
    end.

%%-------------------------------------------------------------------------
proxy_trace(doc) ->
    ["Perform a TRACE request that goes through a proxy."];
proxy_trace(suite) ->
    [];
proxy_trace(Config) when is_list(Config) ->
    %%{ok, {{_,200,_}, [_ | _], "TRACE " ++ _}} =
    %%	http:request(trace, {?PROXY_URL, []}, [], []),
    {skip, "HTTP TRACE is no longer allowed on the ?PROXY_URL server due "
     "to security reasons"}.


%%-------------------------------------------------------------------------
proxy_post(doc) ->
    ["Perform a POST request that goes through a proxy. Note the server"
     " will reject the request this is a test of the sending of the"
     " request."];
proxy_post(suite) ->
    [];
proxy_post(Config) when is_list(Config) ->
    case ?config(skip, Config) of 
	undefined ->
	    case http:request(post, {?PROXY_URL, [], 
				     "text/plain", "foobar"}, [],[]) of
		{ok, {{_,405,_}, [_ | _], [_ | _]}} ->
		    ok;
		Unexpected ->
		    test_server:fail({unexpected_result, Unexpected})
	    end;
	Reason ->
	    {skip, Reason}
    end.


%%-------------------------------------------------------------------------
proxy_put(doc) ->
    ["Perform a PUT request that goes through a proxy. Note the server"
     " will reject the request this is a test of the sending of the"
     " request."];
proxy_put(suite) ->
    [];
proxy_put(Config) when is_list(Config) ->
    case ?config(skip, Config) of 
	undefined -> 
	    case http:request(put, {"http://www.erlang.org/foobar.html", [], 
				    "html", "<html> <body><h1> foo </h1>" 
				    "<p>bar</p> </body></html>"}, [], []) of
		{ok, {{_,405,_}, [_ | _], [_ | _]}} ->
		    ok;
		Unexpected ->
		    test_server:fail({unexpected_result, Unexpected})
	    end;
	Reason ->
	    {skip, Reason}
    end.


%%-------------------------------------------------------------------------
proxy_delete(doc) ->
    ["Perform a DELETE request that goes through a proxy. Note the server"
     " will reject the request this is a test of the sending of the"
     " request. But as the file does not exist the return code will"
     " be 404 not found."];
proxy_delete(suite) ->
    [];
proxy_delete(Config) when is_list(Config) ->
    case ?config(skip, Config) of 
	undefined -> 
	    URL = ?PROXY_URL ++ "/foobar.html",
	    case http:request(delete, {URL, []}, [], []) of
		{ok, {{_,404,_}, [_ | _], [_ | _]}} ->
		    ok;
		Unexpected ->
		    test_server:fail({unexpected_result, Unexpected})
	    end;
	Reason ->
	    {skip, Reason}
    end.


%%-------------------------------------------------------------------------
proxy_headers(doc) ->
    ["Use as many request headers as possible"];
proxy_headers(suite) ->
    [];
proxy_headers(Config) when is_list(Config) ->
    case ?config(skip, Config) of 
	undefined ->
	    {ok, {{_,200,_}, [_ | _], [_ | _]}} 
		= http:request(get, {?PROXY_URL,
				     [
				      {"Accept",
				       "text/*, text/html,"
				       " text/html;level=1,"
				       " */*"}, 
				      {"Accept-Charset", 
				       "iso-8859-5, unicode-1-1;"
				       "q=0.8"},
				      {"Accept-Encoding", "*"},
				      {"Accept-Language", 
				       "sv, en-gb;q=0.8,"
				       " en;q=0.7"},
				      {"User-Agent", "inets"},
				      {"Max-Forwards","5"},
				      {"Referer", 
				       "http://otp.ericsson.se:8000"
				       "/product/internal"}
			     ]}, [], []),
	    ok;
	Reason ->
	    {skip, Reason}
    end.

%%-------------------------------------------------------------------------
proxy_auth(doc) ->
    ["Test the code for sending of proxy authorization."];
proxy_auth(suite) ->
    [];
proxy_auth(Config) when is_list(Config) ->
    %% Our proxy seems to ignore the header, however our proxy
    %% does not requirer an auth header, but we want to know
    %% atleast the code for sending the header does not crash!
    case ?config(skip, Config) of 
	undefined ->	    
	    case http:request(get, {?PROXY_URL, []}, 
			      [{proxy_auth, {"foo", "bar"}}], []) of
		{ok, {{_,200, _}, [_ | _], [_|_]}} ->
		    ok;
		Unexpected ->
		    test_server:fail({unexpected_result, Unexpected})
	    end;
	Reason ->
	    {skip, Reason}
    end.  


%%-------------------------------------------------------------------------
http_server_does_not_exist(doc) ->
    ["Test that we get an error message back when the server "
     "does note exist."];
http_server_does_not_exist(suite) ->
    [];
http_server_does_not_exist(Config) when is_list(Config) ->
    {error, _} = 
	http:request(get, {"http://localhost:" ++ 
			   integer_to_list(?NOT_IN_USE_PORT) 
			   ++ "/", []},[], []),
    ok.


%%-------------------------------------------------------------------------
page_does_not_exist(doc) ->
    ["Test that we get a 404 when the page is not found."];
page_does_not_exist(suite) ->
    [];
page_does_not_exist(Config) when is_list(Config) ->
    Port = ?config(local_port, Config),
    URL = ?URL_START ++ integer_to_list(Port) ++ "/doesnotexist.html",
    {ok, {{_,404,_}, [_ | _], [_ | _]}} 
	= http:request(get, {URL, []}, [], []),
    ok.


%%-------------------------------------------------------------------------
proxy_page_does_not_exist(doc) ->
    ["Test that we get a 404 when the page is not found."];
proxy_page_does_not_exist(suite) ->
    [];
proxy_page_does_not_exist(Config) when is_list(Config) ->
    case ?config(skip, Config) of 
	undefined ->
	    URL = ?PROXY_URL ++ "/doesnotexist.html",
	    {ok, {{_,404,_}, [_ | _], [_ | _]}} = 
		http:request(get, {URL, []}, [], []),
	    ok;
	Reason ->
	    {skip, Reason}
    end.


%%-------------------------------------------------------------------------
proxy_https_not_supported(doc) ->
    [];
proxy_https_not_supported(suite) ->
    [];
proxy_https_not_supported(Config) when is_list(Config) ->
    {error, https_through_proxy_is_not_currently_supported} 
	= http:request(get, {"https://login.yahoo.com", []}, [], []),
    ok.


%%-------------------------------------------------------------------------

http_stream(doc) ->
    ["Test the option stream for asynchrony requests"];
http_stream(suite) ->
    [];
http_stream(Config) when is_list(Config) ->
    Port = ?config(local_port, Config),
    URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
    {ok, {{_,200,_}, [_ | _], Body}} = 
	http:request(get, {URL, []}, [], []),
    
    {ok, RequestId} =
	http:request(get, {URL, []}, [], [{sync, false}, 
					  {stream, self}]),
    
    receive 
	{http, {RequestId, stream_start, _Headers}} ->
	    ok;
	{http, Msg} ->
	    test_server:fail(Msg)
    end,

    StreamedBody = receive_streamed_body(RequestId, <<>>),
    
    Body == binary_to_list(StreamedBody).


%%-------------------------------------------------------------------------
http_stream_once(doc) ->
    ["Test the option stream for asynchrony requests"];
http_stream_once(suite) ->
    [];
http_stream_once(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),    
    Port = receive 
	       {port, ServerPort} ->
			   ServerPort
	   end,
    
    PortStr =  integer_to_list(Port),
    once(?URL_START ++ PortStr ++ "/once.html"),
    once(?URL_START ++ PortStr ++ "/once_chunked.html"),
    once(?URL_START ++ PortStr ++ "/dummy.html"),
    
    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.
  
once(URL) ->
    {ok, {{_,200,_}, [_ | _], Body}} = 
	http:request(get, {URL, []}, [], []),
    
    {ok, RequestId} =
	http:request(get, {URL, []}, [], [{sync, false}, 
					  {stream, {self, once}}]),
    
    NewPid = receive 
		 {http, {RequestId, stream_start, _Headers, Pid}} ->
		     Pid;
		 {http, Msg} ->
		     test_server:fail(Msg)
	     end,

    test_server:format("Request handler: ~p~n", [NewPid]),

    BodyPart = 
	receive 
	    {http, {RequestId, stream, BinBodyPart}} ->
		BinBodyPart
	end,

    test_server:format("First body part: ~p~n", 
		       [binary_to_list(BodyPart)]),

    StreamedBody = receive_streamed_body(RequestId, BinBodyPart, NewPid),
    
    Body = binary_to_list(StreamedBody),
    ok.


%%-------------------------------------------------------------------------
proxy_stream(doc) ->
    ["Test the option stream for asynchrony requests"];
proxy_stream(suite) ->
    [];
proxy_stream(Config) when is_list(Config) ->
    case ?config(skip, Config) of 
	undefined ->
	    {ok, {{_,200,_}, [_ | _], Body}} = 
		http:request(get, {?PROXY_URL, []}, [], []),
	    
	    {ok, RequestId} =
		http:request(get, {?PROXY_URL, []}, [], 
			     [{sync, false}, {stream, self}]),
	    
	    receive 
		{http, {RequestId, stream_start, _Headers}} ->
		    ok;
		{http, Msg} ->
		    test_server:fail(Msg)
	    end,
	    
	    StreamedBody = receive_streamed_body(RequestId, <<>>),
	    
	    Body == binary_to_list(StreamedBody);
	Reason ->
	    {skip, Reason}
    end.


%%-------------------------------------------------------------------------
parse_url(doc) ->
    ["Test that an url is parsed correctly"];
parse_url(suite) ->
    [];
parse_url(Config) when is_list(Config) ->
    %% ipv6
    {http,[],"2010:836B:4179::836B:4179",80,"/foobar.html",[]}
	= http_uri:parse("http://[2010:836B:4179::836B:4179]/foobar.html"),
    {error,
     {malformed_url,"http://2010:836B:4179::836B:4179/foobar.html"}} =
	http_uri:parse("http://2010:836B:4179::836B:4179/foobar.html"), 

    %% ipv4
    {http,[],"127.0.0.1",80,"/foobar.html",[]} =
	http_uri:parse("http://127.0.0.1/foobar.html"),
    
    %% host
    {http,[],"localhost",8888,"/foobar.html",[]} = 
	http_uri:parse("http://localhost:8888/foobar.html"),
    
    %% Userinfo
    {http,"nisse:foobar","localhost",8888,"/foobar.html",[]} =
	http_uri:parse("http://nisse:foobar@localhost:8888/foobar.html"),
    
    %% Scheme error
    {error,no_scheme} =  http_uri:parse("localhost/foobar.html"),
    {error,{not_supported_scheme,localhost}} =
	http_uri:parse("localhost:8888/foobar.html"),
    
    %% Query
    {http,[],"localhost",8888,"/foobar.html","?foo=bar&foobar=42"} =
	http_uri:parse("http://localhost:8888/foobar.html?foo=bar&foobar=42"),
    
    %%  Esc chars
    {http,[],"www.somedomain.com",80,"/%2Eabc",[]} =
	http_uri:parse("http://www.somedomain.com/%2Eabc"),
    {http,[],"www.somedomain.com",80,"/%252Eabc",[]} = 
	http_uri:parse("http://www.somedomain.com/%252Eabc"),
    {http,[],"www.somedomain.com",80,"/%25abc",[]} =
	http_uri:parse("http://www.somedomain.com/%25abc"),
    {http,[],"www.somedomain.com",80,"/%25abc", "?foo=bar"} =
	http_uri:parse("http://www.somedomain.com/%25abc?foo=bar"),
    ok.    


%%-------------------------------------------------------------------------
ipv6(doc) ->
    ["Test ipv6."];
ipv6(suite) ->
    [];
ipv6(Config) when is_list(Config) ->
    {ok, Hostname} = inet:gethostname(),
    
    case lists:member(list_to_atom(Hostname), 
		      ?config(ipv6_hosts, Config)) of
	true ->
	    DummyServerPid = dummy_server(self(), ipv6),
	    
	    Port = receive 
		       {port, ServerPort} ->
			   ServerPort
		   end,
	    
	    URL = "http://[" ++ ?IPV6_LOCAL_HOST ++ "]:" ++ 
		integer_to_list(Port) ++ "/foobar.html",
	    {ok, {{_,200,_}, [_ | _], [_|_]}} =
		http:request(get, {URL, []}, [], []),
	    
	    DummyServerPid ! stop,
	    ok;
	false ->
	    {skip, "Host does not support IPv6"}
    end.


%%-------------------------------------------------------------------------
headers_as_is(doc) ->
    ["Test the option headers_as_is"];
headers_as_is(suite) ->
    [];
headers_as_is(Config) when is_list(Config) ->
    Port = ?config(local_port, Config),
    URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
    {ok, {{_,200,_}, [_|_], [_|_]}} =
	http:request(get, {URL, [{"Host", "localhost"},{"Te", ""}]}, 
		     [], [{headers_as_is, true}]),
     
    {ok, {{_,400,_}, [_|_], [_|_]}} = 
	http:request(get, {URL, [{"Te", ""}]},[], [{headers_as_is, true}]),
    ok.


%%-------------------------------------------------------------------------
options(doc) ->
    ["Test the option parameters."];
options(suite) ->
    [];
options(Config) when is_list(Config) ->
    case ?config(local_server, Config) of 
	ok ->
	    Port = ?config(local_port, Config),
	    URL = ?URL_START ++ integer_to_list(Port) ++ "/dummy.html",
	    {ok, {{_,200,_}, [_ | _], Bin}} 
		= http:request(get, {URL, []}, [{foo, bar}], 
			       %% Ignore unknown options
			       [{body_format, binary}, {foo, bar}]),

	    true = is_binary(Bin),
	    {ok, {200, [_|_]}} 
		= http:request(get, {URL, []}, [{timeout, infinity}],
			       [{full_result, false}]);
	_ ->
	    {skip, "Failed to start local http-server"}
    end.  


%%-------------------------------------------------------------------------
http_invalid_http(doc) ->
    ["Test parse error"];
http_invalid_http(suite) ->
    [];
http_invalid_http(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
 	       {port, ServerPort} ->
 		   ServerPort
 	   end,
    
    URL = ?URL_START ++ integer_to_list(Port) ++ "/invalid_http.html",
    
    {error, {could_not_parse_as_http, _} = Reason} =
	http:request(get, {URL, []}, [], []),
    
    test_server:format("Parse error: ~p ~n", [Reason]),
    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.


%%-------------------------------------------------------------------------

hexed_query_otp_6191(doc) ->
    [];
hexed_query_otp_6191(suite) ->
    [];
hexed_query_otp_6191(Config) when is_list(Config) ->
    Google = "www.google.com",
    GoogleSearch = "http://" ++ Google ++ "/search",
    Search1 = "?hl=en&q=a%D1%85%D1%83%D0%B9&btnG=Google+Search", 
    URI1    = GoogleSearch ++ Search1,
    Search2 = "?hl=en&q=%25%25", 
    URI2    = GoogleSearch ++ Search2,
    Search3 = "?hl=en&q=%foo",
    URI3    = GoogleSearch ++ Search3, 

    {http, [], Google, 80, "/search", _} = http_uri:parse(URI1),
    {http, [], Google, 80, "/search", _} = http_uri:parse(URI2),
    {http, [], Google, 80, "/search", _} = http_uri:parse(URI3),
    ok.


%%-------------------------------------------------------------------------

empty_body_otp_6243(doc) ->
    ["An empty body was not returned directly. There was a delay for several"
     "seconds."];
empty_body_otp_6243(suite) ->
    [];
empty_body_otp_6243(Config) when is_list(Config) ->
    Port = ?config(local_port, Config),
    URL = ?URL_START ++ integer_to_list(Port) ++ "/empty.html",
    {ok, {{_,200,_}, [_ | _], []}} =
	http:request(get, {URL, []}, [{timeout, 500}], []).


%%-------------------------------------------------------------------------

transfer_encoding_otp_6807(doc) ->
    ["Transfer encoding is case insensitive"];
transfer_encoding_otp_6807(suite) ->
    [];
transfer_encoding_otp_6807(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
	       {port, ServerPort} ->
		   ServerPort
	   end,
    
    URL = ?URL_START ++ integer_to_list(Port) ++ 
	"/capital_transfer_encoding.html",
    {ok, {{_,200,_}, [_|_], [_ | _]}} = http:request(URL),
    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.


%%-------------------------------------------------------------------------

proxy_not_modified_otp_6821(doc) ->
    ["If unmodified no body should be returned"];
proxy_not_modified_otp_6821(suite) ->
    [];
proxy_not_modified_otp_6821(Config) when is_list(Config) ->
    case ?config(skip, Config) of 
	undefined ->
	    provocate_not_modified_bug(?PROXY_URL);
	Reason ->
	    {skip, Reason}
    end.


%%-------------------------------------------------------------------------

empty_response_header_otp_6830(doc) ->
    ["Test the case that the HTTP server does not send any headers"];
empty_response_header_otp_6830(suite) ->
    [];
empty_response_header_otp_6830(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
	       {port, ServerPort} ->
		   ServerPort
	   end,
    
    URL = ?URL_START ++ integer_to_list(Port) ++ "/no_headers.html",
    {ok, {{_,200,_}, [], [_ | _]}} = http:request(URL),
    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.


%%-------------------------------------------------------------------------

no_content_204_otp_6982(doc) ->
    ["Test the case that the HTTP 204 no content header"];
no_content_204_otp_6982(suite) ->
    [];
no_content_204_otp_6982(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
	       {port, ServerPort} ->
		   ServerPort
	   end,
    
    URL = ?URL_START ++ integer_to_list(Port) ++ "/no_content.html",
    {ok, {{_,204,_}, [], []}} = http:request(URL),
    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.


%%-------------------------------------------------------------------------

missing_CR_otp_7304(doc) ->
    ["Test the case that the HTTP server uses only LF instead of CRLF" 
     "as delimitor"];
missing_CR_otp_7304(suite) ->
    [];
missing_CR_otp_7304(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),
    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
	       {port, ServerPort} ->
		   ServerPort
	   end,
    
    URL = ?URL_START ++ integer_to_list(Port) ++ "/missing_CR.html",
    {ok, {{_,200,_}, _, [_ | _]}} = http:request(URL),
    DummyServerPid ! stop,
    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.


%%-------------------------------------------------------------------------

otp_7883(suite) ->
    [otp_7883_1, otp_7883_2].

otp_7883_1(doc) ->
    ["OTP-7883-sync"];
otp_7883_1(suite) ->
    [];
otp_7883_1(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),

    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
	       {port, ServerPort} ->
		   ServerPort
	   end,

    URL = ?URL_START ++ integer_to_list(Port) ++ "/just_close.html",
    {error, socket_closed_remotely} = http:request(URL),
    DummyServerPid ! stop,

    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.

otp_7883_2(doc) ->
    ["OTP-7883-async"];
otp_7883_2(suite) ->
    [];
otp_7883_2(Config) when is_list(Config) ->
    ok = http:set_options([{ipfamily, inet}]),

    DummyServerPid = dummy_server(self(), ipv4),
    
    Port = receive 
	       {port, ServerPort} ->
		   ServerPort
	   end,

    URL = ?URL_START ++ integer_to_list(Port) ++ "/just_close.html",
    Method      = get,
    Request     = {URL, []}, 
    HttpOptions = [], 
    Options     = [{sync, false}], 
    Profile     = http:default_profile(), 
    {ok, RequestId} = 
	http:request(Method, Request, HttpOptions, Options, Profile),
    ok = 
	receive
	    {http, {RequestId, {error, socket_closed_remotely}}} ->
		ok
    end,
    DummyServerPid ! stop,

    ok = http:set_options([{ipfamily, inet6fb4}]),   % ********** ipfamily = inet6 *************
    ok.


%%-------------------------------------------------------------------------

otp_8154(suite) ->
    [otp_8154_1].

otp_8154_1(doc) ->
    ["OTP-8154"];
otp_8154_1(suite) ->
    [];
otp_8154_1(Config) when is_list(Config) ->
    start_inets(),
    ReqSeqNumServer = start_sequence_number_server(),
    RespSeqNumServer = start_sequence_number_server(),
    {ok, Server, Port} = start_slow_server(RespSeqNumServer),
    Clients = run_clients(105, Port, ReqSeqNumServer),
    %% ok = wait_for_clients(Clients),
    ok = wait4clients(Clients, timer:minutes(2)),
    Server ! shutdown,
    RespSeqNumServer ! shutdown,
    ReqSeqNumServer ! shutdown,
    ok.

start_inets() ->
    inets:start(),
    ok.

%% -----------------------------------------------------
%% A sequence number handler
%% The purpose is to be able to pair requests with responses.

start_sequence_number_server() ->
    proc_lib:spawn(fun() -> loop_sequence_number(1) end).

loop_sequence_number(N) ->
    receive
	shutdown ->
	    ok;
	{From, get_next} ->
	    From ! {next_is, N},
	    loop_sequence_number(N + 1)
    end.

get_next_sequence_number(SeqNumServer) ->
    SeqNumServer ! {self(), get_next},
    receive {next_is, N} -> N end.

%% -----------------------------------------------------
%% Client part
%% Sends requests randomly parallel

run_clients(NumClients, ServerPort, SeqNumServer) ->
    io:format("start clients when"
	      "~n   NumClients:   ~w"
	      "~n   ServerPort:   ~w"
	      "~n   SeqNumServer: ~w"
	      "~n", [NumClients, ServerPort, SeqNumServer]),
    set_random_seed(),
    lists:map(
      fun(Id) ->
	      io:format("starting client ~w~n", [Id]),
	      Req = f("req~3..0w", [get_next_sequence_number(SeqNumServer)]),
	      Url = f(?URL_START ++ "~w/~s", [ServerPort, Req]),
	      Pid = proc_lib:spawn(
		      fun() ->
			      io:format("[~w] client started - "
					"issue request~n", [Id]),
			      case http:request(Url) of
				  {ok, {{_,200,_}, _, Resp}} ->
				      io:format("[~w] 200 response: "
						"~p~n", [Id, Resp]),
				      case lists:prefix(Req++"->", Resp) of
					  true -> exit(normal);
					  false -> exit({bad_resp,Req,Resp})
				      end;
				  {ok, {{_,EC,Reason},_,Resp}}  ->
				      io:format("[~w] ~w response: "
						"~s~n~s~n", 
						[Id, EC, Reason, Resp]),
				      exit({bad_resp,Req,Resp});
				  Crap ->
				      io:format("[~w] bad response: ~p", 
						[Id, Crap]),
				      exit({bad_resp, Req, Crap})
			      end
		      end),
	      MRef = erlang:monitor(process, Pid),
	      timer:sleep(10 + random:uniform(1334)),
	      {Id, Pid, MRef}

      end,
      lists:seq(1, NumClients)).

wait_for_clients(Clients) ->
    lists:foreach(
      fun({Id, Pid, MRef}) ->
	      io:format("waiting for client ~w termination~n", [Id]),
	      receive
		  {'DOWN', MRef, process, Pid, normal} ->
		      io:format("waiting for clients: "
				"normal exit from ~w (~p)~n", 
				[Id, Pid]),
		      ok;
		  {'DOWN', MRef, process, Pid, Reason} ->
		      io:format("waiting for clients: "
				"unexpected exit from ~w (~p):"
				"~n   Reason: ~p"
				"~n", [Id, Pid, Reason]),
		      erlang:error(Reason)
	      end
      end,
      Clients).


wait4clients([], _Timeout) ->
    ok;
wait4clients(Clients, Timeout) when Timeout > 0 ->
    io:format("wait4clients -> entry with"
	      "~n   length(Clients): ~w"
	      "~n   Timeout:         ~w"
	      "~n", [length(Clients), Timeout]),
    T = t(),
    receive
	{'DOWN', _MRef, process, Pid, normal} ->
	    case lists:keysearch(Pid, 2, Clients) of
		{value, {Id, _, _}} ->
		    io:format("receive normal exit message "
			      "from client ~p (~p)", [Id, Pid]),
		    NewClients = 
			lists:keydelete(Id, 1, Clients),
		    wait4clients(NewClients, 
				 Timeout - (t() - T));
		false ->
		    io:format("receive normal exit message "
			      "from unknown process: ~p", [Pid]),
		    wait4clients(Clients, Timeout - (t() - T))
	    end;

	{'DOWN', _MRef, process, Pid, Reason} ->
	    case lists:keysearch(Pid, 2, Clients) of
		{value, {Id, _, _}} ->
		    io:format("receive bad exit message "
			      "from client ~p (~p):"
			      "~n   ~p", [Id, Pid, Reason]),
		    erlang:error({bad_client_termination, Id, Reason});
		false ->
		    io:format("receive normal exit message "
			      "from unknown process: ~p", [Pid]),
		    wait4clients(Clients, Timeout - (t() - T))
	    end

    after Timeout ->
	    erlang:error({client_timeout, Clients})  
    end;
wait4clients(Clients, _) ->
    erlang:error({client_timeout, Clients}).
		    
		    
%% Time in milli seconds
t() ->
    {A,B,C} = erlang:now(),
    A*1000000000+B*1000+(C div 1000).


%% -----------------------------------------------------
%% Webserver part:
%% Implements a web server that sends responses one character
%% at a time, with random delays between the characters.

start_slow_server(SeqNumServer) ->
    io:format("start slow server when"
	      "~n   SeqNumServer: ~w"
	      "~n", [SeqNumServer]),
    proc_lib:start(
      erlang, apply, [fun() -> init_slow_server(SeqNumServer) end, []]).

init_slow_server(SeqNumServer) ->
    io:format("[webserver ~w] init slow server"
	      "~n", [SeqNumServer]),
    {ok, LSock} = gen_tcp:listen(0, [binary, {packet,0}, {active,true},
				     {backlog, 100}]),
    io:format("[webserver ~w] LSock: ~p"
	      "~n", [SeqNumServer, LSock]),
    {ok, {_IP, Port}} = inet:sockname(LSock),
    io:format("[webserver ~w] Port: ~w"
	      "~n", [SeqNumServer, Port]),
    proc_lib:init_ack({ok, self(), Port}),
    loop_slow_server(LSock, SeqNumServer).

loop_slow_server(LSock, SeqNumServer) ->
    io:format("[webserver ~w] entry with"
	      "~n   LSock: ~p"
	      "~n", [SeqNumServer, LSock]),
    Master = self(),
    Acceptor = proc_lib:spawn(
		 fun() -> client_handler(Master, LSock, SeqNumServer) end),
    io:format("[webserver ~w] acceptor started"
	      "~n   Acceptor: ~p"
	      "~n", [SeqNumServer, Acceptor]),
    receive
	{accepted, Acceptor} ->
	    io:format("[webserver ~w] accepted"
		      "~n", [SeqNumServer]),
	    loop_slow_server(LSock, SeqNumServer);
	shutdown ->
	    gen_tcp:close(LSock),
	    exit(Acceptor, kill)
    end.


%% Handle one client connection
client_handler(Master, LSock, SeqNumServer) ->
    io:format("[acceptor ~w] await accept"
	      "~n", [SeqNumServer]),
    {ok, CSock} = gen_tcp:accept(LSock),
    io:format("[acceptor ~w] accepted"
	      "~n   CSock: ~p"
	      "~n", [SeqNumServer, CSock]),
    Master ! {accepted, self()},
    set_random_seed(),
    loop_client(1, CSock, SeqNumServer).

loop_client(N, CSock, SeqNumServer) ->
    %% Await request, don't bother parsing it too much,
    %% assuming the entire request arrives in one packet.
    io:format("[acceptor ~w] await request"
	      "~n   N: ~p"
	      "~n", [SeqNumServer, N]),
    receive
	{tcp, CSock, Req} ->
	    ReqNum = parse_req_num(Req),
	    RespSeqNum = get_next_sequence_number(SeqNumServer),
	    Response = f("~s->resp~3..0w/~2..0w", [ReqNum, RespSeqNum, N]),
	    Txt = f("Slow server (~p) got ~p, answering with ~p",
		    [self(), Req, Response]),
	    io:format("~s...~n", [Txt]),
	    slowly_send_response(CSock, Response),
	    case parse_connection_type(Req) of
		keep_alive ->
		    io:format("~s...done~n", [Txt]),
		    loop_client(N+1, CSock, SeqNumServer);
		close ->
		    io:format("~s...done (closing)~n", [Txt]),
		    gen_tcp:close(CSock)
	    end
    end.

slowly_send_response(CSock, Answer) ->
    Response = f("HTTP/1.1 200 OK\r\nContent-Length: ~w\r\n\r\n~s",
		 [length(Answer), Answer]),
    lists:foreach(
      fun(Char) ->
	      timer:sleep(random:uniform(500)),
	      gen_tcp:send(CSock, <<Char>>)
      end,
      Response).

parse_req_num(Request) ->
    Opts = [caseless,{capture,all_but_first,list}],
    {match, [ReqNum]} = re:run(Request, "GET /(.*) HTTP", Opts),
    ReqNum.

parse_connection_type(Request) ->
    Opts = [caseless,{capture,all_but_first,list}],
    {match,[CType]} = re:run(Request, "connection: *(keep-alive|close)", Opts),
    case string:to_lower(CType) of
	"close" -> close;
	"keep-alive" -> keep_alive
    end.


set_random_seed() ->
    {_, _, Micros} = now(),
    A = erlang:phash2([make_ref(), self(), Micros]),
    random:seed(A, A, A).

f(F, A) -> lists:flatten(io_lib:format(F,A)).




%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------
setup_server_dirs(ServerRoot, DocRoot, DataDir) ->   
    ConfDir = filename:join(ServerRoot, "conf"),
    CgiDir =  filename:join(ServerRoot, "cgi-bin"),
    ok = file:make_dir(ServerRoot),
    ok = file:make_dir(DocRoot),
    ok = file:make_dir(ConfDir),
    ok = file:make_dir(CgiDir),

    {ok, Files} = file:list_dir(DataDir),
    
    lists:foreach(fun(File) -> case lists:suffix(".html", File) of
				   true ->
				       inets_test_lib:copy_file(File, 
								DataDir, 
								DocRoot);
				   false ->
				       ok
			       end
		  end, Files),
    
    Cgi = case test_server:os_type() of
	      {win32, _} ->
		  "cgi_echo.exe";
	      _ ->
		  "cgi_echo"
	  end,
    
    inets_test_lib:copy_file(Cgi, DataDir, CgiDir),
    inets_test_lib:copy_file("mime.types", DataDir, ConfDir).

create_config(FileName, ComType, Port, PrivDir, ServerRoot, DocRoot, 
	      SSLDir) ->
    MaxHdrSz     = io_lib:format("~p", [256]),
    MaxHdrAct    = io_lib:format("~p", [close]),
    SSL =
	case ComType of
	    ssl ->
		[cline(["SSLCertificateFile ", 
			filename:join(SSLDir, "ssl_server_cert.pem")]),
		 cline(["SSLCertificateKeyFile ",
			filename:join(SSLDir, "ssl_server_cert.pem")]),
		 cline(["SSLVerifyClient 0"])];
	    _ ->
		[]
	end,

    Mod_order = "Modules mod_alias mod_auth mod_esi mod_actions mod_cgi" 
	" mod_include mod_dir mod_get mod_head" 
	" mod_log mod_disk_log mod_trace",
	    
    HttpConfig = [
		  cline(["Port ", integer_to_list(Port)]),
		  cline(["ServerName ", "httpc_test"]),
		  cline(["SocketType ", atom_to_list(ComType)]),
		  cline([Mod_order]),
		  cline(["ServerRoot ", ServerRoot]),
		  cline(["DocumentRoot ", DocRoot]),
		  cline(["MaxHeaderSize ",MaxHdrSz]),
		  cline(["MaxHeaderAction ",MaxHdrAct]),
		  cline(["DirectoryIndex ", "index.html "]),
		  cline(["DefaultType ", "text/plain"]),
		  cline(["ScriptAlias /cgi-bin/ ", 
			 filename:join(ServerRoot, "cgi-bin"), "/"]),
		  SSL],
    ConfigFile = filename:join([PrivDir,FileName]),
    {ok, Fd} = file:open(ConfigFile, [write]),
    ok = file:write(Fd, lists:flatten(HttpConfig)),
    ok = file:close(Fd).

cline(List) ->
    lists:flatten([List, "\r\n"]).

is_proxy_available(Proxy, Port) ->
    case gen_tcp:connect(Proxy, Port, []) of
	{ok, Socket} ->
	    gen_tcp:close(Socket),
	    true;
	_ ->
	    false
    end.

receive_streamed_body(RequestId, Body) ->
    receive 
	{http, {RequestId, stream, BinBodyPart}} ->
	    receive_streamed_body(RequestId, 
				  <<Body/binary, BinBodyPart/binary>>);
	{http, {RequestId, stream_end, _Headers}} ->
	    Body;
	{http, Msg} ->	    
	    test_server:fail(Msg)
    end.

receive_streamed_body(RequestId, Body, Pid) ->
    http:stream_next(Pid),
    test_server:format("Requested next stream ~n", []),
    receive 
	{http, {RequestId, stream, BinBodyPart}} ->
	    receive_streamed_body(RequestId, 
				  <<Body/binary, BinBodyPart/binary>>, 
				  Pid);
	{http, {RequestId, stream_end, _Headers}} ->
	    Body;
	{http, Msg} ->	    
	    test_server:fail(Msg)
    end.



dummy_server(Caller, IpV) ->
    spawn(httpc_SUITE, dummy_server_init, [Caller, IpV]).

dummy_server_init(Caller, IpV) ->
    {ok, ListenSocket} = 
	case IpV of 
	    ipv4 ->
		gen_tcp:listen(0, [binary, inet, {packet, 0},
				   {reuseaddr,true},
				   {active, false}]);
	    ipv6 ->
		gen_tcp:listen(0, [binary, inet6, {packet, 0},
				   {reuseaddr,true},
				   {active, false}])
	end,
    {ok, Port} = inet:port(ListenSocket),
    test_server:format("Port: ~p~n", [Port]),
    Caller ! {port, Port},
    dummy_server_loop({httpd_request, parse, [?HTTP_MAX_HEADER_SIZE]},
		      [], ListenSocket).

dummy_server_loop(MFA, Handlers, ListenSocket) ->
    receive
	stop ->
	    lists:foreach(fun(Handler) -> Handler ! stop end,
			  Handlers)
    after 0 ->
	    {ok, Socket} = gen_tcp:accept(ListenSocket),
	    HandlerPid  = dummy_request_handler(MFA, Socket),
	    gen_tcp:controlling_process(Socket, HandlerPid),
	    HandlerPid ! controller,
	    dummy_server_loop(MFA, [HandlerPid | Handlers],
			      ListenSocket)
    end.

dummy_request_handler(MFA, Socket) ->
    spawn(httpc_SUITE, dummy_request_handler_init, [MFA, Socket]).

dummy_request_handler_init(MFA, Socket) ->
    receive 
	controller ->
	    inet:setopts(Socket, [{active, true}])
    end,
    dummy_request_handler_loop(MFA, Socket).
    
dummy_request_handler_loop({Module, Function, Args}, Socket) ->
    receive 
	{tcp, _, Data} ->
	    test_server:format("dummy_request_handler_loop -> Data ~p~n", [Data]),
	    case handle_request(Module, Function, [Data | Args], Socket) of
		stop ->
		    gen_tcp:close(Socket);
		NewMFA ->
		    dummy_request_handler_loop(NewMFA, Socket)
	    end;
	stop ->
	    gen_tcp:close(Socket)
    end.

handle_request(Module, Function, Args, Socket) ->
    case Module:Function(Args) of
	{ok, Result} ->
	    case handle_http_msg(Result, Socket) of
		stop ->
		    stop;
		<<>> ->
		    {httpd_request, parse, [?HTTP_MAX_HEADER_SIZE]};
		Data ->	
		    handle_request(httpd_request, parse, 
				   [Data |[?HTTP_MAX_HEADER_SIZE]],
				   Socket)
	    end;
	NewMFA ->
	    NewMFA
    end.

handle_http_msg({_, RelUri, _, {_, Headers}, Body}, Socket) ->
    
    NextRequest = case RelUri of
		      "/dummy_headers.html" ->
			  <<>>;
		      "/no_headers.html" ->
			  stop;
		      "/just_close.html" ->
			  stop;
		      _ ->
			  ContentLength = content_length(Headers),    
			  case size(Body) - ContentLength of
			      0 ->
				  <<>>;
			      _ ->
				  <<_BodyThisReq:ContentLength/binary, 
				   Next/binary>> = Body,
				  Next
			  end
		  end,
   
    test_server:format("NextRequest: ~p~n", [NextRequest]),
 
    case (catch ets:lookup(cookie, cookies)) of 
	[{cookies, true}]->
	    test_server:format("Headers ~p~n", [Headers]),
	    check_cookie(Headers);
	_ ->
	    ok
    end,
    
    DefaultResponse = "HTTP/1.1 200 ok\r\n" ++
	"Content-Length:32\r\n\r\n"
	"<HTML><BODY>foobar</BODY></HTML>",

    Msg = 
	case RelUri of
	    "/just_close.html" ->
		close; 
	    "/no_content.html" ->
		"HTTP/1.0 204 No Content\r\n\r\n";
	    "/no_headers.html" ->
		"HTTP/1.0 200 OK\r\n\r\nTEST";
	    "/300.html" ->
		NewUri = ?URL_START ++
		    integer_to_list(?IP_PORT) ++ "/dummy.html",
		"HTTP/1.1 300 Multiple Choices\r\n" ++
		    "Location:" ++ NewUri ++  "\r\n" ++
		    "Content-Length:0\r\n\r\n";
	    "/301.html" ->
		NewUri = ?URL_START ++
		    integer_to_list(?IP_PORT) ++ "/dummy.html",
		"HTTP/1.1 301 Moved Permanently\r\n" ++
		    "Location:" ++ NewUri ++  "\r\n" ++
		    "Content-Length:80\r\n\r\n" ++
		    "<HTML><BODY><a href=" ++ NewUri ++
		    ">New place</a></BODY></HTML>";
	    "/302.html" ->
		NewUri = ?URL_START ++
		    integer_to_list(?IP_PORT) ++ "/dummy.html",
		"HTTP/1.1 302 Found \r\n" ++
		    "Location:" ++ NewUri ++  "\r\n" ++
		    "Content-Length:80\r\n\r\n" ++
		    "<HTML><BODY><a href=" ++ NewUri ++
		    ">New place</a></BODY></HTML>";
	    "/307.html" ->
		NewUri = ?URL_START ++
		    integer_to_list(?IP_PORT) ++ "/dummy.html",
		"HTTP/1.1 307 Temporary Rediect \r\n" ++
		    "Location:" ++ NewUri ++  "\r\n" ++
		    "Content-Length:80\r\n\r\n" ++
		    "<HTML><BODY><a href=" ++ NewUri ++
		    ">New place</a></BODY></HTML>";
	    "/500.html" ->
		"HTTP/1.1 500 Internal Server Error\r\n" ++
		    "Content-Length:47\r\n\r\n" ++
		    "<HTML><BODY>Internal Server Error</BODY<</HTML>";
	    "/503.html" ->
		case ets:lookup(unavailable, 503) of
		    [{503, unavailable}] -> 
			ets:insert(unavailable, {503, available}),
			"HTTP/1.1 503 Service Unavailable\r\n" ++
			    "Retry-After:5\r\n" ++
			    "Content-Length:47\r\n\r\n" ++
			    "<HTML><BODY>Internal Server Error</BODY></HTML>";
		    [{503, available}]   ->
			DefaultResponse;
		    [{503, long_unavailable}]  ->
			"HTTP/1.1 503 Service Unavailable\r\n" ++
			    "Retry-After:120\r\n" ++
			    "Content-Length:47\r\n\r\n" ++
			    "<HTML><BODY>Internal Server Error</BODY></HTML>"
		end;
	    "/redirectloop.html" -> %% Create a potential endless loop!
		{ok, Port} = inet:port(Socket),
		NewUri = ?URL_START ++
		    integer_to_list(Port) ++ "/redirectloop.html",
		"HTTP/1.1 300 Multiple Choices\r\n" ++
		    "Location:" ++ NewUri ++  "\r\n" ++
		    "Content-Length:0\r\n\r\n";
	    "/userinfo.html" ->
		Challange = "HTTP/1.1 401 Unauthorized \r\n" ++
		    "WWW-Authenticate:Basic" ++"\r\n" ++
		    "Content-Length:0\r\n\r\n",
		case auth_header(Headers) of
		    {ok, Value} ->
			handle_auth(Value, Challange, DefaultResponse);
		    _ ->
			Challange
		end;
	    "/dummy_headers.html" ->
		%% The client will only care about the Transfer-Encoding
		%% header the rest of these headers are left to the
		%% user to evaluate. This is not a valid response 
		%% it only tests that the header handling code works.
		Head = "HTTP/1.1 200 ok\r\n" ++
		    "Content-Length:32\r\n" ++
		    "Pragma:1#no-cache\r\n"  ++
		    "Via:1.0 fred, 1.1 nowhere.com (Apache/1.1)\r\n"  ++
		    "Warning:1#pseudonym foobar\r\n"  ++
		    "Vary:*\r\n"  ++
		    "Trailer:Other:inets_test\r\n"  ++
		    "Upgrade:HTTP/2.0\r\n"  ++
		    "Age:4711\r\n" ++ 
		    "Transfer-Encoding:chunked\r\n" ++
		    "Content-Encoding:foo\r\n" ++
		    "Content-Language:en\r\n"  ++
		    "Content-Location:http://www.foobar.se\r\n"  ++
		    "Content-MD5:104528739076276072743283077410617235478\r\n" 
		    ++
		    "Content-Range:Sat, 29 Oct 1994 19:43:31 GMT\r\n"  ++
		    "Expires:Sat, 29 Oct 1994 19:43:31 GMT\r\n"  ++
		    "Proxy-Authenticate:#1Basic"  ++
		    "\r\n\r\n",
		gen_tcp:send(Socket, Head),
		gen_tcp:send(Socket, http_chunk:encode("<HTML><BODY>fo")),
		gen_tcp:send(Socket, http_chunk:encode("obar</BODY></HTML>")),
		http_chunk:encode_last();
	    "/capital_transfer_encoding.html" ->
		Head =  "HTTP/1.1 200 ok\r\n" ++
		    "Transfer-Encoding:Chunked\r\n\r\n",
		gen_tcp:send(Socket, Head),
		gen_tcp:send(Socket, http_chunk:encode("<HTML><BODY>fo")),
		gen_tcp:send(Socket, http_chunk:encode("obar</BODY></HTML>")),
		http_chunk:encode_last();
	    "/cookie.html" ->
		"HTTP/1.1 200 ok\r\n" ++
		    "set-cookie:" ++ "test_cookie=true; path=/;" ++
		    "max-age=60000\r\n" ++
		    "Content-Length:32\r\n\r\n"++
		    "<HTML><BODY>foobar</BODY></HTML>";
	    "/missing_crlf.html" ->
		"HTTP/1.1 200 ok" ++
		    "Content-Length:32\r\n" ++
		    "<HTML><BODY>foobar</BODY></HTML>";
	    "/wrong_statusline.html" ->
		"ok 200 HTTP/1.1\r\n\r\n" ++
		    "Content-Length:32\r\n\r\n" ++
		    "<HTML><BODY>foobar</BODY></HTML>";
	    "/once_chunked.html" ->
		Head =  "HTTP/1.1 200 ok\r\n" ++
		    "Transfer-Encoding:Chunked\r\n\r\n",
		gen_tcp:send(Socket, Head),
		gen_tcp:send(Socket, http_chunk:encode("<HTML><BODY>fo")),
		gen_tcp:send(Socket, 
			     http_chunk:encode("obar</BODY></HTML>")),
		http_chunk:encode_last();
	    "/once.html" ->
		Head =  "HTTP/1.1 200 ok\r\n" ++
		    "Content-Length:32\r\n\r\n", 
		gen_tcp:send(Socket, Head), 
		gen_tcp:send(Socket, "<HTML><BODY>fo"),
		test_server:sleep(1000),
		gen_tcp:send(Socket, "ob"),
		test_server:sleep(1000),
		gen_tcp:send(Socket, "ar</BODY></HTML>");
	    "/invalid_http.html" ->
		"HTTP/1.1 301\r\nDate:Sun, 09 Dec 2007 13:04:18 GMT\r\n" ++ 
		    "Transfer-Encoding:chunked\r\n\r\n";
	    "/missing_reason_phrase.html" ->
		"HTTP/1.1 200\r\n" ++
		    "Content-Length: 32\r\n\r\n"
		    "<HTML><BODY>foobar</BODY></HTML>";
	    "/missing_CR.html" ->
		"HTTP/1.1 200 ok\n" ++
		    "Content-Length:32\r\n\n"
		    "<HTML><BODY>foobar</BODY></HTML>";
	    _ ->
		DefaultResponse
	end,
    
    test_server:format("Msg: ~p~n", [Msg]),
    case Msg of
	close ->
	    %% Nothing to send, just close
	    gen_tcp:close(Socket);
	_ ->
	    gen_tcp:send(Socket, Msg)
    end,
    NextRequest.

auth_header([]) ->
    auth_header_not_found;
auth_header(["authorization:" ++ Value | _]) ->
    {ok, string:strip(Value)};
auth_header([_ | Tail]) ->
    auth_header(Tail).

handle_auth("Basic " ++ UserInfo, Challange, DefaultResponse) ->
    case string:tokens(base64:decode_to_string(UserInfo), ":") of
	["alladin", "sesame"] = Auth ->
	    test_server:format("Auth: ~p~n", [Auth]),
	    DefaultResponse;
	Other ->
	    test_server:format("UnAuth: ~p~n", [Other]),
	    Challange
    end.

check_cookie([]) ->
    test_server:fail(no_cookie_header);
check_cookie(["cookie:" ++ _Value | _]) ->
    ok;
check_cookie([_Head | Tail]) ->
   check_cookie(Tail).

content_length([]) ->
    0;
content_length(["content-length:" ++ Value | _]) ->
    list_to_integer(string:strip(Value));
content_length([_Head | Tail]) ->
   content_length(Tail).

provocate_not_modified_bug(Url) ->
    Timeout = 15000, %% 15s should be plenty

    {ok, {{_, 200, _}, ReplyHeaders, _Body}} =
	http:request(get, {Url, []}, [{timeout, Timeout}], []),
    Etag = pick_header(ReplyHeaders, "ETag"),
    Last = pick_header(ReplyHeaders, "last-modified"),
    
    case http:request(get, {Url, [{"If-None-Match", Etag},
				  {"If-Modified-Since", Last}]},
		      [{timeout, 15000}],
		      []) of
	{ok, {{_, 304, _}, _, _}} -> %% The expected reply
	    page_unchanged;
	{ok, {{_, 200, _}, _, _}} -> %% If the page has changed since the
	                             %% last request we retry to
	                             %% trigger the bug
	    provocate_not_modified_bug(Url);
	{error, timeout} ->
	    %% Not what we expected. Tcpdump can be used to
	    %% verify that we receive the complete http-reply
	    %% but still time out.
	    incorrect_result
    end.

pick_header(Headers, Name) ->
    case lists:keysearch(string:to_lower(Name), 1,
			 [{string:to_lower(X), Y} || {X, Y} <- Headers]) of
	false ->
	    [];
	{value, {_Key, Val}} ->
	    Val
    end.


%% p(F, A) ->
%%     io:format("~p ~w:" ++ F ++ "~n", [self(), ?MODULE | A]).
