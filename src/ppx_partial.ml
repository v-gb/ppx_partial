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
     allocation into arbitrarily many, so no pexp_function or pexp_tuple of trivial
     things for instance).  We must accept __, otherwise this will never fire. *)
  match e with
  | { pexp_desc = (Pexp_ident _ | Pexp_constant _ | Pexp_construct (_, None)); _ } -> true
  | _ -> false

let beta_redex ~loc params body exprs =
    eapply ~loc (eabstract ~loc params body) exprs

let with_inferred_type_of_arg ~loc (first_params, last_param) body first_args =
  (* If we're compiling [f e1 __ e3], we want type directed disambiguation to be
     preserved, meaning to work the same as in [fun x -> f e1 x e2].

     If we create the naive [let v1 = e1 and v3 = e3 in fun v2 -> f v1 v2 v3], then
     [e1] and [e3] have no expected types, hence no type-directed disambiguation.

     One reasonably simple improvement is to replace the let-binding by the OG
     let-binding, meaning a beta-redex : [(fun v1 v3 v2 -> f v1 v2 v3) e1 e3] (note the
     order of parameters). With this, [e1] and [e3] are typed according to what f
     expects, but [e3] is still not typed according to what the context expects v2 to
     be (in things like [List.map l ~f:..], provided List.map is defined nicely like
     Base does but unlike what the Stdlib does, the type of the elements of l flows
     into ~f's argument, and this is very useful).

     So the next and last trick is to generate [(fun v1 v3 (v2 : 'v2) -> f v1 v2 v3) e1
     e3 : 'v2 -> _], so the expected type of the resulting function flows into v2,
     which flows into v3, which then flows into [e3]. That solution doesn't concretely
     work, because adding an annotation (_ : 'fresh) around expressions can cause type
     errors. So instead we use dead code that encodes the same flow of type inference. *)
  if false (* Maybe we should make this simpler version available as a flag *)
  then
    beta_redex ~loc first_params
      [%expr (); fun [%p last_param] -> [%e body]]
      first_args
  else
    [%expr
     let _partial_arg_type = (* ('v2 -> unit) option, for a fresh non generalized 'v2.
                                We want contravariant in 'v2 so the variable is non
                                generalized, but we want to avoid function values, as
                                the closure middle end doesn't do a good job at
                                eliminating unused ones (even ignore doesn't work). *)
       if true then
         (None : (_ -> unit) option) else Stdlib.(!) (Stdlib.ref (assert false))
     in
     if false
     then
       (* unify 'v2 with the expected type of v2 *)
       (fun x -> (match _partial_arg_type with None -> () | Some f -> f x); assert false)
     else [%e beta_redex ~loc first_params
                [%expr
                    if false
                    then fun x -> (match _partial_arg_type with
                                   | None -> ()
                                   | Some f -> f x); assert false
                    else fun [%p last_param] -> [%e body]]
                first_args]
    ]

let rewrite ~loc f params =
  (* If we have to process [f e1 __ e2] *)
  if willing_to_reexecute f
     && List.for_all (fun (_, e) -> willing_to_reexecute e) params
  then
    (* generate cleaner code [fun x -> f e1 x e2] for trivial things like ~f:(__ + 1),
       to guarantee good perf even if the compiler wouldn't optimize away our local
       function, as is presumably the case in the bytecode -> js_of_ocaml pipeline. *)
    let replace_placeholder e =
      match e with
      | [%expr __] -> partial_evar ~loc:e.pexp_loc 1
      | _ -> e
    in
    let args = List.map (fun (arg, e) -> (arg, replace_placeholder e)) params in
    eabstract ~loc [partial_pvar ~loc 1]
      (pexp_apply ~loc (replace_placeholder f) args)
  else
    (* Otherwise, generate [(fun p1 p3 p2 -> f p1 p2 p3) e1 e2] (roughly, see
       with_inferred_type_of_arg for the gory details). *)
    bind f (fun f ->
        let remaining_params =
          List.filter_map (function
              | (_, [%expr __]) -> None
              | (_, e) -> Some e) params
        in
        let body =
          pexp_apply ~loc
            (match f with
             | [%expr __] -> partial_evar ~loc:f.pexp_loc (-1)
             | _ -> f)
            (List.mapi (fun i (arg, e) ->
                 arg, partial_evar ~loc:e.pexp_loc i
               ) params)
        in
        let first_params, last_param =
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
          let last_param =
            match !last_param with
            | None -> partial_pvar ~loc:f.pexp_loc (-1)
            | Some p -> p
          in
          first_params, last_param
        in
        with_inferred_type_of_arg
          ~loc
          (first_params, last_param)
          body
          remaining_params)

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
                   | _ -> acc)
                 (match f with
                  | [%expr __] -> 1
                  | _ -> 0)
                 params
             in
             if count = 0
             then e
             else
               if count > 1
               then
                 let replace_placeholder e =
                   match e with
                   | [%expr __] ->
                      pexp_extension
                        ~loc:e.pexp_loc
                        (Location.error_extensionf ~loc:e.pexp_loc
                           "ppx_partial: only one __ argument is supported per function call")
                   | e -> e
                 in
                 let f = replace_placeholder f in
                 let params = List.map (fun (arg, e) -> arg, replace_placeholder e) params in
                 { e with pexp_desc = Pexp_apply (f, params) }
               else rewrite ~loc:e.pexp_loc f params
          | _ -> e
       end#structure str
    )
    "ppx_partial"
