let src = Logs.Src.create "cohttp.eio" ~doc:"Cohttp Eio module"
include (val Logs.src_log src : Logs.LOG)
