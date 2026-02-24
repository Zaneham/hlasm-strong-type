type dstat = {
  stmts : Types.statement array;
  regs : (string, Types.register) Hashtbl.t;
  labels : (string, int) Hashtbl.t;
  diags : Diagnostics.diag list;
}

let analyse stmts =
  let regs = Register.scan_equregs stmts in
  let labels = Register.scan_labels stmts in
  let diags = Diagnostics.run regs stmts in
  { stmts; regs; labels; diags }
