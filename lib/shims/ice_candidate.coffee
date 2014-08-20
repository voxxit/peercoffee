"use strict"

((root, factory) ->
  if typeof define is "function" and define.amd
    define [], -> root.RTCIceCandidate = factory()
  else if typeof exports is "object"
    module.exports = factory()
  else
    root.RTCIceCandidate = factory()
)(@, () ->

  return root.RTCIceCandidate or root.mozRTCIceCandidate

)
