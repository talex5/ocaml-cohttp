open Cohttp_eio

let read_body req =
  let body = Request.read_fixed req in
  Server.text_response @@ Fmt.str "%a\n\n%s" Request.pp req body

let app req =
  match Request.resource req with
  | "/get" -> Server.text_response (Fmt.to_to_string Request.pp req)
  | "/get_error" -> (
      try
        let _ = Request.read_fixed req in
        assert false
      with Invalid_argument e -> Server.text_response e)
  | "/post" -> read_body req
  | _ -> Server.bad_request_response

let () = Eio_main.run @@ fun env -> Server.run ~port:8080 env app
