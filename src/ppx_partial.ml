open Ppxlib
open Ast_builder.Default

let partial_evar ~loc n = evar ~loc ("_partial" ^ string_of_int (n + 1))
let partial_pvar ~loc n = pvar ~loc ("_partial" ^ string_of_int (n + 1))

let bind expr f =
  match expr.pexp_desc with
  | Pexp_ident _ -> f expr
  | _ ->
     pexp_let ~loc:expr.pexp_loc
       Nonrecursive
       [ value_binding
            ~loc:expr.pexp_loc
            ~pat:(pvar ~loc:expr.pexp_loc "_partial_fun")
            ~expr:expr
       ]
       (f (evar ~loc:expr.pexp_loc "_partial_fun"))

let willing_to_reexecute e =
  (* Things that incur no side effects, and no allocations (to avoid transforming one
     allocation into arbitrarily many, so no pexp_function or pexp_tuple of trivial things
     for instance).  We must accept __, otherwise this will never fire. *)
  match e with
  | { pexp_desc = (Pexp_ident _ | Pexp_constant _ | Pexp_construct (_, None)); _ } -> true
  | _ -> false

let () =
  Driver.register_transformation
    ~preprocess_impl:(fun str ->
      (* We need preprocess_impl rather than impl so we run before ppx_pipebang, as
         ppx_pipebang changes the arity of functions. ppxlib has this silly restriction
         where only one ppx can run before the context-free ppxes, so this may make us
         incompatible with other ppxes. *)
      object 
        inherit Ppxlib_traverse_builtins.map
        inherit map as super
        method! expression e =
          let e = super#expression e in
          match e with
          | { pexp_desc = Pexp_field ([%expr __] as placeholder, fieldname); _ } ->
             let e' =
               let loc = placeholder.pexp_loc in
               { e with pexp_desc = Pexp_field ([%expr x], fieldname) }
             in
             let loc = e.pexp_loc in
             [%expr fun x -> [%e e']]
          | { pexp_desc = Pexp_construct (constructor, Some ([%expr __] as placeholder)); _ } ->
             let e' =
               let loc = placeholder.pexp_loc in
               { e with pexp_desc = Pexp_construct (constructor, Some [%expr x]) }
             in
             let loc = e.pexp_loc in
             [%expr fun x -> [%e e']]
          | { pexp_desc = Pexp_variant (constructor, Some ([%expr __] as placeholder)); _ } ->
             let e' =
               let loc = placeholder.pexp_loc in
               { e with pexp_desc = Pexp_variant (constructor, Some [%expr x]) }
             in
             let loc = e.pexp_loc in
             [%expr fun x -> [%e e']]
          | { pexp_desc = Pexp_apply (f, params); _ } ->
             let count =
               List.fold_left (fun acc (_, e) ->
                   match e with
                   | [%expr __] -> acc + 1
                   | _ -> acc) 0 params
             in
             if count = 0
             then e
             else
               if count > 1
               then
                 let params =
                   List.map (fun (arg, e) ->
                       arg,
                       match e with
                       | [%expr __] ->
                          pexp_extension
                            ~loc:e.pexp_loc
                            (Location.error_extensionf ~loc:e.pexp_loc
                               "ppx_partial: only one __ argument is supported per function call")
                       | e -> e
                     ) params
                 in
                 { e with pexp_desc = Pexp_apply (f, params) }
               else
                 if willing_to_reexecute f
                 && List.for_all (fun (_, e) -> willing_to_reexecute e) params
                 then
                   (* generate cleaner code for trivial things like ~f:(__ + 1), to
                      guarantee good perf even if the compiler wouldn't optimize away
                      our local function, as is presumably the case in the bytecode ->
                      js_of_ocaml pipeline *)
                   let args =
                     List.map (fun (arg, e) ->
                         match e with
                         | [%expr __] -> (arg, partial_evar ~loc:e.pexp_loc 1)
                         | _ -> (arg, e)) params
                   in
                   eabstract ~loc:e.pexp_loc [partial_pvar ~loc:e.pexp_loc 1]
                     (pexp_apply ~loc:e.pexp_loc f args)
                 else
                   bind f (fun f ->
                       let fun_ =
                         let args =
                           List.mapi (fun i (arg, e) ->
                               arg, partial_evar ~loc:e.pexp_loc i
                             ) params in
                         let params =
                           let last_param = ref None in
                           let first_params =
                             let i = ref (-1) in
                             List.filter_map (fun (_arg, e) ->
                                 i := !i + 1;
                                 let param = partial_pvar ~loc:e.pexp_loc !i in
                                 match e with
                                 | [%expr __] -> last_param := Some param; None
                                 | _ -> Some param
                               ) params
                           in
                           first_params
                           @ (match !last_param with
                              | None -> assert false
                              | Some p -> [p])
                         in
                         eabstract ~loc:e.pexp_loc
                           params
                           (pexp_apply ~loc:e.pexp_loc f args)
                       in
                       let new_fun_call =
                         let remaining_params =
                           List.filter_map (function
                               | (_, [%expr __]) -> None
                               | (_, e) -> Some e) params
                         in
                         eapply ~loc:e.pexp_loc
                           (evar ~loc:e.pexp_loc "_partial_tmpfun")
                           remaining_params
                       in
                       let loc = e.pexp_loc in
                       [%expr
                        let _partial_tmpfun = [%e fun_] in
                            [%e new_fun_call]])
          | _ -> e
       end#structure str
    )
    "ppx_partial"
