{react, see, bind, duplex, flow, unary, binary} = require('lazy-flow')

module.exports = flow

flow.bindings = (model, name) ->
  result = {}
  for key of model
    result[key+'$'] = duplex(model, key, name)
    result[key+'_'] = bind(model, key, name)
  result

flow.seeAttrs = (target, from) ->
  for key, value of from
    attr = target[key]
    if typeof attr == 'function'
      attr(value)
    else target[key] = see value
  target

flow.neg = (x) -> unary(x, (x) -> -x)
flow.no = flow.not = flow.not_ = (x) -> unary(x, (x) -> !x)
flow.bitnot = (x) -> unary(x, (x) -> ~x)
flow.reciprocal = (x) -> unary(x, (x) -> 1/x)
flow.abs = (x) -> unary(x, Math.abs)
flow.floor = (x) -> unary(x, Math.floor)
flow.ceil = (x) -> unary(x, Math.ceil)
flow.round = (x) -> unary(x, Math.round)

flow.add = (x, y) -> binary(x, y, (x, y) -> x+y)
flow.sub = (x, y) -> binary(x, y, (x, y) -> x-y)
flow.mul = (x, y) -> binary(x, y, (x, y) -> x*y)
flow.div = (x, y) -> binary(x, y, (x, y) -> x/y)
flow.min = (x, y) -> binary(x, y, (x, y) -> Math.min(x, y))

flow.and = (x, y) -> binary(x, y, (x, y) -> x && y)
flow.or = (x, y) -> binary(x, y, (x, y) -> x || y)

# obj can be an object or a function
# attr should be an string
flow.funcAttr = (obj, attr) ->
    flow obj, attr, (value) ->
      objValue = obj()
      if !objValue? then return objValue
      if !arguments.length then objValue[attr]
      else objValue[attr] = value

# this is intended to be called directly
# e.g.div {onclick: -> toggle x; dc.update()}
flow.toggle = (x) -> x(!x())

flow.if_ = (test, then_, else_) ->
  if typeof test != 'function'
    if test then then_ else else_
  else if !test.invalidate
    if typeof then_ == 'function' and typeof else_ == 'function'
      -> if test() then then_() else else_()
    else if then_ == 'function'
      -> if test() then then_() else else_
    else if else_ == 'function'
      -> if test() then then_ else else_()
    else if test() then then_ else else_
  else
    if typeof then_ == 'function' and typeof else_ == 'function'
      if then_.invalidate and else_.invalidate then flow test, then_, else_, ->
        if test() then then_() else else_()
      else -> if test() then then_() else else_()
    else if typeof then_ == 'function'
      if then_.invalidate
        flow test, then_, (-> if test() then then_() else else_)
      else -> if test() then then_() else else_
    else if typeof else_ == 'function'
      if else_.invalidate
        flow else_, (-> if test() then then_ else else_())
      else -> if test() then then_ else else_()
    else flow test, -> if test() then then_ else else_

flow.thisBind = (field) ->
  method = react -> this[field]
  method.bindComponent = (component) ->
    bound = flow.bind(component, field)
    bound.onInvalidate ->
      # make invalidate() does its work
      method.valid = true
      method.invalidate()
    method
  method


