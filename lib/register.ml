open Types

let parse_reg_type s =
  match String.uppercase_ascii (String.trim s) with
  | "G" -> Some General
  | "A" -> Some Address
  | "F" -> Some Float
  | "C" -> Some Control
  | _ -> None

let resolve_reg_number operands =
  match operands with
  | Sym s :: _ ->
    let upper = String.uppercase_ascii s in
    let len = String.length upper in
    if len >= 2 && len <= 3 && upper.[0] = 'R' then
      match int_of_string_opt (String.sub upper 1 (len - 1)) with
      | Some n when n >= 0 && n <= 15 -> Some n
      | _ -> None
    else None
  | Reg n :: _ -> Some n
  | _ -> None

let scan_equregs stmts =
  let regs : (string, register) Hashtbl.t = Hashtbl.create 32 in
  Array.iter (fun (stmt : statement) ->
    if String.uppercase_ascii stmt.op = "EQUREG" then begin
      match stmt.label with
      | None -> ()
      | Some name ->
        let upper_name = String.uppercase_ascii name in
        let number = resolve_reg_number stmt.operands in
        let rtype =
          match stmt.operands with
          | _ :: Sym t :: _ -> parse_reg_type t
          | _ :: Raw t :: _ -> parse_reg_type t
          | _ -> None
        in
        match number, rtype with
        | Some n, Some rt ->
          Hashtbl.replace regs upper_name
            { name = upper_name; number = n; rtype = rt }
        | Some n, None ->
          Hashtbl.replace regs upper_name
            { name = upper_name; number = n; rtype = General }
        | _ -> ()
    end
  ) stmts;
  regs

let scan_labels stmts =
  let labels : (string, int) Hashtbl.t = Hashtbl.create 64 in
  Array.iter (fun (stmt : statement) ->
    match stmt.label with
    | Some name when stmt.op <> "*" ->
      Hashtbl.replace labels (String.uppercase_ascii name) stmt.line
    | _ -> ()
  ) stmts;
  labels
