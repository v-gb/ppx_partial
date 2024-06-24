% ppx_partial

# What it does

ppx_partial is a preprocessor that makes it possible to do partial applications
on any parameter of a function, not necessarily the last unlabelled one:

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

In the general case , the ppx ensures that all parameters are executed exactly
once, just like with a regular partial application. For instance, these two
expressions have the exact same performance :

```ocaml
List.filter l ~f:(Re.execp (Re.compile re) __)
List.filter l ~f:(Re.execp (Re.compile re))
```

As a slight generalization, field accesses and sum constructors are allowed: 
`List.map __.field`, `List.map (Some __)`.

As an other slight generalization, it is possible to omit the function instead of an
argument: `Option.iter o ~f:(__ ())` which means `Option.iter o ~f:(fun f -> f ())`.

# What it doesn't do

This is *not* a general lighter syntax for short anonymous functions.  If you
want a lightweight syntax for `(fun x -> f (g x))` or `(fun x -> x * 2 + 1)`,
this ppx isn't providing such things.

# Why

The purpose is simply convenience. To be more specific :

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

- This allows easily dropping optional parameters. For instance, in:

    ```ocaml
      Markup.string src
      |> (match flavor with
          | `Xml -> Markup.parse_xml __
          | `Html -> Markup.parse_html __)
      |> Markup.signals
      |> transform
      |> (match flavor with
          | `Xml -> Markup.write_xml __
          | `Html -> Markup.write_html __)
      |> Markup.to_string
    ```

    `Markup.parse_{xml,html}` have different optional parameters, and thus 
    
    ```ocaml
      match flavor with
      | `Xml -> Markup.parse_xml
      | `Html -> Markup.parse_html
    ```

    would be ill-typed. Same thing with `Markup.write_{xml,html}`.
