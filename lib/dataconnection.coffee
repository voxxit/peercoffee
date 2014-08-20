"use strict"

((root, factory) ->
  if typeof define is "function" and define.amd
    define [], -> root.DataConnection = factory()
  else if typeof exports is "object"
    module.exports = factory()
  else
    root.DataConnection = factory()
)(@, () ->

  # Wraps a DataChannel between two Peers
  DataConnection = (peer, provider, options) ->
    return new DataConnection(peer, provider, options)  unless this instanceof DataConnection
    EventEmitter.call this
    @options = util.extend(
      serialization: "binary"
      reliable: false
    , options)

    # Connection is not open yet.
    @open = false
    @type = "data"
    @peer = peer
    @provider = provider
    @id = @options.connectionId or DataConnection._idPrefix + util.randomToken()
    @label = @options.label or @id
    @metadata = @options.metadata
    @serialization = @options.serialization
    @reliable = @options.reliable

    # Data channel buffering.
    @_buffer = []
    @_buffering = false
    @bufferSize = 0

    # For storing large data.
    @_chunkedData = {}
    @_peerBrowser = @options._payload.browser  if @options._payload
    Negotiator.startConnection this, @options._payload or originator: true
    return
  util.inherits DataConnection, EventEmitter
  DataConnection._idPrefix = "dc_"

  ###
  Called by the Negotiator when the DataChannel is ready.
  ###
  DataConnection::initialize = (dc) ->
    @_dc = @dataChannel = dc
    @_configureDataChannel()
    return

  DataConnection::_configureDataChannel = ->
    self = this
    @_dc.binaryType = "arraybuffer"  if util.supports.sctp
    @_dc.onopen = ->
      util.log "Data channel connection success"
      self.open = true
      self.emit "open"
      return


    # Use the Reliable shim for non Firefox browsers
    @_reliable = new Reliable(@_dc, util.debug)  if not util.supports.sctp and @reliable
    if @_reliable
      @_reliable.onmessage = (msg) ->
        self.emit "data", msg
        return
    else
      @_dc.onmessage = (e) ->
        self._handleDataMessage e
        return
    @_dc.onclose = (e) ->
      util.log "DataChannel closed for:", self.peer
      self.close()
      return

    return


  # Handles a DataChannel message.
  DataConnection::_handleDataMessage = (e) ->
    self = this
    data = e.data
    datatype = data.constructor
    if @serialization is "binary" or @serialization is "binary-utf8"
      if datatype is Blob

        # Datatype should never be blob
        util.blobToArrayBuffer data, (ab) ->
          data = util.unpack(ab)
          self.emit "data", data
          return

        return
      else if datatype is ArrayBuffer
        data = util.unpack(data)
      else if datatype is String

        # String fallback for binary data for browsers that don't support binary yet
        ab = util.binaryStringToArrayBuffer(data)
        data = util.unpack(ab)
    else data = JSON.parse(data)  if @serialization is "json"

    # Check if we've chunked--if so, piece things back together.
    # We're guaranteed that this isn't 0.
    if data.__peerData
      id = data.__peerData
      chunkInfo = @_chunkedData[id] or
        data: []
        count: 0
        total: data.total

      chunkInfo.data[data.n] = data.data
      chunkInfo.count += 1
      if chunkInfo.total is chunkInfo.count

        # Clean up before making the recursive call to `_handleDataMessage`.
        delete @_chunkedData[id]


        # We've received all the chunks--time to construct the complete data.
        data = new Blob(chunkInfo.data)
        @_handleDataMessage data: data
      @_chunkedData[id] = chunkInfo
      return
    @emit "data", data
    return


  ###
  Exposed functionality for users.
  ###

  ###
  Allows user to close connection.
  ###
  DataConnection::close = ->
    return  unless @open
    @open = false
    Negotiator.cleanup this
    @emit "close"
    return


  ###
  Allows user to send data.
  ###
  DataConnection::send = (data, chunked) ->
    unless @open
      @emit "error", new Error("Connection is not open. You should listen for the `open` event before sending messages.")
      return
    if @_reliable

      # Note: reliable shim sending will make it so that you cannot customize
      # serialization.
      @_reliable.send data
      return
    self = this
    if @serialization is "json"
      @_bufferedSend JSON.stringify(data)
    else if @serialization is "binary" or @serialization is "binary-utf8"
      blob = util.pack(data)

      # For Chrome-Firefox interoperability, we need to make Firefox "chunk"
      # the data it sends out.
      needsChunking = util.chunkedBrowsers[@_peerBrowser] or util.chunkedBrowsers[util.browser]
      if needsChunking and not chunked and blob.size > util.chunkedMTU
        @_sendChunks blob
        return

      # DataChannel currently only supports strings.
      unless util.supports.sctp
        util.blobToBinaryString blob, (str) ->
          self._bufferedSend str
          return

      else unless util.supports.binaryBlob

        # We only do this if we really need to (e.g. blobs are not supported),
        # because this conversion is costly.
        util.blobToArrayBuffer blob, (ab) ->
          self._bufferedSend ab
          return

      else
        @_bufferedSend blob
    else
      @_bufferedSend data
    return

  DataConnection::_bufferedSend = (msg) ->
    if @_buffering or not @_trySend(msg)
      @_buffer.push msg
      @bufferSize = @_buffer.length
    return


  # Returns true if the send succeeds.
  DataConnection::_trySend = (msg) ->
    try
      @_dc.send msg
    catch e
      @_buffering = true
      self = this
      setTimeout (->

        # Try again.
        self._buffering = false
        self._tryBuffer()
        return
      ), 100
      return false
    true


  # Try to send the first message in the buffer.
  DataConnection::_tryBuffer = ->
    return  if @_buffer.length is 0
    msg = @_buffer[0]
    if @_trySend(msg)
      @_buffer.shift()
      @bufferSize = @_buffer.length
      @_tryBuffer()
    return

  DataConnection::_sendChunks = (blob) ->
    blobs = util.chunk(blob)
    i = 0
    ii = blobs.length

    while i < ii
      blob = blobs[i]
      @send blob, true
      i += 1
    return

  DataConnection::handleMessage = (message) ->
    payload = message.payload
    switch message.type
      when "ANSWER"
        @_peerBrowser = payload.browser

        # Forward to negotiator
        Negotiator.handleSDP message.type, this, payload.sdp
      when "CANDIDATE"
        Negotiator.handleCandidate this, payload.candidate
      else
        util.warn "Unrecognized message type:", message.type, "from peer:", @peer

  return DataConnection

)
