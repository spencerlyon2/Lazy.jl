export @rec

tailcall(ex, f, dummy, start) =
  ex.args[1] ≠ f ? ex :
    :($(tupleassign(dummy, ex.args[2:end])); @goto $start)

lastcalls(ex, f, dummy, start) =
  @switch isexpr(ex, _),
    :call  -> tailcall(ex, f, dummy, start),
    :block -> Expr(:block, lastcalls(ex.args, f, dummy, start)...),
    :let   -> Expr(:let, lastcalls(ex.args[1], f, dummy, start), ex.args[2:end]...),
    :if    -> Expr(:if, ex.args[1], lastcalls(ex.args[2], f, dummy, start), lastcalls(ex.args[3], f, dummy, start)),
    ex

lastcalls(ex::Array, f, dummy, start) =
  isempty(ex) ? ex :
    [ex[1:end-1]..., lastcalls(ex[end], f, dummy, start)]

retcalls(ex, f, dummy, start) =
  isexpr(ex, :return) ? Expr(:return, lastcalls(ex.args[1], f, dummy, start)) :
  isexpr(ex) ? Expr(ex.head, map(ex->retcalls(ex, f, dummy, start), ex.args)...) :
  ex

"Generate an expression like `(a, b) = (c, d)`."
tupleassign(xs, ys) = Expr(:(=), Expr(:tuple, xs...), Expr(:tuple, ys...))

"""
Enables efficient recursive functions, e.g.

    @rec reduce(f::Function, v, xs::List) =
      isempty(xs) ? v : reduce(f, f(v, first(xs)), rest(xs))

Without `@rec` this function would overflow the stack for
lists of 80,000 or more elements.

Caveats:
  • No support for trampolining, i.e. only calls to the
    given function are optimised away.
  • Ignores multiple dispatch – it is assumed that the function's
    name always refers to the given definition.
  • Don't rebind the function's name in a let (see above).
  • Don't use this with varargs functions.
"""
macro rec (def)
  @assert isdef(def)
  f = def.args[1].args[1]
  args = @>> def.args[1].args[2:end]
  dummy = @>> args map(namify) map(string) map(gensym)
  body = def.args[2]

  # Set up of variables
  @gensym start
  unshift!(body.args, quote
             $(tupleassign(dummy, args))
             @label $start
             $(tupleassign(args, dummy))
           end)

  def.args[2] = @> body macroexpand lastcalls(f, dummy, start) retcalls(f, dummy, start)
  return esc(def)
end
