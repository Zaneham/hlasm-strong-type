open Types

type diag = {
  line : int;
  col_start : int;
  col_end : int;
  severity : [ `Error | `Warning | `Info ];
  message : string;
}

let fpops = [
  "LE"; "LER"; "LD"; "LDR"; "STE"; "STD";
  "AE"; "AER"; "AD"; "ADR";
  "SE"; "SER"; "SD"; "SDR";
  "ME"; "MER"; "MD"; "MDR";
  "DE"; "DER"; "DD"; "DDR";
  "CE"; "CER"; "CD"; "CDR";
  "AW"; "AWR"; "SW"; "SWR";
  "HDR"; "HER"; "LCER"; "LCDR";
  "LNER"; "LNDR"; "LPER"; "LPDR";
  "LTER"; "LTDR"; "SQER"; "SQDR";
]

let adops = [
  "LA"; "LAE"; "LAM"; "LAY"; "LARL";
  "BAL"; "BALR"; "BAS"; "BASR";
]

let rtname = function
  | General -> "general"
  | Address -> "address"
  | Float -> "float"
  | Control -> "control"

let fndcol raw name =
  let uline = String.uppercase_ascii raw in
  let uname = String.uppercase_ascii name in
  let nlen = String.length uname in
  let llen = min (String.length uline) 71 in
  let found = ref (-1) in
  for i = 0 to llen - nlen do
    if !found < 0 && String.sub uline i nlen = uname then
      found := i
  done;
  if !found >= 0 then (!found, !found + nlen)
  else (9, 9 + nlen)

let sym_name = function Sym s -> Some s | _ -> None

let chktyp regs (stmt : statement) =
  let op = String.uppercase_ascii stmt.op in
  let out = ref [] in
  List.iter (fun operand ->
    match sym_name operand with
    | None -> ()
    | Some sn ->
      let upper = String.uppercase_ascii sn in
      match Hashtbl.find_opt regs upper with
      | None -> ()
      | Some (reg : register) ->
        if List.mem op fpops && reg.rtype <> Float then begin
          let cs, ce = fndcol stmt.raw sn in
          out := {
            line = stmt.line; col_start = cs; col_end = ce;
            severity = `Warning;
            message = Printf.sprintf
              "%s is a %s register but %s requires a float register"
              reg.name (rtname reg.rtype) op;
          } :: !out
        end
        else if List.mem op adops && reg.rtype = Float then begin
          let cs, ce = fndcol stmt.raw sn in
          out := {
            line = stmt.line; col_start = cs; col_end = ce;
            severity = `Warning;
            message = Printf.sprintf
              "%s is a float register but %s expects general/address"
              reg.name op;
          } :: !out
        end
  ) stmt.operands;
  !out

let chkodd regs (stmt : statement) =
  let op = String.uppercase_ascii stmt.op in
  if not (List.mem op fpops) then []
  else begin
    let out = ref [] in
    List.iter (fun operand ->
      match sym_name operand with
      | None -> ()
      | Some sn ->
        let upper = String.uppercase_ascii sn in
        match Hashtbl.find_opt regs upper with
        | Some (reg : register) when reg.rtype = Float
                                     && reg.number mod 2 <> 0 ->
          let cs, ce = fndcol stmt.raw sn in
          out := {
            line = stmt.line; col_start = cs; col_end = ce;
            severity = `Warning;
            message = Printf.sprintf
              "float register %s (R%d) has odd number; \
               even registers expected"
              reg.name reg.number;
          } :: !out
        | _ -> ()
    ) stmt.operands;
    !out
  end

let run regs stmts =
  let out = ref [] in
  Array.iter (fun (stmt : statement) ->
    let op = String.uppercase_ascii stmt.op in
    if op <> "*" && op <> "" then begin
      out := chktyp regs stmt @ !out;
      out := chkodd regs stmt @ !out
    end
  ) stmts;
  List.rev !out
