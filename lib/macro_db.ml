type mcdef = {
  name : string;
  description : string;
  category : string;
  parameters : string list;
  source : string;
}

type cbfld = {
  name : string;
  control_block : string;
  field_type : string;
  storage_type : string;
  length : int;
  parent : string;
  description : string;
}

type t = {
  macros : (string, mcdef) Hashtbl.t;
  fields : (string, cbfld) Hashtbl.t;
}

let str_member key obj =
  match List.assoc_opt key obj with
  | Some (`String s) -> s
  | _ -> ""

let str_list key obj =
  match List.assoc_opt key obj with
  | Some (`List items) ->
    List.filter_map (function `String s -> Some s | _ -> None) items
  | _ -> []

let int_member key obj =
  match List.assoc_opt key obj with
  | Some (`Int n) -> n
  | _ -> 0

let parse_macro obj =
  match obj with
  | `Assoc f ->
    Some {
      name = str_member "name" f;
      description = str_member "description" f;
      category = str_member "category" f;
      parameters = str_list "parameters" f;
      source = str_member "source" f;
    }
  | _ -> None

let parse_field cb obj =
  match obj with
  | `Assoc f ->
    Some {
      name = str_member "name" f;
      control_block = cb;
      field_type = str_member "fieldType" f;
      storage_type = str_member "storageType" f;
      length = int_member "length" f;
      parent = str_member "parent" f;
      description = str_member "description" f;
    }
  | _ -> None

let load path =
  let macros = Hashtbl.create 300 in
  let fields = Hashtbl.create 8000 in
  (match Yojson.Safe.from_file path with
   | exception _ -> ()
   | `Assoc top ->
     (match List.assoc_opt "macros" top with
      | Some (`List items) ->
        List.iter (fun item ->
          match parse_macro item with
          | Some m ->
            Hashtbl.replace macros (String.uppercase_ascii m.name) m
          | None -> ()
        ) items
      | _ -> ());
     (match List.assoc_opt "controlBlocks" top with
      | Some (`Assoc cbs) ->
        List.iter (fun (cb, data) ->
          match data with
          | `Assoc cb_obj ->
            (match List.assoc_opt "fields" cb_obj with
             | Some (`List flds) ->
               List.iter (fun f ->
                 match parse_field cb f with
                 | Some fld ->
                   Hashtbl.replace fields
                     (String.uppercase_ascii fld.name) fld
                 | None -> ()
               ) flds
             | _ -> ())
          | _ -> ()
        ) cbs
      | _ -> ())
   | _ -> ());
  { macros; fields }

let find_macro db name =
  Hashtbl.find_opt db.macros (String.uppercase_ascii name)

let find_field db name =
  Hashtbl.find_opt db.fields (String.uppercase_ascii name)

let empty () = {
  macros = Hashtbl.create 1;
  fields = Hashtbl.create 1;
}
