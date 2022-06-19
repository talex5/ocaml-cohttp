open Eio.Std

module Buf_write = Eio.Buf_write

let log_src = Log.src

type middleware = handler -> handler
and handler = request -> response
and request = Http.Request.t * Eio.Buf_read.t
and response = Http.Response.t * Body.t

let domain_count =
  match Sys.getenv_opt "COHTTP_DOMAINS" with
  | Some d -> int_of_string d
  | None -> 1

(* Request *)

let read_fixed ((request, reader) : request) =
  match request.meth with
  | `POST | `PUT | `PATCH -> Body.read_fixed reader request.headers
  | _ ->
      let err =
        Printf.sprintf
          "Request with HTTP method '%s' doesn't support request body"
          (Http.Method.to_string request.meth)
      in
      raise @@ Invalid_argument err

let read_chunked : request -> (Body.chunk -> unit) -> Http.Header.t =
 fun (request, reader) f -> Body.read_chunked reader request.headers f

(* Responses *)

let is_custom body = match body with Body.Custom _ -> true | _ -> false

let text_response body =
  let headers =
    Http.Header.of_list
      [
        ("content-type", "text/plain; charset=UTF-8");
        ("content-length", string_of_int @@ String.length body);
      ]
  in
  let response =
    Http.Response.make ~version:`HTTP_1_1 ~status:`OK ~headers ()
  in
  (response, Body.Fixed body)

let html_response body =
  let headers =
    Http.Header.of_list
      [
        ("content-type", "text/html; charset=UTF-8");
        ("content-length", string_of_int @@ String.length body);
      ]
  in
  let response =
    Http.Response.make ~version:`HTTP_1_1 ~status:`OK ~headers ()
  in
  (response, Body.Fixed body)

let not_found_response = (Http.Response.make ~status:`Not_found (), Body.Empty)

let internal_server_error_response =
  (Http.Response.make ~status:`Internal_server_error (), Body.Empty)

let bad_request_response =
  (Http.Response.make ~status:`Bad_request (), Body.Empty)

let write_response (writer : Buf_write.t)
    ((response, body) : Http.Response.t * Body.t) =
  let version = Http.Version.to_string response.version in
  let status = Http.Status.to_string response.status in
  Buf_write.write_string writer version;
  Buf_write.write_string writer " ";
  Buf_write.write_string writer status;
  Buf_write.write_string writer "\r\n";
  Body.write_headers writer response.headers;
  Buf_write.write_string writer "\r\n";
  match body with
  | Fixed s -> Buf_write.write_string writer s
  | Chunked chunk_writer -> Body.write_chunked writer chunk_writer
  | Custom _f ->
    failwith "TODO"
(*
      Buf_write.wakeup writer;
      f (writer.sink :> Eio.Flow.sink)
*)
  | Empty -> ()

(* main *)

let rec handle_request client_addr reader writer flow handler =
  match Reader.http_request reader with
  | request ->
      Log.info (fun f ->
        f "%a: %a %s"
          Eio.Net.Sockaddr.pp client_addr
          Http.Method.pp request.meth
          request.resource);
      let response, body = handler (request, reader) in
      write_response writer (response, body);
      if Http.Request.is_keep_alive request then
        handle_request client_addr reader writer flow handler
  | (exception End_of_file) | (exception Eio.Net.Connection_reset _) -> ()
  | exception Failure msg ->
      Log.info (fun f -> f "%a: bad request: %s" Eio.Net.Sockaddr.pp client_addr msg);
      write_response writer bad_request_response
  | exception ex ->
      write_response writer internal_server_error_response;
      raise ex

type connection_handler = sw:Eio.Switch.t -> <Eio.Flow.two_way; Eio.Flow.close> -> Eio.Net.Sockaddr.stream -> unit

let connection_handler : handler -> connection_handler = fun handler ~sw:_ flow client_addr ->
  let reader = Eio.Buf_read.of_flow ~initial_size:0x1000 ~max_size:max_int flow in
  Buf_write.with_flow flow (fun writer ->
      handle_request client_addr reader writer flow handler
    )

let log_connection_error ex =
  Log.warn (fun f -> f "Error handling connection: %a" Fmt.exn ex)

let run_domain ssock handler =
  let handler = connection_handler handler in
  Switch.run (fun sw ->
      let rec loop () =
        Eio.Net.accept_sub ~sw ssock ~on_error:log_connection_error handler;
        loop ()
      in
      loop ()
    )

let run ?(socket_backlog = 128) ?(domains = domain_count) ~port env handler =
  Switch.run @@ fun sw ->
  let domain_mgr = Eio.Stdenv.domain_mgr env in
  let ssock =
    Eio.Net.listen (Eio.Stdenv.net env) ~sw ~reuse_addr:true ~reuse_port:true
      ~backlog:socket_backlog
      (`Tcp (Eio.Net.Ipaddr.V4.loopback, port))
  in
  for _ = 2 to domains do
    Eio.Std.Fiber.fork ~sw (fun () ->
        Eio.Domain_manager.run domain_mgr (fun () -> run_domain ssock handler))
  done;
  run_domain ssock handler

(* Basic handlers *)

let not_found_handler _ = not_found_response
