% ppx_partial

# What it does

ppx_partial is a preprocessor that makes it possible to do partial applications
regardless of the order of parameters of a function, and whether they are
labelled:

```ocaml
whatever () (* returns a string *)
|> Base.String.drop_prefix __ 1
|> Base.Out_channel.save "/tmp/z" ~data:__
```

becomes :

```ocaml
whatever () (* returns a string *)
|> (fun x -> Base.String.drop_prefix x 1)
|> (fun x -> Base.Out_channel.save "/tmp/z" ~data:x)
```

In the general case , the ppx ensures that all parameters are executed exactly
once, just like with a regular partial application. For instance, these two
expressions have the exact same performance :

```ocaml
List.filter l ~f:(Re.execp (Re.compile re) __)
List.filter l ~f:(Re.execp (Re.compile re))
```

# Why

The purpose is to see whether one writes code differently with this, for
instance things like :

- replacing `(>) a`, which reads backwards, by `(a > __)`. Similarly with `(-)
  1`.
- removing the tradeoff between easy pipelining, `t` parameter first, and no
  excessive labelled parameters. `Base.Or_error.tag e ~tag` is an example of a
  function where the label creates noise in regular code to make pipelining
  nicer, and `Base.List.take l int` is the opposite.

This is *not* a general lighter syntax for short anonymous functions.  If you
want a lightweight syntax for `(fun x -> f (g x))` or `(fun x -> x * 2 + 1)`,
this ppx isn't providing such things.
<
