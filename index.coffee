{newLine, funcString} = require('dc-util')

react = (method) ->

  if method.invalidate
    return method

  method.valid = false

  method.invalidateCallbacks = []

  method.onInvalidate = (callback) ->
    if typeof callback != 'function'
      throw new Error "call back should be a function"
    else
      invalidateCallbacks = method.invalidateCallbacks ||  method.invalidateCallbacks = []
      invalidateCallbacks.push(callback)

  method.offInvalidate = (callback) ->
    {invalidateCallbacks} = method
    if invalidateCallbacks && (index = invalidateCallbacks.indexOf(callback)) >= 0
        invalidateCallbacks.splice(index, 1)
        if !invalidateCallbacks.length
          method.invalidateCallbacks = null
    method

  method.invalidate = ->
    if method.valid && method.invalidateCallbacks
      for callback in method.invalidateCallbacks
       callback()
      method.valid = false
    method

  method

renew = (computation) ->
  method = ->
    if !arguments.length
      value = computation.call(this)
      method.valid = true
      method.invalidate()
      value
    else throw new Error 'flow.renew is not allowed to accept arguments'

  method.toString = () ->  "renew: #{funcString(computation)}"

  react method

lazy = (method) ->
  react method
  method.invalidate = ->
    if method.invalidateCallbacks
      for callback in method.invalidateCallbacks
        callback()
    method
  oldToString = method.toString
  method.toString = () ->  "lazy: #{oldToString.call(method)}"
  method

module.exports = flow = (deps..., computation) ->
  if !deps.length
    return lazy computation

  for dep in deps
    if typeof dep == 'function' && !dep.invalidate
      return renew(computation)

  cacheValue = null

  reactive = react (value) ->
    if !arguments.length
      if !reactive.valid
        reactive.valid = true
        cacheValue = computation.call(this)
      else
        cacheValue
    else
      if value==cacheValue
        value
      else
        cacheValue = computation.call(this, value)
        reactive.invalidate()
        cacheValue

  for dep in deps
    if dep && dep.onInvalidate
      dep.onInvalidate(reactive.invalidate)

  reactive.toString = ->
    "flow: [#{(for dep in deps then dep.toString()).join(',')}] --> #{funcString(computation)}"

  reactive

flow.pipe = (deps..., computation) ->
  for dep in deps
    if typeof dep == 'function' && !dep.invalidate
      reactive = react ->
        if arguments.length then throw new Error "flow.pipe is not allow to have arguments"
        args = []
        for dep in deps
          if typeof dep == 'function' then args.push dep()
          else args.push dep
        result = computation.apply(this, args)
        reactive.valid = true
        reactive.invalidate()
        result
      return reactive

  reactive = react ->
    reactive.valid = true
    args = []
    for dep in deps
      if typeof dep == 'function' then args.push dep()
      else args.push dep
    computation.apply(this, args)

  for dep in deps
    if dep && dep.onInvalidate
      dep.onInvalidate(reactive.invalidate)

  reactive

flow.react = react

flow.lazy = lazy

flow.renew = renew

flow.flow = flow

flow.see = see = (value, transform) ->
  cacheValue = value

  method = (value) ->
    if !arguments.length
      method.valid = true
      cacheValue
    else
      value = if transform then transform value else value
      if value!=cacheValue
        cacheValue = value
        method.invalidate()
      value

  method.isDuplex = true
  method.toString = () ->  "see: #{value}"
  react method

flow.seeN = (computations...) ->
  for computation in computations then see computation

# Object.defineProperty is ES5 feature, it's not supported in IE 6, 7, 8
# bind and duplex can not be refactored and merged to one implemention
# because the isDuplex should not affect bind
if Object.defineProperty

  flow.bind = (obj, attr, debugName) ->

    d = Object.getOwnPropertyDescriptor(obj, attr)
    if d
      getter = d.get
      {set} = d

    if !getter || !getter.invalidate
      getter = ->
        if arguments.length
          throw new Error('should not set value on flow.bind')
        getter.valid = true
        getter.cacheValue

      getter.cacheValue = obj[attr]

      setter = (value) ->
        if value!=obj[attr]
          if set then set.call(obj, value)
          getter.cacheValue = value
          getter.invalidate()
          value

      react getter

      getter.toString = () ->  "#{debugName || 'm'}[#{attr}]"
      Object.defineProperty(obj, attr, {get:getter, set:setter})
    getter

  flow.duplex = (obj, attr, debugName) ->
    d = Object.getOwnPropertyDescriptor(obj, attr)
    if d
      {get, set} = d

    if !set || !set.invalidate
      method = (value) ->
        if !arguments.length
          method.valid = true
          return method.cacheValue
        if value!=obj[attr]
          if set
            set.call(obj, value)
          get && get.invalidate && get.invalidate()
          method.cacheValue = value
          method.invalidate()
          value
      method.cacheValue = obj[attr]
      react method
      method.isDuplex = true
      method.toString = () ->  "#{debugName or 'm'}[#{attr}]"
      Object.defineProperty(obj, attr, {get:method, set:method})
      method
    else set

else

  flow.bind = (obj, attr, debugName) ->
    _dcBindMethodMap = obj._dcBindMethodMap
    if !_dcBindMethodMap
      _dcBindMethodMap = obj._dcBindMethodMap = {}

    if !obj.dcSet$
      obj.dcSet$ = (attr, value) ->
        if value!=obj[attr]
          _dcBindMethodMap && _dcBindMethodMap[attr] && _dcBindMethodMap[attr].invalidate()
          (_dcDuplexMethodMap=@_dcDuplexMethodMap) && _dcDuplexMethodMap[attr] && _dcDuplexMethodMap[attr].invalidate()

    method = _dcBindMethodMap[attr]
    if !method
      method = _dcBindMethodMap[attr] = ->
        method.valid = true
        obj[attr]
      method.toString = () ->  "#{debugName or 'm'}[#{attr}]"
      react method

    method

  flow.duplex = (obj, attr, debugName) ->
    _dcDuplexMethodMap = obj._dcDuplexMethodMap
    if !_dcDuplexMethodMap
      _dcDuplexMethodMap = obj._dcDuplexMethodMap = {}

    if !obj.dcSet$
      obj.dcSet$ = (attr, value) ->
        if value!=obj[attr]
          (_dcBindMethodMap=@_dcBindMethodMap) && _dcBindMethodMap[attr] && _dcBindMethodMap[attr].invalidate()
          _dcDuplexMethodMap && _dcDuplexMethodMap[attr] && _dcDuplexMethodMap[attr].invalidate()
        value

    method = _dcDuplexMethodMap[attr]

    if !method
      method = _dcDuplexMethodMap[attr] = (value) ->
        if !arguments.length
          method.valid = true
          obj[attr]
        else
          obj.dcSet$(attr, value)
      method.isDuplex = true
      method.toString = () ->  "#{debugName or 'm'}[#{attr}]"
      react method

    method

flow.unary = (x, unaryFn) ->
  if typeof x != 'function' then unaryFn(x)
  else if x.invalidate then flow(x, -> unaryFn(x()))
  else -> unaryFn(x())

flow.binary = (x, y, binaryFn) ->
  if typeof x == 'function' && typeof y == 'function'
    if x.invalidate && y.invalidate then flow x, y, -> binaryFn x(), y()
    else -> binaryFn x(), y()
  else if typeof x == 'function'
    if x.invalidate then flow x, -> binaryFn x(), y
    else -> binaryFn x(), y
  else if typeof y == 'function'
    if y.invalidate then flow y, -> binaryFn x, y()
    else -> binaryFn x, y()
  else binaryFn(x, y)

