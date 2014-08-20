"use strict"

((root, factory) ->
  if typeof define is "function" and define.amd
    define [], -> root.util = factory()
  else if typeof exports is "object"
    module.exports = factory()
  else
    root.util = factory()
)(@, () ->

  defaultConfig = iceServers: [url: "stun:stun.l.google.com:19302"]
  dataCount = 1
  util =
    noop: ->

    CLOUD_HOST: "0.peerjs.com"
    CLOUD_PORT: 9000

    # Browsers that need chunking:
    chunkedBrowsers:
      Chrome: 1

    chunkedMTU: 16300 # The original 60000 bytes setting does not work when sending data from Firefox to Chrome,
                      # which is "cut off" after 16384 bytes and delivered individually.

    # Logging logic
    logLevel: 0
    setLogLevel: (level) ->
      debugLevel = parseInt(level, 10)
      unless isNaN(parseInt(level, 10))
        util.logLevel = debugLevel
      else

        # If they are using truthy/falsy values for debug
        util.logLevel = (if level then 3 else 0)
      util.log = util.warn = util.error = util.noop
      util.error = util._printWith("ERROR")  if util.logLevel > 0
      util.warn = util._printWith("WARNING")  if util.logLevel > 1
      util.log = util._print  if util.logLevel > 2
      return

    setLogFunction: (fn) ->
      if fn.constructor isnt Function
        util.warn "The log function you passed in is not a function. Defaulting to regular logs."
      else
        util._print = fn
      return

    _printWith: (prefix) ->
      ->
        copy = Array::slice.call(arguments_)
        copy.unshift prefix
        util._print.apply util, copy
        return

    _print: ->
      err = false
      copy = Array::slice.call(arguments_)
      copy.unshift "PeerJS: "
      i = 0
      l = copy.length

      while i < l
        if copy[i] instanceof Error
          copy[i] = "(" + copy[i].name + ") " + copy[i].message
          err = true
        i++
      (if err then console.error.apply(console, copy) else console.log.apply(console, copy))
      return


    #

    # Returns browser-agnostic default config
    defaultConfig: defaultConfig

    #

    # Returns the current browser.
    browser: (->
      if window.mozRTCPeerConnection
        "Firefox"
      else if window.webkitRTCPeerConnection
        "Chrome"
      else if window.RTCPeerConnection
        "Supported"
      else
        "Unsupported"
    )()

    #

    # Lists which features are supported
    supports: (->
      return {}  if typeof RTCPeerConnection is "undefined"
      data = true
      audioVideo = true
      binaryBlob = false
      sctp = false
      onnegotiationneeded = !!window.webkitRTCPeerConnection
      pc = undefined
      dc = undefined
      try
        pc = new RTCPeerConnection(defaultConfig,
          optional: [RtpDataChannels: true]
        )
      catch e
        data = false
        audioVideo = false
      if data
        try
          dc = pc.createDataChannel("_PEERJSTEST")
        catch e
          data = false
      if data

        # Binary test
        try
          dc.binaryType = "blob"
          binaryBlob = true

        # Reliable test.
        # Unfortunately Chrome is a bit unreliable about whether or not they
        # support reliable.
        reliablePC = new RTCPeerConnection(defaultConfig, {})
        try
          reliableDC = reliablePC.createDataChannel("_PEERJSRELIABLETEST", {})
          sctp = reliableDC.reliable
        reliablePC.close()

      # FIXME: not really the best check...
      audioVideo = !!pc.addStream  if audioVideo

      # FIXME: this is not great because in theory it doesn't work for
      # av-only browsers (?).
      if not onnegotiationneeded and data

        # sync default check.
        negotiationPC = new RTCPeerConnection(defaultConfig,
          optional: [RtpDataChannels: true]
        )
        negotiationPC.onnegotiationneeded = ->
          onnegotiationneeded = true

          # async check.
          util.supports.onnegotiationneeded = true  if util and util.supports
          return

        negotiationDC = negotiationPC.createDataChannel("_PEERJSNEGOTIATIONTEST")
        setTimeout (->
          negotiationPC.close()
          return
        ), 1000
      pc.close()  if pc
      audioVideo: audioVideo
      data: data
      binaryBlob: binaryBlob
      binary: sctp # deprecated; sctp implies binary support.
      reliable: sctp # deprecated; sctp implies reliable data.
      sctp: sctp
      onnegotiationneeded: onnegotiationneeded
    )()

    #

    # Ensure alphanumeric ids
    validateId: (id) ->

      # Allow empty ids
      not id or /^[A-Za-z0-9]+(?:[ _-][A-Za-z0-9]+)*$/.exec(id)

    validateKey: (key) ->

      # Allow empty keys
      not key or /^[A-Za-z0-9]+(?:[ _-][A-Za-z0-9]+)*$/.exec(key)

    debug: false
    inherits: (ctor, superCtor) ->
      ctor.super_ = superCtor
      ctor:: = Object.create(superCtor::,
        constructor:
          value: ctor
          enumerable: false
          writable: true
          configurable: true
      )
      return

    extend: (dest, source) ->
      for key of source
        dest[key] = source[key]  if source.hasOwnProperty(key)
      dest

    pack: BinaryPack.pack
    unpack: BinaryPack.unpack
    log: ->
      if util.debug
        err = false
        copy = Array::slice.call(arguments_)
        copy.unshift "PeerJS: "
        i = 0
        l = copy.length

        while i < l
          if copy[i] instanceof Error
            copy[i] = "(" + copy[i].name + ") " + copy[i].message
            err = true
          i++
        (if err then console.error.apply(console, copy) else console.log.apply(console, copy))
      return

    setZeroTimeout: ((global) ->

      # Like setTimeout, but only takes a function argument.	 There's
      # no time argument (always zero) and no arguments (you have to
      # use a closure).
      setZeroTimeoutPostMessage = (fn) ->
        timeouts.push fn
        global.postMessage messageName, "*"
        return
      handleMessage = (event) ->
        if event.source is global and event.data is messageName
          event.stopPropagation()  if event.stopPropagation
          timeouts.shift()()  if timeouts.length
        return
      timeouts = []
      messageName = "zero-timeout-message"
      if global.addEventListener
        global.addEventListener "message", handleMessage, true
      else global.attachEvent "onmessage", handleMessage  if global.attachEvent
      setZeroTimeoutPostMessage
    (this))

    # Binary stuff

    # chunks a blob.
    chunk: (bl) ->
      chunks = []
      size = bl.size
      start = index = 0
      total = Math.ceil(size / util.chunkedMTU)
      while start < size
        end = Math.min(size, start + util.chunkedMTU)
        b = bl.slice(start, end)
        chunk =
          __peerData: dataCount
          n: index
          data: b
          total: total

        chunks.push chunk
        start = end
        index += 1
      dataCount += 1
      chunks

    blobToArrayBuffer: (blob, cb) ->
      fr = new FileReader()
      fr.onload = (evt) ->
        cb evt.target.result
        return

      fr.readAsArrayBuffer blob
      return

    blobToBinaryString: (blob, cb) ->
      fr = new FileReader()
      fr.onload = (evt) ->
        cb evt.target.result
        return

      fr.readAsBinaryString blob
      return

    binaryStringToArrayBuffer: (binary) ->
      byteArray = new Uint8Array(binary.length)
      i = 0

      while i < binary.length
        byteArray[i] = binary.charCodeAt(i) & 0xff
        i++
      byteArray.buffer

    randomToken: ->
      Math.random().toString(36).substr 2


    #
    isSecure: ->
      location.protocol is "https:"

  return util

)
