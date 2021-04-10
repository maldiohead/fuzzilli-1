module String_Set = Set.Make(struct type t = string let compare = compare end)

type varUseData = 
    {
        declares: String_Set.t;
        cond_declars: String_Set.t;
        uses: String_Set.t;
        toHoist: String_Set.t;
    }

let empty_use_data = 
    {
        declares = String_Set.empty;
        cond_declars = String_Set.empty;
        uses = String_Set.empty;
        toHoist = String_Set.empty;
    } 

let build_declare_data dec = 
    {
        declares = String_Set.singleton dec;
        cond_declars = String_Set.empty;
        uses = String_Set.empty;
        toHoist = String_Set.empty;
    }

let build_conditional_declare_data condDecl = 
    {
        declares = String_Set.empty;
        cond_declars = String_Set.singleton condDecl;
        uses = String_Set.empty;
        toHoist = String_Set.empty;
    }

let build_use_data use = 
    {
        declares = String_Set.empty;
        cond_declars = String_Set.empty;
        uses = String_Set.singleton use;
        toHoist = String_Set.empty;
    }

let combine_use_data_nohoist (a: varUseData) (b: varUseData) =
    let declares_union = String_Set.union a.declares b.declares in
    let cond_declars_union = String_Set.union a.cond_declars b.cond_declars in
    {
        declares = declares_union;
        cond_declars = String_Set.diff cond_declars_union declares_union;
        uses = String_Set.union a.uses b.uses;
        toHoist = String_Set.union a.toHoist b.toHoist;
    }

let combine_use_data_hoist (a: varUseData) (b: varUseData) =
    let declares_union = String_Set.union a.declares b.declares in
    let cond_declars_union = String_Set.union a.cond_declars b.cond_declars in
    let new_hoist = String_Set.inter a.cond_declars b.uses in
    {
        declares = declares_union;
        cond_declars = String_Set.diff cond_declars_union declares_union;
        uses = String_Set.union a.uses b.uses;
        toHoist = String_Set.union a.toHoist b.toHoist |> String_Set.union new_hoist;
    }


let rec combine_use_data_list_nohoist (l: varUseData list) = 
    match l with
        [] -> empty_use_data
        | [hd] -> hd
        | hd :: tl ->
            combine_use_data_nohoist hd (combine_use_data_list_nohoist tl)

let rec combine_use_data_list_hoist (l: varUseData list) = 
    match l with
        [] -> empty_use_data
        | [hd] -> hd
        | hd :: tl ->
            combine_use_data_hoist hd (combine_use_data_list_hoist tl)

let leave_conditional_data data =
    {
        declares = String_Set.empty;
        cond_declars = String_Set.union data.declares data.cond_declars;
        uses = data.uses;
        toHoist = data.toHoist;
    }

let rec get_expression_useData_array (exp: ('M, 'T) Flow_ast.Expression.Array.t) =
    let data = List.map get_expression_useData_array_elem exp.elements in
    combine_use_data_list_nohoist data

and get_expression_useData_array_elem (elem: ('M, 'T) Flow_ast.Expression.Array.element) =
    match elem with
        Expression e -> get_expression_useData e
        | Spread spread -> 
            let _, unwrapped = spread in
            get_expression_useData unwrapped.argument
        | Hole h ->
            empty_use_data

and get_expression_useData_arg_list (arg_list: ('M, 'T) Flow_ast.Expression.ArgList.t) =
    let _, unwrapped = arg_list in
    let arguments = unwrapped.arguments in
    let proc_exp_or_spread (exp_or_spread: ('M, 'T) Flow_ast.Expression.expression_or_spread) = 
        match exp_or_spread with
            Expression exp -> 
                get_expression_useData exp
            | Spread spread -> 
                empty_use_data
        in
    List.map proc_exp_or_spread arguments |> combine_use_data_list_nohoist

and get_expression_useData_assignment (assign_exp: (Loc.t, Loc.t) Flow_ast.Expression.Assignment.t) =
    match assign_exp.left with
        (_ , (Flow_ast.Pattern.Identifier id)) -> 
            let (_, act_name)  = id.name in
            let left = build_declare_data act_name.name in
            let right = get_expression_useData assign_exp.right in
            combine_use_data_nohoist left right
        | (_, (Flow_ast.Pattern.Expression (_, exp))) -> 
            (match exp with
                Flow_ast.Expression.Member mem -> 
                    let obj_data = get_expression_useData mem._object in
                    let right_data = get_expression_useData assign_exp.right in
                    (match mem.property with
                        Flow_ast.Expression.Member.PropertyExpression pex -> 
                            combine_use_data_list_nohoist (obj_data :: get_expression_useData pex :: [right_data])
                        |  Flow_ast.Expression.Member.PropertyIdentifier pid -> 
                            let (_, unwapped_id) = pid in
                            let idData = build_declare_data unwapped_id.name in
                            combine_use_data_list_nohoist (obj_data :: [idData; right_data])
                        | _ -> raise (Invalid_argument "Unhandled member property in exp assignment"))
                | _ -> raise (Invalid_argument "Unhandled assignment expression left member"))
        | _ -> raise (Invalid_argument "Unhandled assignment expressesion left ")

and get_expression_useData_call (call_exp: ('M, 'T) Flow_ast.Expression.Call.t) =
    let (_, callee) = call_exp.callee in
    let arg_data = get_expression_useData_arg_list call_exp.arguments in
    match callee with
        (* Handle the method call case explicity*)
        Flow_ast.Expression.Member member -> 
            (match member.property with
                (* Handle method calls seperately for all other cases *)
                Flow_ast.Expression.Member.PropertyIdentifier (_, id) -> 
                    let sub_exp_data = get_expression_useData member._object in
                    let method_data = build_use_data id.name in
                    combine_use_data_list_nohoist (sub_exp_data :: arg_data :: [method_data])
                | _ ->
                    let callee_data = get_expression_useData call_exp.callee in
                    combine_use_data_nohoist callee_data arg_data)
        (* Otherwise, run the callee sub expression as normal*)
        | _ ->  let callee_data = get_expression_useData call_exp.callee in
                combine_use_data_nohoist callee_data arg_data

(* Note: This is a conditional expression, not an if statement *)
and get_expression_useData_conditional (cond_exp: (Loc.t, Loc.t) Flow_ast.Expression.Conditional.t) =
    let test_data = get_expression_useData cond_exp.test in
    let consequent_data = get_expression_useData cond_exp.consequent in
    let alternative_data =get_expression_useData cond_exp.alternate in
    combine_use_data_list_nohoist (test_data :: consequent_data :: [alternative_data])

and get_expression_useData_new (new_exp: ('M, 'T) Flow_ast.Expression.New.t) =
    let callee_data = get_expression_useData new_exp.callee in
    let arguments = new_exp.arguments in  
    let arg_data = match arguments with
        None -> empty_use_data
        | Some act_args -> 
            get_expression_useData_arg_list act_args 
        in
    combine_use_data_nohoist callee_data arg_data

and get_expression_useData (exp: ('M, 'T) Flow_ast.Expression.t) = 
    let (_, unwrapped_exp) = exp in
    match unwrapped_exp with
        (Flow_ast.Expression.ArrowFunction arrow_func) ->
            empty_use_data
        | (Flow_ast.Expression.Array array_op) ->
            get_expression_useData_array array_op
        | (Flow_ast.Expression.Assignment assign_op) ->
            get_expression_useData_assignment assign_op
        | (Flow_ast.Expression.Binary bin_op) ->
            combine_use_data_nohoist (get_expression_useData bin_op.left) (get_expression_useData bin_op.right)
        | (Flow_ast.Expression.Call call_op) ->
            get_expression_useData_call call_op
        | (Flow_ast.Expression.Conditional cond_exp) ->
            get_expression_useData_conditional cond_exp
        | (Flow_ast.Expression.Function func_exp) ->
            (match func_exp.id with 
                None -> empty_use_data
                | Some (_, id) ->
                    build_declare_data id.name)
        | (Flow_ast.Expression.Identifier id_val) ->
            let (_, unwraped_id_val) = id_val in
            build_use_data unwraped_id_val.name
        | (Flow_ast.Expression.Import _) -> 
            empty_use_data
        | (Flow_ast.Expression.Literal lit_val) -> 
            empty_use_data
        | (Flow_ast.Expression.Logical log_op) ->
            combine_use_data_nohoist (get_expression_useData log_op.left) (get_expression_useData log_op.right)
        (* | (Flow_ast.Expression.Member memb_exp) ->
            proc_exp_member memb_exp *)
        | (Flow_ast.Expression.New new_exp) ->
            get_expression_useData_new new_exp
        (* | (Flow_ast.Expression.Object create_obj_op) ->
            proc_create_object create_obj_op *)
        | (Flow_ast.Expression.This this_exp) ->
            empty_use_data
        | (Flow_ast.Expression.Unary u_val) ->
            get_expression_useData u_val.argument
        | (Flow_ast.Expression.Update update_exp) ->
            get_expression_useData update_exp.argument 
        | (Flow_ast.Expression.Yield yield_exp) ->
            (match yield_exp.argument with
                Some x -> get_expression_useData x
                | None -> empty_use_data)
        | x -> raise (Invalid_argument ("Unhandled expression type in variable hoisting " ^ (Util.trim_flow_ast_string (Util.print_expression exp))))       

and get_statement_useData_for (for_state: (Loc.t, Loc.t) Flow_ast.Statement.For.t) =
    let init_data = match for_state.init with
        None -> empty_use_data
        | Some (InitDeclaration (_, decl)) -> get_statement_vardecl_useData decl
        | Some (InitExpression exp) -> get_expression_useData exp
        in
    let test_data = match for_state.test with
        None -> empty_use_data
        | Some exp -> get_expression_useData exp 
        in
    let body_data = get_statement_useData for_state.body |> leave_conditional_data in
    let update_data = match for_state.update with
        None -> empty_use_data
        | Some exp -> get_expression_useData exp
        in
    combine_use_data_list_nohoist [init_data; test_data; body_data; update_data]

and get_statement_useData_if (if_statement: (Loc.t, Loc.t) Flow_ast.Statement.If.t) =
    let test_data = get_expression_useData if_statement.test in
    let consequent_statement_data = get_statement_useData if_statement.consequent in
    let fin_statement_data = match if_statement.alternate with
        None -> empty_use_data
        | Some (_, alt) ->
            get_statement_useData alt.body
        in
    let conditional_data = combine_use_data_nohoist consequent_statement_data fin_statement_data |> leave_conditional_data in
    combine_use_data_nohoist test_data conditional_data

and get_statement_vardecl_useDat_rec (decs : (Loc.t, Loc.t) Flow_ast.Statement.VariableDeclaration.Declarator.t list) (kind: Flow_ast.Statement.VariableDeclaration.kind) =
    match decs with
        [] -> empty_use_data
        | (_, declarator) :: tl -> 
            let var_identifier = match declarator.id with
                (_, (Flow_ast.Pattern.Identifier x)) -> x.name
                | _ -> raise (Invalid_argument "Left side of var decl isn't an identifier") in
            let (_, act_name) = var_identifier in
            let var_name = act_name.name in
            let init = declarator.init in 
            let initalization_data = match init with 
                None -> empty_use_data
                | Some exp -> get_expression_useData exp in
            let new_data = build_declare_data var_name in
            combine_use_data_nohoist initalization_data new_data |> combine_use_data_nohoist (get_statement_vardecl_useDat_rec tl kind)

and get_statement_vardecl_useData (var_decl: (Loc.t, Loc.t) Flow_ast.Statement.VariableDeclaration.t) =
    let decs = var_decl.declarations in
    let kind = var_decl.kind in
    get_statement_vardecl_useDat_rec decs kind

and get_statement_useData_return (ret_state: (Loc.t, Loc.t) Flow_ast.Statement.Return.t) =
    match ret_state.argument with
        None -> empty_use_data
        | Some exp -> get_expression_useData exp

and get_statement_useData (statement: (Loc.t, Loc.t) Flow_ast.Statement.t) = 
    match statement with 
        (_, Flow_ast.Statement.Block state_block) -> get_statement_list_use_data state_block.body
        | (_, Flow_ast.Statement.Break _) -> empty_use_data
        | (_, Flow_ast.Statement.Continue state_continue) -> empty_use_data
        (* | (_, Flow_ast.Statement.DoWhile state_do_while) -> proc_do_while state_do_while *)
        | (_, Flow_ast.Statement.Empty _) -> empty_use_data
        | (_, Flow_ast.Statement.Expression state_exp) -> get_expression_useData state_exp.expression
        | (_, Flow_ast.Statement.For state_for) -> get_statement_useData_for state_for
        (* | (_, Flow_ast.Statement.ForIn state_foin) -> proc_for_in state_foin *)
        (* | (_, Flow_ast.Statement.ForOf state_forof) -> proc_for_of state_forof  *)
        | (_, Flow_ast.Statement.FunctionDeclaration func_def) -> 
            (match func_def.id with 
                None -> empty_use_data
                | Some (_, id) ->
                    build_declare_data id.name)
        | (_, Flow_ast.Statement.If state_if) -> get_statement_useData_if state_if
        | (_, Flow_ast.Statement.ImportDeclaration _) -> empty_use_data
        | (_, Flow_ast.Statement.Return state_return) -> get_statement_useData_return state_return
        (* | (_, Flow_ast.Statement.Throw state_throw) -> proc_throw state_throw  *)
        (* | (_, Flow_ast.Statement.Try state_try) -> proc_try state_try  *)
        | (_ , VariableDeclaration decl) -> get_statement_vardecl_useData decl
        (* | (_, Flow_ast.Statement.While state_while) -> proc_while state_while  *)
        (* | (_, Flow_ast.Statement.With state_with) -> proc_with state_with  *)
        | _ as s -> raise (Invalid_argument (Printf.sprintf "Unhandled statement type in var hoisting %s" (Util.trim_flow_ast_string (Util.print_statement s))))

and get_statement_list_use_data (statements: (Loc.t, Loc.t) Flow_ast.Statement.t list) =
    List.map get_statement_useData statements |> combine_use_data_list_hoist

let get_vars_to_hoist (statements: (Loc.t, Loc.t) Flow_ast.Statement.t list) =
    let varData = get_statement_list_use_data statements in
    let res : string list = String_Set.to_seq varData.toHoist |> List.of_seq in
    res