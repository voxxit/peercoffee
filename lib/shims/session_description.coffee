((root, factory) ->
  if typeof define is "function" and define.amd
    define [], -> root.RTCSessionDescription = factory()
  else if typeof exports is "object"
    module.exports = factory()
  else
    root.RTCSessionDescription = factory()
)(@, () ->

  return window.RTCSessionDescription or window.mozRTCSessionDescription

)
