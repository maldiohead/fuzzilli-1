open Program_types
open Compiler.ProgramBuilder

let input = 
"const v0 = 0;"

let correct = 
    let builder = init_builder false false false in
    let _, inst = build_load_integer 0L builder in
    let res = [inst] in
    List.map inst_to_prog_inst res

let test () = 
    let (ast, errors) = Compiler.string_to_flow_ast input in
    let prog = Compiler.flow_ast_to_inst_list ast false false true in
    Alcotest.(check (list Util.inst_testable)) "single_constant" correct prog 