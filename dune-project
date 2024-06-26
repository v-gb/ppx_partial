(lang dune 3.15)

(name ppx_partial)

(generate_opam_files true)
(source (github v-gb/ppx_partial))
(authors "Valentin Gatien-Baron")
(maintainers "Valentin Gatien-Baron")
(license ISC)

(package
 (name ppx_partial)
 (synopsis
  "Syntax for a partial application of functions that omits any single argument")
 (description
  "
This provides a syntax `f e1 __ e3` that means `(fun x -> f e1 x e3)`,
except that `e1` and `e3` are evaluated exactly once. Only one `__` is
supported.

This can be convenient in pipelines or to build arguments for `List.map`
or any places that need single-argument functions.

As a slight generalization, `__.record_field` and `Sum_constructor __`
allow shortening `(fun x -> x.record_field)` and `(fun x -> Sum_constructor x)`.
")
 (depends
  (ppxlib (>= 0.32.1))
  (ocaml (>= 4.14.0))
  dune
  (base :with-test)
  (ppx_pipebang :with-test)
  (ppx_inline_test :with-test)
  (ppx_assert :with-test)
 )
 (tags
  (syntax ppx)))
