Modernizr = require('modernizr')

# Using `Modernizr`, we detect a bunch of browser features
# related to WebRTC which may or may not be available yet.
#
# - WebSockets (and binary WebSockets)
# - HTML5 `<video>` element
# - Prefixed `navigator.getUserMedia`
# - Prefixed `RTCPeerConnection`
# - `Blob` constructor
#
class Browser

  @websocket:      Modernizr.websockets
  @video:          Modernizr.video
  @getUserMedia:   Modernizr.getusermedia
  @peerConnection: Modernizr.peerconnection
  @binarySocket:   Modernizr.websocketsbinary
  @blob:           Modernizr.blobconstructor
