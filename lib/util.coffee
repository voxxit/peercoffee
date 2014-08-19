# Importing Lo-Dash utility functions - [API Docs](http://devdocs.io/lodash)
_ = require('lodash')

class Log

  @levels:
    SILENT: 0
    ERROR:  1
    WARN:   2
    INFO:   3
    DEBUG:  4
    TRACE:  5

  @level: Log.levels.SILENT  # No logs by default

  constructor: ->
    @set(level || Log.levels.SILENT)

  set: (level) ->
    newLevel = _.invert(Log.levels)[level]

    throw new Error("Invalid level: #{level}") unless newLevel?

    Log.level = newLevel

    @error = @warn = @info = @debug = @trace = _.noop

    for name, val in Log.levels
      if val isnt 5 and val >= Log.level
        @[key.toLowerCase()] = @log(key)

    console.log(@)

  # Internal method which prefixes the log output by the requested
  # log level. If none if provided by the wrapper function, `INFO` is used.
  #
  # *Example console output:*
  #
  #     PeerJS: [DEBUG] 1 2 3
  #
  log: (requestedLogLevel = Log.levels.INFO, messages...) ->
    if requestedLogLevel >= Log.level
      name = _.invert(Log.levels)[requestedLogLevel]
      prefixes = ["PeerJS:", "[#{name}]"]

      for message in messages
        if message instanceof Error
          message = "(#{message.name}) #{message.message}"

        console[name.toLowerCase()].apply(console, messages)

class Util

  # Class Methods
  # ------------
  #
  # We provide a default list of public STUN servers we'll try to
  # use for breaking through NAT and firewalls. More information on these
  # and other public servers can be found here:
  #
  # http://goo.gl/faYctg
  #
  # It is recommended that you use your own private STUN server
  # since public servers may not offer the highest form of reliability.
  #
  # All STUN servers require the `url` parameter.
  #
  @iceServers: [
    { url: "stun.l.google.com:19302"  }
    { url: "stun1.l.google.com:19302" }
    { url: "stun2.l.google.com:19302" }
    { url: "stun3.l.google.com:19302" }
    { url: "stun4.l.google.com:19302" }
  ]

  @dataCount: 1

  # Set `Util.cloudHost` and `Util.cloudPort` to the PeerJS server you'll be
  # connecting to.
  @cloudHost: "0.peerjs.com"
  @cloudPort: 9000

  # Chrome is the only browser currently known to require chunking.
  @chunkedBrowsers:
    Chrome: true

  # The original 60000 bytes setting does not work when sending data from
  # Firefox to Chrome, which is "cut off" after 16384 bytes and delivered
  # individually.
  @chunkedMTU: 16300

  # Instance Methods
  # ----------------




#   _print: ->
#     err = false
#     copy = Array::slice.call(arguments_)
#     copy.unshift "PeerJS: "
#     i = 0
#     l = copy.length
#
#     while i < l
#       if copy[i] instanceof Error
#         copy[i] = "(" + copy[i].name + ") " + copy[i].message
#         err = true
#       i++
#     (if err
#        console.error.apply(console, copy)
#       else console.log.apply(console, copy))
#
#   # Returns browser-agnostic default config
#   defaultConfig: defaultConfig
#
#   #
#
#   # Returns the current browser.
#   browser: (->
#     if window.mozRTCPeerConnection
#       "Firefox"
#     else if window.webkitRTCPeerConnection
#       "Chrome"
#     else if window.RTCPeerConnection
#       "Supported"
#     else
#       "Unsupported"
#   )()
#
#   #
#
#   # Lists which features are supported
#   supports: (->
#     return {}  if typeof RTCPeerConnection is "undefined"
#     data = true
#     audioVideo = true
#     binaryBlob = false
#     sctp = false
#     onnegotiationneeded = !!window.webkitRTCPeerConnection
#     pc = undefined
#     dc = undefined
#     try
#       pc = new RTCPeerConnection(defaultConfig,
#         optional: [RtpDataChannels: true]
#       )
#     catch e
#       data = false
#       audioVideo = false
#     if data
#       try
#         dc = pc.createDataChannel("_PEERJSTEST")
#       catch e
#         data = false
#     if data
#
#       # Binary test
#       try
#         dc.binaryType = "blob"
#         binaryBlob = true
#
#       # Reliable test.
#       # Unfortunately Chrome is a bit unreliable about whether or not they
#       # support reliable.
#       reliablePC = new RTCPeerConnection(defaultConfig, {})
#       try
#         reliableDC = reliablePC.createDataChannel("_PEERJSRELIABLETEST", {})
#         sctp = reliableDC.reliable
#       reliablePC.close()
#
#     # FIXME: not really the best check...
#     audioVideo = !!pc.addStream  if audioVideo
#
#     # FIXME: this is not great because in theory it doesn't work for
#     # av-only browsers (?).
#     if not onnegotiationneeded and data
#
#       # sync default check.
#       negotiationPC = new RTCPeerConnection(defaultConfig,
#         optional: [RtpDataChannels: true]
#       )
#       negotiationPC.onnegotiationneeded = ->
#         onnegotiationneeded = true
#
#         # async check.
#         util.supports.onnegotiationneeded = true  if util and util.supports
#         return
#
#       negotiationDC = negotiationPC.createDataChannel(
#         "_PEERJSNEGOTIATIONTEST"
#       )
#       setTimeout (->
#         negotiationPC.close()
#         return
#       ), 1000
#     pc.close()  if pc
#     audioVideo: audioVideo
#     data: data
#     binaryBlob: binaryBlob
#     binary: sctp # deprecated; sctp implies binary support.
#     reliable: sctp # deprecated; sctp implies reliable data.
#     sctp: sctp
#     onnegotiationneeded: onnegotiationneeded
#   ()
#
#   #
#
#   # Ensure alphanumeric ids
#   validateId: (id) ->
#
#     # Allow empty ids
#     not id or /^[A-Za-z0-9]+(?:[ _-][A-Za-z0-9]+)*$/.exec(id)
#
#   validateKey: (key) ->
#
#     # Allow empty keys
#     not key or /^[A-Za-z0-9]+(?:[ _-][A-Za-z0-9]+)*$/.exec(key)
#
#   debug: false
#   inherits: (ctor, superCtor) ->
#     ctor.super_ = superCtor
#     ctor:: = Object.create(superCtor::,
#       constructor:
#         value: ctor
#         enumerable: false
#         writable: true
#         configurable: true
#     )
#     return
#
#   extend: (dest, source) ->
#     for key of source
#       dest[key] = source[key]  if source.hasOwnProperty(key)
#     dest
#
#   pack: BinaryPack.pack
#   unpack: BinaryPack.unpack
#
#   log: ->
#     if util.debug is true
#       err = false
#       copy = Array::slice.call(arguments_)
#       copy.unshift "PeerJS: "
#       i = 0
#       l = copy.length
#
#       while i < l
#         if copy[i] instanceof Error
#           copy[i] = "(" + copy[i].name + ") " + copy[i].message
#           err = true
#         i++
#       (if err
#          console.error.apply(console, copy)
#        else console.log.apply(console, copy))
#     return
#
#   setZeroTimeout: ((global) ->
#
#     # Like setTimeout, but only takes a function argument.	 There's
#     # no time argument (always zero) and no arguments (you have to
#     # use a closure).
#     setZeroTimeoutPostMessage = (fn) ->
#       timeouts.push fn
#       global.postMessage messageName, "*"
#       return
#     handleMessage = (event) ->
#       if event.source is global and event.data is messageName
#         event.stopPropagation()  if event.stopPropagation
#         timeouts.shift()()  if timeouts.length
#       return
#     timeouts = []
#     messageName = "zero-timeout-message"
#     if global.addEventListener
#       global.addEventListener "message", handleMessage, true
#     else global.attachEvent "onmessage", handleMessage  if global.attachEvent
#     setZeroTimeoutPostMessage
#   (this))
#
#   chunk: (bl) ->
#     chunks = []
#     size = bl.size
#     start = index = 0
#     total = Math.ceil(size / util.chunkedMTU)
#     while start < size
#       end = Math.min(size, start + util.chunkedMTU)
#       b = bl.slice(start, end)
#       chunk =
#         __peerData: dataCount
#         n: index
#         data: b
#         total: total
#
#       chunks.push chunk
#       start = end
#       index += 1
#     dataCount += 1
#     chunks
#
#   blobToArrayBuffer: (blob, cb) ->
#     fr = new FileReader()
#
#     fr.onload = (evt) ->
#       cb evt.target.result
#
#     fr.readAsArrayBuffer blob
#
#   blobToBinaryString: (blob, cb) ->
#     fr = new FileReader()
#
#     fr.onload = (evt) ->
#       cb evt.target.result
#
#     fr.readAsBinaryString blob
#
#   binaryStringToArrayBuffer: (binary) ->
#     byteArray = new Uint8Array(binary.length)
#     i = 0
#
#     while i < binary.length
#       byteArray[i] = binary.charCodeAt(i) & 0xff
#       i++
#
#     byteArray.buffer
#
#   randomToken: -> Math.random().toString(36).substr 2
#
#   isSecure: -> location.protocol is "https:"
#
root = exports ? window
root.util = util
