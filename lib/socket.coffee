EventEmitter = require('events').EventEmitter
util = require("util")

# An abstraction on top of WebSockets and XHR streaming to provide fastest possible connection for peers.
Socket = (secure, host, port, path, key) ->
  return new Socket(secure, host, port, path, key)  unless this instanceof Socket
  EventEmitter.call this

  # Disconnected manually.
  @disconnected = false
  @_queue = []
  httpProtocol = (if secure then "https://" else "http://")
  wsProtocol = (if secure then "wss://" else "ws://")
  @_httpUrl = httpProtocol + host + ":" + port + path + key
  @_wsUrl = wsProtocol + host + ":" + port + path + "peerjs?key=" + key

util.inherits Socket, EventEmitter

# Check in with ID or get one from server.
Socket::start = (id, token) ->
  @id = id
  @_httpUrl += "/" + id + "/" + token
  @_wsUrl += "&id=" + id + "&token=" + token
  @_startXhrStream()
  @_startWebSocket()

# Start up websocket communications.
Socket::_startWebSocket = (id) ->
  self = this
  return  if @_socket
  @_socket = new WebSocket(@_wsUrl)
  @_socket.onmessage = (event) ->
    try
      data = JSON.parse(event.data)
      self.emit "message", data
    catch e
      util.log "Invalid server message", event.data
      return
    return

  @_socket.onclose = (event) ->
    util.log "Socket closed."
    self.disconnected = true
    self.emit "disconnected"
    return

  # Take care of the queue of connections if necessary and make sure Peer knows
  # socket is open.
  @_socket.onopen = ->
    if self._timeout
      clearTimeout self._timeout
      setTimeout (->
        self._http.abort()
        self._http = null
        return
      ), 5000
    self._sendQueuedMessages()
    util.log "Socket open"
    return

  return

# Start XHR streaming.
Socket::_startXhrStream = (n) ->
  try
    self = this
    @_http = new XMLHttpRequest()
    @_http._index = 1
    @_http._streamIndex = n or 0
    @_http.open "post", @_httpUrl + "/id?i=" + @_http._streamIndex, true
    @_http.onreadystatechange = ->
      if @readyState is 2 and @old
        @old.abort()
        delete @old
      else if @readyState > 2 and @status is 200 and @responseText
        self._handleStream this
      else if @status isnt 200

        # If we get a different status code, likely something went wrong.
        # Stop streaming.
        clearTimeout self._timeout
        self.emit "disconnected"
      return

    @_http.send null
    @_setHTTPTimeout()
  catch e
    util.log "XMLHttpRequest not available; defaulting to WebSockets"
  return

# Handles onreadystatechange response as a stream.
Socket::_handleStream = (http) ->

  # 3 and 4 are loading/done state. All others are not relevant.
  messages = http.responseText.split("\n")

  # Check to see if anything needs to be processed on buffer.
  if http._buffer
    while http._buffer.length > 0
      index = http._buffer.shift()
      bufferedMessage = messages[index]
      try
        bufferedMessage = JSON.parse(bufferedMessage)
      catch e
        http._buffer.shift index
        break
      @emit "message", bufferedMessage
  message = messages[http._index]
  if message
    http._index += 1

    # Buffering--this message is incomplete and we'll get to it next time.
    # This checks if the httpResponse ended in a `\n`, in which case the last
    # element of messages should be the empty string.
    if http._index is messages.length
      http._buffer = []  unless http._buffer
      http._buffer.push http._index - 1
    else
      try
        message = JSON.parse(message)
      catch e
        util.log "Invalid server message", message
        return
      @emit "message", message
  return

Socket::_setHTTPTimeout = ->
  self = this
  @_timeout = setTimeout(->
    old = self._http
    unless self._wsOpen()
      self._startXhrStream old._streamIndex + 1
      self._http.old = old
    else
      old.abort()
    return
  , 25000)
  return

# Is the websocket currently open?
Socket::_wsOpen = ->
  @_socket and @_socket.readyState is 1

# Send queued messages.
Socket::_sendQueuedMessages = ->
  i = 0
  ii = @_queue.length

  while i < ii
    @send @_queue[i]
    i += 1
  return

# Exposed send for DC & Peer.
Socket::send = (data) ->
  return  if @disconnected

  # If we didn't get an ID yet, we can't yet send anything so we should queue
  # up these messages.
  unless @id
    @_queue.push data
    return
  unless data.type
    @emit "error", "Invalid message"
    return
  message = JSON.stringify(data)
  if @_wsOpen()
    @_socket.send message
  else
    http = new XMLHttpRequest()
    url = @_httpUrl + "/" + data.type.toLowerCase()
    http.open "post", url, true
    http.setRequestHeader "Content-Type", "application/json"
    http.send message
  return

Socket::close = ->
  if not @disconnected and @_wsOpen()
    @_socket.close()
    @disconnected = true
  return

exports = Socket
