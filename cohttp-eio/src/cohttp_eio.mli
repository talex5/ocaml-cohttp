module Body : sig
  type t =
    | Fixed of string
    | Chunked of chunk_writer
    | Custom of (Eio.Buf_write.t -> unit)
    | Empty

  and chunk_writer = {
    body_writer : (chunk -> unit) -> unit;
    trailer_writer : (Http.Header.t -> unit) -> unit;
  }

  (** [Chunk] encapsulates HTTP/1.1 chunk transfer encoding data structures.
      https://datatracker.ietf.org/doc/html/rfc7230#section-4.1 *)
  and chunk = Chunk of chunk_body | Last_chunk of chunk_extension list

  and chunk_body = {
    size : int;
    data : string;
    extensions : chunk_extension list;
  }

  and chunk_extension = { name : string; value : string option }

  val pp_chunk_extension : Format.formatter -> chunk_extension list -> unit
  val pp_chunk : Format.formatter -> chunk -> unit
end

module Request : sig
  type t
  (** An HTTP request. *)

  val of_http :
    reader:Eio.Buf_read.t ->
    client_addr:Eio.Net.Sockaddr.stream ->
    Http.Request.t ->
    t

  val pp : t Fmt.t
  val client_addr : t -> Eio.Net.Sockaddr.stream

  (** {2 Http.Request wrappers}

      These provide direct access to the wrapped {!Http.Request.t}. *)

  val http_request : t -> Http.Request.t
  val has_body : t -> [ `No | `Unknown | `Yes ]
  val headers : t -> Http.Header.t
  val meth : t -> Http.Method.t
  val scheme : t -> string option
  val resource : t -> string
  val version : t -> Http.Version.t
  val encoding : t -> Http.Transfer.encoding
  val is_keep_alive : t -> bool
  val with_headers : Http.Header.t -> t -> t

  (** {2 Reading the body} *)

  val read_fixed : t -> string
  (** [read_fixed t] reads a string of length [n] if "Content-Length" header is
      a valid integer value [n] in [t].

      @raise Invalid_argument
        if ["Content-Length"] header is missing or is an invalid value in
        [headers] OR if the request http method is not one of [POST], [PUT] or
        [PATCH]. *)

  val read_chunked : t -> (Body.chunk -> unit) -> Http.Header.t
  (** [read_chunked t chunk_handler] is [updated_headers] if "Transfer-Encoding"
      header value is "chunked" in [headers] and all chunks in [reader] are read
      successfully. [updated_headers] is the updated headers as specified by the
      chunked encoding algorithm in
      https://datatracker.ietf.org/doc/html/rfc7230#section-4.1.3. Otherwise it
      is [Error err] where [err] is the error text.

      @raise Invalid_argument
        if [Transfer-Encoding] header in [headers] is not specified as "chunked" *)

  val reader : t -> Eio.Buf_read.t
  (** [reader t] provides direct access to the request flow.

      This may be useful when switching to another protocol. *)
end

(** [Server] is a HTTP 1.1 server. *)
module Server : sig
  type middleware = handler -> handler
  and handler = Request.t -> response
  and response = Http.Response.t * Body.t

  (** {1 Response} *)

  val text_response : string -> response
  (** [text t s] returns a HTTP/1.1, 200 status response with "Content-Type"
      header set to "text/plain". *)

  val html_response : string -> response
  (** [html t s] returns a HTTP/1.1, 200 status response with header set to
      "Content-Type: text/html". *)

  val not_found_response : response
  (** [not_found t] returns a HTTP/1.1, 404 status response. *)

  val internal_server_error_response : response
  (** [internal_server_error] returns a HTTP/1.1, 500 status response. *)

  val bad_request_response : response
  (* [bad_request t] returns a HTTP/1.1, 400 status response. *)

  (** {1 Run Server} *)

  val run :
    ?socket_backlog:int ->
    ?domains:int ->
    port:int ->
    Eio.Stdenv.t ->
    handler ->
    'a

  val connection_handler :
    handler -> #Eio.Net.stream_socket -> Eio.Net.Sockaddr.stream -> unit
  (** [connection_handler request_handler] is a connection handler, suitable for
      passing to {!Eio.Net.accept_fork}. *)

  (** {1 Basic Handlers} *)

  val not_found_handler : handler

  (** {1 Logging} *)

  val log_src : Logs.Src.t
end
