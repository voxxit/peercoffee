((root, factory) ->
  if typeof define is "function" and define.amd
    define [], -> root.RTCPeerConnection = factory()
  else if typeof exports is "object"
    module.exports = factory()
  else
    root.RTCPeerConnection = factory()
)(@, () ->

  return root.RTCPeerConnection or root.mozRTCPeerConnection or root.webkitRTCPeerConnection

)
