open Cohttp_eio
open Cohttp_eio.Server

let dump_chunk buf chunk =
  let s = Format.asprintf "\n%a" Body.pp_chunk chunk in
  Buffer.add_string buf s

let app req =
  match Request.resource req with
  | "/" -> (
      let chunk_buf = Buffer.create 0 in
      match Request.read_chunked req (dump_chunk chunk_buf) with
      | headers ->
          let req = Request.with_headers headers req in
          Buffer.contents chunk_buf
          |> Format.asprintf "%a@ %s%!" Request.pp req
          |> Server.text_response
      | exception Invalid_argument _ -> Server.bad_request_response)
  | _ -> Server.not_found_response

let () =
  let port = ref 8080 in
  Arg.parse
    [ ("-p", Arg.Set_int port, " Listening port number(8080 by default)") ]
    ignore "An HTTP/1.1 server";

  Eio_main.run @@ fun env -> run ~port:!port env app
