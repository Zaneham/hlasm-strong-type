open Lsp.Types

let log fmt =
  Printf.ksprintf (fun s ->
    Printf.eprintf "[hlasm-lsp] %s\n%!" s) fmt

let read_message ic =
  let content_length = ref (-1) in
  let done_hdrs = ref false in
  let eof = ref false in
  let guard = ref 0 in
  while not !done_hdrs && not !eof && !guard < 32 do
    incr guard;
    match input_line ic with
    | exception End_of_file -> eof := true
    | line ->
      let line = String.trim line in
      if String.length line = 0 then
        done_hdrs := true
      else begin
        let lower = String.lowercase_ascii line in
        if String.length lower > 15 &&
           String.sub lower 0 16 = "content-length: " then
          let v = String.trim
                    (String.sub line 16 (String.length line - 16)) in
          content_length := (match int_of_string_opt v with
                             | Some n -> n | None -> -1)
      end
  done;
  if !eof || !content_length < 0 then None
  else begin
    let buf = Bytes.create !content_length in
    really_input ic buf 0 !content_length;
    Some (Yojson.Safe.from_string (Bytes.to_string buf))
  end

let send_json oc json =
  let body = Yojson.Safe.to_string json in
  let header = Printf.sprintf "Content-Length: %d\r\n\r\n"
                 (String.length body) in
  output_string oc header;
  output_string oc body;
  flush oc

let send_packet oc pkt =
  send_json oc (Jsonrpc.Packet.yojson_of_t pkt)

let send_response oc id result_json =
  send_packet oc
    (Jsonrpc.Packet.Response (Jsonrpc.Response.ok id result_json))

let send_error oc id code msg =
  let err = Jsonrpc.Response.Error.make ~code ~message:msg () in
  send_packet oc
    (Jsonrpc.Packet.Response (Jsonrpc.Response.error id err))

let send_notification oc notif =
  let n = Lsp.Server_notification.to_jsonrpc notif in
  send_packet oc (Jsonrpc.Packet.Notification n)

let data_dir_override = ref ""

let documents : (string, string) Hashtbl.t = Hashtbl.create 64
let doc_states : (string, Hlasm_lsp.Analysis.dstat) Hashtbl.t =
  Hashtbl.create 64
let macro_db = ref (Hlasm_lsp.Macro_db.empty ())
let shutdown_received = ref false
let macro_dirs : string list ref = ref []

let find_macro_file name =
  let fname = name ^ ".mac" in
  let result = ref None in
  let guard = ref 0 in
  List.iter (fun dir ->
    incr guard;
    if !result = None && !guard < 64 then begin
      let path = Filename.concat dir fname in
      if Sys.file_exists path then result := Some path
    end
  ) !macro_dirs;
  !result

let uri_key uri = Lsp.Uri.to_string uri

let diag_severity = function
  | `Error -> DiagnosticSeverity.Error
  | `Warning -> DiagnosticSeverity.Warning
  | `Info -> DiagnosticSeverity.Information

let analyse_and_publish oc uri text =
  let stmts = Hlasm_lsp.Parse_line.parse_document text in
  let state = Hlasm_lsp.Analysis.analyse stmts in
  let key = uri_key uri in
  Hashtbl.replace doc_states key state;
  let lsp_diags = List.map (fun (d : Hlasm_lsp.Diagnostics.diag) ->
    let range = Range.create
      ~start:(Position.create ~line:d.line ~character:d.col_start)
      ~end_:(Position.create ~line:d.line ~character:d.col_end) in
    Diagnostic.create
      ~range
      ~severity:(diag_severity d.severity)
      ~source:"hlasm-lsp"
      ~message:(`String d.message)
      ()
  ) state.diags in
  send_notification oc
    (Lsp.Server_notification.PublishDiagnostics
       (PublishDiagnosticsParams.create ~diagnostics:lsp_diags ~uri ()))

let is_ident_char c =
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
  (c >= '0' && c <= '9') || c = '@' || c = '#' || c = '$' || c = '_'

let word_at_position text line char =
  let lines = String.split_on_char '\n' text in
  let line_str = ref "" in
  let idx = ref 0 in
  List.iter (fun l ->
    if !idx = line then begin
      let n = String.length l in
      line_str := if n > 0 && l.[n - 1] = '\r'
                  then String.sub l 0 (n - 1) else l
    end;
    incr idx
  ) lines;
  let s = !line_str in
  let len = String.length s in
  if char >= len then None
  else if not (is_ident_char s.[char]) then None
  else begin
    let start = ref char in
    while !start > 0 && is_ident_char s.[!start - 1] do decr start done;
    let stop = ref char in
    while !stop < len - 1 && is_ident_char s.[!stop + 1] do incr stop done;
    Some (String.sub s !start (!stop - !start + 1))
  end

let do_initialize (params : InitializeParams.t) =
  let data_dir =
    if !data_dir_override <> "" then !data_dir_override
    else match params.rootUri with
      | Some uri ->
        let path = Lsp.Uri.to_path uri in
        path ^ "/data"
      | None -> "data"
  in
  let db_path = data_dir ^ "/macros.json" in
  log "loading macros from %s" db_path;
  macro_db := Hlasm_lsp.Macro_db.load db_path;
  log "loaded %d macros, %d fields"
    (Hashtbl.length !macro_db.macros)
    (Hashtbl.length !macro_db.fields);
  let td_sync =
    `TextDocumentSyncOptions
      (TextDocumentSyncOptions.create
         ~openClose:true
         ~change:TextDocumentSyncKind.Full
         ())
  in
  let caps = ServerCapabilities.create
    ~textDocumentSync:td_sync
    ~hoverProvider:(`Bool true)
    ~completionProvider:(CompletionOptions.create
      ~triggerCharacters:[" "]
      ())
    ~definitionProvider:(`Bool true)
    ~referencesProvider:(`Bool true)
    ()
  in
  let info = InitializeResult.create_serverInfo
    ~name:"hlasm-lsp" ~version:"0.3.0" () in
  InitializeResult.create ~capabilities:caps ~serverInfo:info ()

let do_hover (params : HoverParams.t) =
  let uri = params.textDocument.uri in
  let key = uri_key uri in
  match Hashtbl.find_opt documents key with
  | None -> None
  | Some text ->
    let line = params.position.line in
    let char = params.position.character in
    match word_at_position text line char with
    | None -> None
    | Some word ->
      let regs = match Hashtbl.find_opt doc_states key with
        | Some st -> Some st.regs
        | None -> None
      in
      match Hlasm_lsp.Hover.hover_for_word ~regs !macro_db word with
      | None -> None
      | Some md ->
        let content = MarkupContent.create
          ~kind:MarkupKind.Markdown ~value:md in
        Some (Hover.create ~contents:(`MarkupContent content) ())

let do_completion (params : CompletionParams.t) =
  let uri = params.textDocument.uri in
  let key = uri_key uri in
  let state = Hashtbl.find_opt doc_states key in
  match Hashtbl.find_opt documents key with
  | None -> None
  | Some text ->
    let line = params.position.line in
    let char = params.position.character in
    let prefix = match word_at_position text line char with
      | Some w -> w
      | None -> ""
    in
    let items = Hlasm_lsp.Completion.complete !macro_db state prefix in
    let lsp_items = List.map (fun (it : Hlasm_lsp.Completion.item) ->
      let kind = match it.kind with
        | `Keyword -> CompletionItemKind.Keyword
        | `Variable -> CompletionItemKind.Variable
        | `Function -> CompletionItemKind.Function
        | `Field -> CompletionItemKind.Field
        | `Value -> CompletionItemKind.Value
      in
      CompletionItem.create ~label:it.label ~kind
        ~detail:it.detail ()
    ) items in
    Some (`CompletionList
      (CompletionList.create ~isIncomplete:false ~items:lsp_items ()))

let do_definition (params : DefinitionParams.t) =
  let uri = params.textDocument.uri in
  let key = uri_key uri in
  match Hashtbl.find_opt documents key, Hashtbl.find_opt doc_states key with
  | Some text, Some state ->
    let line = params.position.line in
    let char = params.position.character in
    (match word_at_position text line char with
     | None -> None
     | Some word ->
       let upper = String.uppercase_ascii word in
        match Hashtbl.find_opt state.labels upper with
       | Some def_line ->
         let range = Range.create
           ~start:(Position.create ~line:def_line ~character:0)
           ~end_:(Position.create ~line:def_line ~character:
                    (String.length word)) in
         Some (`Location [Location.create ~uri ~range])
       | None ->
         match Hashtbl.find_opt state.regs upper with
         | Some (reg : Hlasm_lsp.Types.register) ->
           let def_line = ref (-1) in
           Array.iter (fun (stmt : Hlasm_lsp.Types.statement) ->
             match stmt.label with
             | Some name when String.uppercase_ascii name = reg.name ->
               if !def_line < 0 then def_line := stmt.line
             | _ -> ()
           ) state.stmts;
           if !def_line >= 0 then begin
             let range = Range.create
               ~start:(Position.create ~line:!def_line ~character:0)
               ~end_:(Position.create ~line:!def_line ~character:
                        (String.length reg.name)) in
             Some (`Location [Location.create ~uri ~range])
           end else None
         | None ->
           (* check macro source files *)
           (match Hlasm_lsp.Macro_db.find_macro !macro_db upper with
            | Some _ ->
              (match find_macro_file upper with
               | Some path ->
                 let mac_uri = Lsp.Uri.of_path path in
                 let range = Range.create
                   ~start:(Position.create ~line:0 ~character:0)
                   ~end_:(Position.create ~line:0 ~character:0) in
                 Some (`Location [Location.create ~uri:mac_uri ~range])
               | None -> None)
            | None -> None))
  | _ -> None

let do_references (params : ReferenceParams.t) =
  let uri = params.textDocument.uri in
  let key = uri_key uri in
  match Hashtbl.find_opt documents key, Hashtbl.find_opt doc_states key with
  | Some text, Some state ->
    let line = params.position.line in
    let char = params.position.character in
    (match word_at_position text line char with
     | None -> None
     | Some word ->
       let upper = String.uppercase_ascii word in
       let incl_decl = params.context.includeDeclaration in
       let locs = ref [] in
       let add ln cs ce =
         let range = Range.create
           ~start:(Position.create ~line:ln ~character:cs)
           ~end_:(Position.create ~line:ln ~character:ce) in
         locs := Location.create ~uri ~range :: !locs
       in
       Array.iter (fun (stmt : Hlasm_lsp.Types.statement) ->
         (* label field = declaration site *)
         (match stmt.label with
          | Some name when String.uppercase_ascii name = upper ->
            if incl_decl then add stmt.line 0 (String.length name)
          | _ -> ());
         (* operands = symbol references *)
         let rec chkop = function
           | Hlasm_lsp.Types.Sym s
             when String.uppercase_ascii s = upper ->
             let cs, ce = Hlasm_lsp.Diagnostics.fndcol stmt.raw s in
             add stmt.line cs ce
           | Hlasm_lsp.Types.Addr { disp; base; index } ->
             chkop disp; chkop base;
             (match index with Some i -> chkop i | None -> ())
           | _ -> ()
         in
         List.iter chkop stmt.operands
       ) state.stmts;
       match !locs with
       | [] -> None
       | l -> Some (List.rev l))
  | _ -> None

let dispatch : type a. out_channel -> Jsonrpc.Id.t ->
               a Lsp.Client_request.t -> unit =
  fun oc id req ->
    let open Lsp.Client_request in
    match req with
    | Initialize params ->
      let result = do_initialize params in
      send_response oc id (yojson_of_result req result)
    | Shutdown ->
      shutdown_received := true;
      send_response oc id (yojson_of_result req ())
    | TextDocumentHover params ->
      let result = do_hover params in
      send_response oc id (yojson_of_result req result)
    | TextDocumentCompletion params ->
      let result = do_completion params in
      send_response oc id (yojson_of_result req result)
    | TextDocumentDefinition params ->
      let result = do_definition params in
      send_response oc id (yojson_of_result req result)
    | TextDocumentReferences params ->
      let result = do_references params in
      send_response oc id (yojson_of_result req result)
    | _ ->
      send_error oc id
        Jsonrpc.Response.Error.Code.MethodNotFound
        "method not supported"

let handle_request oc (req : Jsonrpc.Request.t) =
  match Lsp.Client_request.of_jsonrpc req with
  | Error msg ->
    send_error oc req.id
      Jsonrpc.Response.Error.Code.InvalidRequest msg
  | Ok (Lsp.Client_request.E r) ->
    dispatch oc req.id r

let handle_notification oc (notif : Jsonrpc.Notification.t) =
  match Lsp.Client_notification.of_jsonrpc notif with
  | Error _ -> ()
  | Ok n ->
    let open Lsp.Client_notification in
    (match n with
    | TextDocumentDidOpen params ->
      let uri = params.textDocument.uri in
      let text = params.textDocument.text in
      let key = uri_key uri in
      Hashtbl.replace documents key text;
      log "opened %s (%d bytes)" key (String.length text);
      analyse_and_publish oc uri text
    | TextDocumentDidChange params ->
      let uri = params.textDocument.uri in
      let key = uri_key uri in
      (match params.contentChanges with
       | [] -> ()
       | change :: _ ->
         let text = change.text in
         Hashtbl.replace documents key text;
         analyse_and_publish oc uri text)
    | TextDocumentDidClose params ->
      let uri = params.textDocument.uri in
      let key = uri_key uri in
      Hashtbl.remove documents key;
      Hashtbl.remove doc_states key;
      send_notification oc
        (Lsp.Server_notification.PublishDiagnostics
           (PublishDiagnosticsParams.create ~diagnostics:[] ~uri ()));
      log "closed %s" key
    | Initialized ->
      log "initialized"
    | Exit ->
      exit (if !shutdown_received then 0 else 1)
    | _ -> ())

let parse_argv () =
  let argc = Array.length Sys.argv in
  let i = ref 1 in
  while !i < argc do
    if Sys.argv.(!i) = "--data-dir" && !i + 1 < argc then begin
      data_dir_override := Sys.argv.(!i + 1);
      i := !i + 2
    end else if Sys.argv.(!i) = "--macro-dir" && !i + 1 < argc then begin
      macro_dirs := Sys.argv.(!i + 1) :: !macro_dirs;
      i := !i + 2
    end else
      incr i
  done

let () =
  parse_argv ();
  set_binary_mode_in stdin true;
  set_binary_mode_out stdout true;
  log "hlasm-lsp starting";
  let running = ref true in
  while !running do
    match read_message stdin with
    | None -> running := false
    | Some json ->
      (match Jsonrpc.Packet.t_of_yojson json with
      | exception exn ->
        log "packet parse error: %s" (Printexc.to_string exn)
      | pkt ->
        (match pkt with
         | Jsonrpc.Packet.Request req ->
           handle_request stdout req
         | Jsonrpc.Packet.Notification notif ->
           handle_notification stdout notif
         | _ -> ()))
  done;
  log "hlasm-lsp exiting"
