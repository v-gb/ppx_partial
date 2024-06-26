# What it does

ppx_partial provides syntax for building single argument functions that look and behave
similar to partial applications:

```ocaml
something_that_returns_a_string ()
|> Base.String.drop_suffix __ 1
|> Stdio.Out_channel.write_all "/tmp/z" ~data:__
```

is turned into:

```ocaml
something_that_returns_a_string ()
|> (fun x -> Base.String.drop_prefix x 1)
|> (fun x -> Stdio.Out_channel.write_all "/tmp/z" ~data:x)
```

In general, the ppx ensures that parameters are executed exactly once, just like with a
regular partial application. For instance, these two expressions have the exact same
performance:

```ocaml
List.filter (Re.execp (Re.compile re) __) l
List.filter (Re.execp (Re.compile re)) l
```

This syntax may appear unnecessary at first, given that that ocaml functions are
curried, but note that neither occurrence of `__` in the first example can be replaced
by a partial application.

As a slight generalization, field accesses and sum constructors are allowed: 
`List.map __.field l`, `List.map (Some __) l`.

As an other slight generalization, it is possible to omit the function instead of an
argument: `Option.iter o ~f:(__ ())` which means `Option.iter o ~f:(fun f -> f ())`.

# What it doesn't do

This is *not* a general lighter syntax for short anonymous functions.  If you
want a lightweight syntax for `(fun x -> f (g x))` or `(fun x -> x * 2 + 1)`,
this ppx isn't providing such things.

Only a single placeholder is supported, so things like `f __ __ e1` are not supported.
There are probably no technical obstacles, but I haven't seen a compelling reason to do
this.

# Why

The purpose is simply convenience. To be more specific:

- `__.field` and `Some __` should be self-explanatory.

- there is a tension between 1) easy pipelining (meaning "main parameter" last) 2) `t`
  parameter first consistently 3) no excessive labelling of parameters: you can't get
  all three consistently.
  
  - `Base.List.take list int` is a function that picks 2) and 3) but drops 1).
  - `Base.Or_error.tag error ~tag` is a function that picks 1) and 2) but drops 3).
  - `Stdlib.Map.add key value map` is a function that picks 1) and 3) but drops 2).
  
  `ppx_partial` provides 1) for every parameter of every function, thus function
  signatures only have to provide 2) and 3).

- partial application of some infix operators can be very misleading.  `List.filter
  ((>) 0)` can easily be read as `List.filter (fun -> x > 0)`, when it actually means
  `List.filter (fun x -> 0 > x)`. Writing `List.filter (__ > 0)` is clearer.

- Very occasionaly, this can be used to drop optional parameters by "eta-expansion",
  like so:
    ```ocaml
       match flavor with
       | `Xml -> Markup.parse_xml __ (* wouldn't type without __, due to optional parameters *)
       | `Html -> Markup.parse_html __
    ```
  or it can be used to omit a parameter that's not the usual one, say `List.iter __ l` or
  `List.iter ~f:__ l`.
