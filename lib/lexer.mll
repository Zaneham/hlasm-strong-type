{
  open Types
}

let ident_start = ['A'-'Z' 'a'-'z' '@' '#' '$' '_']
let ident_char  = ['A'-'Z' 'a'-'z' '0'-'9' '@' '#' '$' '_']
let digit        = ['0'-'9']
let hex          = ['0'-'9' 'A'-'F' 'a'-'f']

rule operand_token = parse
  | [' ' '\t']+                                  { operand_token lexbuf }
  | ['C' 'c'] '\'' ([^ '\'']* as s) '\''        { STRING s }
  | ['X' 'x'] '\'' (hex+ as s) '\''             { NUMBER (int_of_string ("0x" ^ s)) }
  | ['B' 'b'] '\'' (['0' '1']+ as s) '\''       { NUMBER (int_of_string ("0b" ^ s)) }
  | (ident_start ident_char*) as s               { IDENT (String.uppercase_ascii s) }
  | digit+ as n                                  { NUMBER (int_of_string n) }
  | '\'' ([^ '\'']* as s) '\''                   { STRING s }
  | ','                                          { COMMA }
  | '('                                          { LPAREN }
  | ')'                                          { RPAREN }
  | '+'                                          { PLUS }
  | '-'                                          { MINUS }
  | '*'                                          { STAR }
  | '='                                          { EQ }
  | eof                                          { EOF }
  | _                                            { operand_token lexbuf }
