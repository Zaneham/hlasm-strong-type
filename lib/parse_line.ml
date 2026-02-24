let split_operands str =
  let len = String.length str in
  if len = 0 then []
  else begin
    let result = ref [] in
    let start = ref 0 in
    let depth = ref 0 in
    let inquote = ref false in
    for i = 0 to len - 1 do
      match str.[i] with
      | '(' when not !inquote -> incr depth
      | ')' when not !inquote -> if !depth > 0 then decr depth
      | '\'' -> inquote := not !inquote
      | ',' when !depth = 0 && not !inquote ->
        result := String.sub str !start (i - !start) :: !result;
        start := i + 1
      | _ -> ()
    done;
    if !start < len then
      result := String.sub str !start (len - !start) :: !result;
    List.rev !result
  end

let tokenize str =
  let lexbuf = Lexing.from_string str in
  let tokens = ref [] in
  let stop = ref false in
  let guard = ref 0 in
  while not !stop && !guard < 200 do
    incr guard;
    match Lexer.operand_token lexbuf with
    | exception _ -> stop := true
    | tok ->
      if tok = Types.EOF then stop := true
      else tokens := tok :: !tokens
  done;
  List.rev !tokens

let parse_single raw_str =
  let s = String.trim raw_str in
  let len = String.length s in
  if len = 0 then Types.Raw ""
  else
    let tokens = tokenize s in
    match tokens with
    | [Types.IDENT name] ->
      if len >= 2 && (s.[0] = 'R' || s.[0] = 'r') then
        match int_of_string_opt (String.sub s 1 (len - 1)) with
        | Some n when n >= 0 && n <= 15 -> Types.Reg n
        | _ -> Types.Sym name
      else
        Types.Sym name
    | [Types.NUMBER n] -> Types.Imm n
    | [Types.STRING s] -> Types.Str s
    | [Types.IDENT d; Types.LPAREN; Types.IDENT b; Types.RPAREN] ->
      Types.Addr { disp = Types.Sym d; base = Types.Sym b; index = None }
    | [Types.NUMBER d; Types.LPAREN; Types.IDENT b; Types.RPAREN] ->
      Types.Addr { disp = Types.Imm d; base = Types.Sym b; index = None }
    | [Types.IDENT d; Types.LPAREN; Types.IDENT x; Types.COMMA;
       Types.IDENT b; Types.RPAREN] ->
      Types.Addr { disp = Types.Sym d; index = Some (Types.Sym x);
                   base = Types.Sym b }
    | [Types.NUMBER d; Types.LPAREN; Types.IDENT x; Types.COMMA;
       Types.IDENT b; Types.RPAREN] ->
      Types.Addr { disp = Types.Imm d; index = Some (Types.Sym x);
                   base = Types.Sym b }
    | [Types.NUMBER d; Types.LPAREN; Types.COMMA;
       Types.IDENT b; Types.RPAREN] ->
      Types.Addr { disp = Types.Imm d; index = None; base = Types.Sym b }
    | _ -> Types.Raw s

let parse_operands str =
  let parts = split_operands str in
  List.map parse_single parts

let parse ~line_num raw =
  let len = String.length raw in
  if len = 0 then None
  else
    let text = if len > 71 then String.sub raw 0 71 else raw in
    let tlen = String.length text in
    if tlen = 0 then None
    else if text.[0] = '*' then
      Some { Types.line = line_num; label = None; op = "*";
             operands = []; comment = Some text; raw }
    else begin
      let pos = ref 0 in
      let label =
        if text.[0] <> ' ' then begin
          while !pos < tlen && text.[!pos] <> ' ' do incr pos done;
          Some (String.sub text 0 !pos)
        end else
          None
      in
      while !pos < tlen && text.[!pos] = ' ' do incr pos done;
      if !pos >= tlen then
        Some { Types.line = line_num; label; op = ""; operands = [];
               comment = None; raw }
      else begin
        let op_start = !pos in
        while !pos < tlen && text.[!pos] <> ' ' do incr pos done;
        let op = String.uppercase_ascii
                   (String.sub text op_start (!pos - op_start)) in
        while !pos < tlen && text.[!pos] = ' ' do incr pos done;
        if !pos >= tlen then
          Some { Types.line = line_num; label; op; operands = [];
                 comment = None; raw }
        else begin
          let ops_start = !pos in
          let depth = ref 0 in
          let inquote = ref false in
          while !pos < tlen &&
                (text.[!pos] <> ' ' || !depth > 0 || !inquote) do
            (match text.[!pos] with
             | '(' when not !inquote -> incr depth
             | ')' when not !inquote ->
               if !depth > 0 then decr depth
             | '\'' -> inquote := not !inquote
             | _ -> ());
            incr pos
          done;
          let ops_str = String.sub text ops_start (!pos - ops_start) in
          let operands = parse_operands ops_str in
          while !pos < tlen && text.[!pos] = ' ' do incr pos done;
          let comment =
            if !pos < tlen then
              Some (String.sub text !pos (tlen - !pos))
            else None
          in
          Some { Types.line = line_num; label; op; operands; comment; raw }
        end
      end
    end

let parse_document text =
  let lines = String.split_on_char '\n' text in
  let stmts = ref [] in
  let line_num = ref 0 in
  List.iter (fun line ->
    let raw =
      let n = String.length line in
      if n > 0 && line.[n - 1] = '\r' then String.sub line 0 (n - 1)
      else line
    in
    (match parse ~line_num:!line_num raw with
     | Some stmt -> stmts := stmt :: !stmts
     | None -> ());
    incr line_num
  ) lines;
  Array.of_list (List.rev !stmts)
