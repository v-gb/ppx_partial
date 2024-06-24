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
  (M.f __ (A (Random.bool ()))) ()
;;

(* an alias for |> that doesn't get rewritten by ppx_pipebang *)
external ( >> ) : 'a -> ('a -> 'b) -> 'b = "%revapply"

let%test_unit "interaction with pipelines" =
  let test_eq_int =
    (* uninline this so the generated code is easier to look at *)
    [%test_eq: int]
  in
  test_eq_int (1 >> (__ + Fn.id 2)) 3;
  test_eq_int (1 >> (__ + 2)) 3;
  (* ppx_pipebang *)
  test_eq_int (1 |> (__ + Fn.id 2)) 3;
  test_eq_int (1 |> (__ + 2)) 3
;;

let%test_unit "__" =
  let _ = List.map [] ~f:__.contents in
  let _ = List.map [] ~f:(Some __) in
  let _ = List.map [] ~f:(`First __) in
  ()
