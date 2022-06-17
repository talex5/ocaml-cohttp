type t = {
  http : Http.Request.t;
  reader : Eio.Buf_read.t;
  client_addr : Eio.Net.Sockaddr.stream;
}

let of_http ~reader ~client_addr http = { http; reader; client_addr }
let meth t = Http.Request.meth t.http
let scheme t = Http.Request.scheme t.http
let resource t = Http.Request.resource t.http
let version t = Http.Request.version t.http
let encoding t = Http.Request.encoding t.http
let is_keep_alive t = Http.Request.is_keep_alive t.http
let has_body t = Http.Request.has_body t.http
let headers t = Http.Request.headers t.http
let pp f t = Http.Request.pp f t.http
let http_request t = t.http
let client_addr t = t.client_addr
let reader t = t.reader
let with_headers headers t = { t with http = { t.http with headers } }

let read_fixed t =
  match meth t with
  | `POST | `PUT | `PATCH -> Body.read_fixed t.reader (headers t)
  | meth ->
      let err =
        Printf.sprintf
          "Request with HTTP method '%s' doesn't support request body"
          (Http.Method.to_string meth)
      in
      raise @@ Invalid_argument err

let read_chunked : t -> (Body.chunk -> unit) -> Http.Header.t =
 fun t f -> Body.read_chunked t.reader (headers t) f
