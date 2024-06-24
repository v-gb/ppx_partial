open Base

let%test_unit "no duplication of side-effects" =
  let r = ref [] in
  let l =
    Stdlib.List.map
      ((r := "a" :: !r; (fun x y z -> x, y, z))
         (r := "b" :: !r; 1)
         __
         (r := "c" :: !r; 2))
      [ 1.; 2. ]
  in
  [%test_eq: (int * float * int) list] l [ 1, 1., 2; 1, 2., 2 ];
  [%test_eq: string list] (List.sort !r ~compare:String.compare) [ "a"; "b"; "c" ]

let%test_unit "type-directed disambiguation" =
  let module M = struct
      type t = A of bool
      let f () (A _) = ()
    end
  in
  let module R = struct
      type t = { r : int }
    end
  in
  (* from function to parameter *)
  (M.f __ (A (Random.bool ()))) ();
  (* from function + earlier parameter to later parameter *)
  ignore (List.map [M.A true] ~f:(Stdlib.(=) __ (A false)));
  ignore (List.map [{ R.r = 1 }] ~f:(__.r));
;;

(* an alias for |> that doesn't get rewritten by ppx_pipebang *)
external ( >> ) : 'a -> ('a -> 'b) -> 'b = "%revapply"

let%test_unit "interaction with pipelines" =
  let module M = struct
      type t = A of bool
    end
  in
  let test_eq_int =
    (* uninline this so the generated code is easier to look at *)
    [%test_eq: int]
  in
  test_eq_int (1 >> (__ + Fn.id 2)) 3;
  test_eq_int (1 >> (__ + 2)) 3;
  (* the List.map example below doesn't work without ppx_pipebang, even without __ *)
  (* ppx_pipebang *)
  test_eq_int (1 |> (__ + Fn.id 2)) 3;
  test_eq_int (1 |> (__ + 2)) 3;
  ignore ([M.A true] |> List.map ~f:(Stdlib.(=) __ (A false)));
;;

let%test_unit "__" =
  let _ = List.map [] ~f:__.contents in
  let _ = List.map [] ~f:(Some __) in
  let _ = List.map [] ~f:(`First __) in
  ()


let f x y z = (x, y, z)
let xxxxx_checkcmm r =
  (* compiled by closure as
     List.map
       (let partial3 = side-effect; 3 in
        let partial1 = side-effectl 1 in
        static_closure)
       static_list
     where
     let static_closure partial2 = (1, partial2, 3)
  *)
  Stdlib.List.map
    (f (r := "b" :: !r; 1) __ (r := "c" :: !r; 2))
    [ 1.; 2. ]

let yyyyy_checkcmm f r =
  (* compiled by closure as
     List.map
       (let partial3 = side-effect; 3 in
        let partial1 = side-effectl 1 in
        alloc-closure codepointer f 1 3)
       static_list
     where
     let codepointer partial2 env = caml_apply3 1 partial2 3 env.f

     which seems fine (no need to close over partial1 partial3 if they are static,
     but that would also happen with hand written code). That indicates closure does
     eliminate all our static ifs without leaving things behind.
  *)
  Stdlib.List.map
    (f (r := "b" :: !r; 1) __ (r := "c" :: !r; 2))
    [ 1.; 2. ]
