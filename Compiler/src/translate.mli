(* Converts a Flow AST program to a program taken as input for protobuf generation*)
val flow_ast_to_inst_list : (Loc.t, Loc.t) Flow_ast.Program.t -> bool -> bool -> Program_types.instruction list