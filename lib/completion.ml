let instrs = [|
  "A"; "AH"; "AL"; "ALR"; "AP"; "AR";
  "BAL"; "BALR"; "BAS"; "BASR"; "BC"; "BCR"; "BCT"; "BCTR";
  "B"; "BE"; "BNE"; "BH"; "BNH"; "BL"; "BNL"; "BZ"; "BNZ";
  "BP"; "BM"; "BO"; "BNO";
  "C"; "CH"; "CL"; "CLC"; "CLCL"; "CLI"; "CLR"; "CP"; "CR";
  "CVB"; "CVD";
  "D"; "DP"; "DR";
  "ED"; "EDMK"; "EX";
  "IC"; "ICM";
  "L"; "LA"; "LCR"; "LH"; "LM"; "LNR"; "LPR"; "LR"; "LTR";
  "M"; "MH"; "MP"; "MR"; "MVC"; "MVCL"; "MVI"; "MVN"; "MVO"; "MVZ";
  "N"; "NC"; "NI"; "NR";
  "O"; "OC"; "OI"; "OR";
  "PACK";
  "S"; "SH"; "SL"; "SLA"; "SLDA"; "SLDL"; "SLL";
  "SP"; "SR"; "SRA"; "SRDA"; "SRDL"; "SRL"; "SRP";
  "ST"; "STC"; "STCM"; "STH"; "STM";
  "SVC";
  "TM"; "TR"; "TRT";
  "UNPK";
  "X"; "XC"; "XI"; "XR";
  "ZAP";
  "CSECT"; "DSECT"; "DC"; "DS"; "EQU"; "USING"; "DROP";
  "ENTRY"; "EXTRN"; "LTORG"; "ORG"; "END";
  "COPY"; "PRINT"; "TITLE"; "SPACE"; "EJECT";
  "LE"; "LER"; "LD"; "LDR"; "STE"; "STD";
  "AE"; "AER"; "AD"; "ADR";
  "SE"; "SER"; "SD"; "SDR";
  "ME"; "MER"; "MD"; "MDR";
  "DE"; "DER"; "DD"; "DDR";
  "CE"; "CER"; "CD"; "CDR";
|]

type item = {
  label : string;
  kind : [`Keyword | `Variable | `Function | `Field | `Value];
  detail : string;
}

let instr_items =
  Array.to_list (Array.map (fun i ->
    { label = i; kind = `Keyword; detail = "HLASM instruction" }
  ) instrs)

let macro_items db =
  Hashtbl.fold (fun _key (m : Macro_db.mcdef) acc ->
    { label = m.name; kind = `Function;
      detail = if m.description <> "" then m.description
               else "Macro" } :: acc
  ) db.Macro_db.macros []

let reg_items regs =
  Hashtbl.fold (fun _key (r : Types.register) acc ->
    let rt = match r.rtype with
      | Types.General -> "General" | Types.Address -> "Address"
      | Types.Float -> "Float" | Types.Control -> "Control"
    in
    { label = r.name; kind = `Variable;
      detail = Printf.sprintf "R%d (%s)" r.number rt } :: acc
  ) regs []

let label_items labels =
  Hashtbl.fold (fun name line acc ->
    { label = name; kind = `Value;
      detail = Printf.sprintf "Label (line %d)" (line + 1) } :: acc
  ) labels []

let bare_regs () =
  let items = ref [] in
  for i = 0 to 15 do
    items := { label = Printf.sprintf "R%d" i;
               kind = `Variable;
               detail = Printf.sprintf "Register %d" i } :: !items
  done;
  !items

let complete db state prefix =
  let upper = String.uppercase_ascii prefix in
  let ulen = String.length upper in
  let hit it =
    let lu = String.uppercase_ascii it.label in
    ulen = 0 || (String.length lu >= ulen && String.sub lu 0 ulen = upper)
  in
  let all =
    instr_items @ macro_items db @ bare_regs ()
    @ (match state with
       | Some (st : Analysis.dstat) ->
         reg_items st.regs @ label_items st.labels
       | None -> [])
  in
  List.filter hit all
