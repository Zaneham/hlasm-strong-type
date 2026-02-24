let regcnv = [|
  "R0  - Work register / parameter passing";
  "R1  - Parameter pointer / work register";
  "R2  - Work register";
  "R3  - Work register";
  "R4  - Work register";
  "R5  - Work register";
  "R6  - Work register";
  "R7  - Work register";
  "R8  - Work register";
  "R9  - Work register";
  "R10 - Work register";
  "R11 - Work register";
  "R12 - Base register (conventional)";
  "R13 - Save area pointer";
  "R14 - Return address";
  "R15 - Entry point / return code";
|]

let hover_macro (m : Macro_db.mcdef) =
  let buf = Buffer.create 256 in
  Buffer.add_string buf (Printf.sprintf "## %s\n\n" m.name);
  if m.description <> "" then
    Buffer.add_string buf (Printf.sprintf "%s\n\n" m.description);
  if m.parameters <> [] then begin
    Buffer.add_string buf "**Parameters:** ";
    Buffer.add_string buf (String.concat ", " m.parameters);
    Buffer.add_string buf "\n\n"
  end;
  if m.category <> "" then
    Buffer.add_string buf (Printf.sprintf "*Category: %s*\n" m.category);
  if m.source <> "" then
    Buffer.add_string buf (Printf.sprintf "*Source: %s*\n" m.source);
  Buffer.contents buf

let hover_field (f : Macro_db.cbfld) =
  let buf = Buffer.create 256 in
  Buffer.add_string buf
    (Printf.sprintf "## %s (%s)\n\n" f.name f.control_block);
  if f.description <> "" then
    Buffer.add_string buf (Printf.sprintf "%s\n\n" f.description);
  Buffer.add_string buf "| Property | Value |\n|---|---|\n";
  Buffer.add_string buf
    (Printf.sprintf "| Control Block | %s |\n" f.control_block);
  if f.field_type <> "" then
    Buffer.add_string buf
      (Printf.sprintf "| Field Type | %s |\n" f.field_type);
  if f.storage_type <> "" then
    Buffer.add_string buf
      (Printf.sprintf "| Storage Type | %s |\n" f.storage_type);
  if f.length > 0 then
    Buffer.add_string buf
      (Printf.sprintf "| Length | %d |\n" f.length);
  if f.parent <> "" then
    Buffer.add_string buf
      (Printf.sprintf "| Parent | %s |\n" f.parent);
  Buffer.contents buf

let hover_register n =
  if n >= 0 && n <= 15 then
    Printf.sprintf "## Register R%d\n\n```\n%s\n```\n" n regcnv.(n)
  else
    ""

let rtname = function
  | Types.General -> "General"
  | Types.Address -> "Address"
  | Types.Float -> "Float"
  | Types.Control -> "Control"

let hover_equreg (reg : Types.register) =
  Printf.sprintf "## %s (EQUREG)\n\nRegister R%d, type: **%s**\n"
    reg.name reg.number (rtname reg.rtype)

let hover_for_word ?(regs=None) db word =
  let upper = String.uppercase_ascii word in
  let len = String.length upper in
  (match regs with
   | Some tbl ->
     (match Hashtbl.find_opt tbl upper with
      | Some reg -> Some (hover_equreg reg)
      | None -> None)
   | None -> None)
  |> function
  | Some _ as hit -> hit
  | None ->
    if len >= 2 && len <= 3 && upper.[0] = 'R' then
      match int_of_string_opt (String.sub upper 1 (len - 1)) with
      | Some n when n >= 0 && n <= 15 -> Some (hover_register n)
      | _ -> None
    else
      match Macro_db.find_macro db upper with
      | Some m -> Some (hover_macro m)
      | None ->
        match Macro_db.find_field db upper with
        | Some f -> Some (hover_field f)
        | None -> None
