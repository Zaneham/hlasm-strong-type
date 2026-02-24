type reg_type = General | Address | Float | Control

type register = {
  name : string;
  number : int;
  rtype : reg_type;
}

type token =
  | IDENT of string
  | NUMBER of int
  | STRING of string
  | COMMA
  | LPAREN
  | RPAREN
  | PLUS
  | MINUS
  | STAR
  | EQ
  | EOF

type operand =
  | Reg of int
  | Sym of string
  | Imm of int
  | Addr of { disp : operand; base : operand; index : operand option }
  | Str of string
  | Raw of string

type statement = {
  line : int;
  label : string option;
  op : string;
  operands : operand list;
  comment : string option;
  raw : string;
}
