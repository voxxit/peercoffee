((root, factory) ->
  if typeof define is "function" and define.amd
    define [], -> root.Peer = factory()
  else if typeof exports is "object"
    module.exports = factory()
  else
    root.Peer = factory()
)(@, () ->

  ###
  A peer who can initiate connections with other peers.
  ###
  Peer = (id, options) ->
    return new Peer(id, options)  unless this instanceof Peer
    EventEmitter.call this

    # Deal with overloading
    if id and id.constructor is Object
      options = id
      id = `undefined`

    # Ensure id is a string
    else id = id.toString()  if id

    #

    # Configurize options
    options = util.extend(
      debug: 0 # 1: Errors, 2: Warnings, 3: All logs
      host: util.CLOUD_HOST
      port: util.CLOUD_PORT
      key: "peerjs"
      path: "/"
      token: util.randomToken()
      config: util.defaultConfig
    , options)
    @options = options

    # Detect relative URL host.
    options.host = window.location.hostname  if options.host is "/"

    # Set path correctly.
    options.path = "/" + options.path  if options.path[0] isnt "/"
    options.path += "/"  if options.path[options.path.length - 1] isnt "/"

    # Set whether we use SSL to same as current host
    options.secure = util.isSecure()  if options.secure is `undefined` and options.host isnt util.CLOUD_HOST

    # Set a custom log function if present
    util.setLogFunction options.logFunction  if options.logFunction
    util.setLogLevel options.debug

    #

    # Sanity checks
    # Ensure WebRTC supported
    if not util.supports.audioVideo and not util.supports.data
      @_delayedAbort "browser-incompatible", "The current browser does not support WebRTC"
      return

    # Ensure alphanumeric id
    unless util.validateId(id)
      @_delayedAbort "invalid-id", "ID \"" + id + "\" is invalid"
      return

    # Ensure valid key
    unless util.validateKey(options.key)
      @_delayedAbort "invalid-key", "API KEY \"" + options.key + "\" is invalid"
      return

    # Ensure not using unsecure cloud server on SSL page
    if options.secure and options.host is "0.peerjs.com"
      @_delayedAbort "ssl-unavailable", "The cloud server currently does not support HTTPS. Please run your own PeerServer to use HTTPS."
      return

    #

    # States.
    @destroyed = false # Connections have been killed
    @disconnected = false # Connection to PeerServer killed but P2P connections still active
    @open = false # Sockets and such are not yet open.
    #

    # References
    @connections = {} # DataConnections for this peer.
    @_lostMessages = {} # src => [list of messages]
    #

    # Start the server connection
    @_initializeServerConnection()
    if id
      @_initialize id
    else
      @_retrieveId()
    return

  #
  util.inherits Peer, EventEmitter

  # Initialize the 'socket' (which is actually a mix of XHR streaming and
  # websockets.)
  Peer::_initializeServerConnection = ->
    self = this
    @socket = new Socket(@options.secure, @options.host, @options.port, @options.path, @options.key)
    @socket.on "message", (data) ->
      self._handleMessage data
      return

    @socket.on "error", (error) ->
      self._abort "socket-error", error
      return

    @socket.on "disconnected", ->

      # If we haven't explicitly disconnected, emit error and disconnect.
      unless self.disconnected
        self.emitError "network", "Lost connection to server."
        self.disconnect()
      return

    @socket.on "close", ->

      # If we haven't explicitly disconnected, emit error.
      self._abort "socket-closed", "Underlying socket is already closed."  unless self.disconnected
      return

    return


  ###
  Get a unique ID from the server via XHR.
  ###
  Peer::_retrieveId = (cb) ->
    self = this
    http = new XMLHttpRequest()
    protocol = (if @options.secure then "https://" else "http://")
    url = protocol + @options.host + ":" + @options.port + @options.path + @options.key + "/id"
    queryString = "?ts=" + new Date().getTime() + "" + Math.random()
    url += queryString

    # If there's no ID we need to wait for one before trying to init socket.
    http.open "get", url, true
    http.onerror = (e) ->
      util.error "Error retrieving ID", e
      pathError = ""
      pathError = " If you passed in a `path` to your self-hosted PeerServer, " + "you'll also need to pass in that same path when creating a new" + " Peer."  if self.options.path is "/" and self.options.host isnt util.CLOUD_HOST
      self._abort "server-error", "Could not get an ID from the server." + pathError
      return

    http.onreadystatechange = ->
      return  if http.readyState isnt 4
      if http.status isnt 200
        http.onerror()
        return
      self._initialize http.responseText
      return

    http.send null
    return


  ###
  Initialize a connection with the server.
  ###
  Peer::_initialize = (id) ->
    @id = id
    @socket.start @id, @options.token
    return


  ###
  Handles messages from the server.
  ###
  Peer::_handleMessage = (message) ->
    type = message.type
    payload = message.payload
    peer = message.src
    switch type
      when "OPEN" # The connection to the server is open.
        @emit "open", @id
        @open = true
      when "ERROR" # Server error.
        @_abort "server-error", payload.msg
      when "ID-TAKEN" # The selected ID is taken.
        @_abort "unavailable-id", "ID `" + @id + "` is taken"
      when "INVALID-KEY" # The given API key cannot be found.
        @_abort "invalid-key", "API KEY \"" + @options.key + "\" is invalid"

      #
      when "LEAVE" # Another peer has closed its connection to this peer.
        util.log "Received leave message from", peer
        @_cleanupPeer peer
      when "EXPIRE" # The offer sent to a peer has expired without response.
        @emitError "peer-unavailable", "Could not connect to peer " + peer
      when "OFFER" # we should consider switching this to CALL/CONNECT, but this is the least breaking option.
        connectionId = payload.connectionId
        connection = @getConnection(peer, connectionId)
        if connection
          util.warn "Offer received for existing Connection ID:", connectionId

        #connection.handleMessage(message);
        else

          # Create a new connection.
          if payload.type is "media"
            connection = new MediaConnection(peer, this,
              connectionId: connectionId
              _payload: payload
              metadata: payload.metadata
            )
            @_addConnection peer, connection
            @emit "call", connection
          else if payload.type is "data"
            connection = new DataConnection(peer, this,
              connectionId: connectionId
              _payload: payload
              metadata: payload.metadata
              label: payload.label
              serialization: payload.serialization
              reliable: payload.reliable
            )
            @_addConnection peer, connection
            @emit "connection", connection
          else
            util.warn "Received malformed connection type:", payload.type
            return

          # Find messages.
          messages = @_getMessages(connectionId)
          i = 0
          ii = messages.length

          while i < ii
            connection.handleMessage messages[i]
            i += 1
      else
        unless payload
          util.warn "You received a malformed message from " + peer + " of type " + type
          return
        id = payload.connectionId
        connection = @getConnection(peer, id)
        if connection and connection.pc

          # Pass it on.
          connection.handleMessage message
        else if id

          # Store for possible later use
          @_storeMessage id, message
        else
          util.warn "You received an unrecognized message:", message


  ###
  Stores messages without a set up connection, to be claimed later.
  ###
  Peer::_storeMessage = (connectionId, message) ->
    @_lostMessages[connectionId] = []  unless @_lostMessages[connectionId]
    @_lostMessages[connectionId].push message
    return


  ###
  Retrieve messages from lost message store
  ###
  Peer::_getMessages = (connectionId) ->
    messages = @_lostMessages[connectionId]
    if messages
      delete @_lostMessages[connectionId]

      messages
    else
      []


  ###
  Returns a DataConnection to the specified peer. See documentation for a
  complete list of options.
  ###
  Peer::connect = (peer, options) ->
    if @disconnected
      util.warn "You cannot connect to a new Peer because you called " + ".disconnect() on this Peer and ended your connection with the" + " server. You can create a new Peer to reconnect, or call reconnect" + " on this peer if you believe its ID to still be available."
      @emitError "disconnected", "Cannot connect to new Peer after disconnecting from server."
      return
    connection = new DataConnection(peer, this, options)
    @_addConnection peer, connection
    connection


  ###
  Returns a MediaConnection to the specified peer. See documentation for a
  complete list of options.
  ###
  Peer::call = (peer, stream, options) ->
    if @disconnected
      util.warn "You cannot connect to a new Peer because you called " + ".disconnect() on this Peer and ended your connection with the" + " server. You can create a new Peer to reconnect."
      @emitError "disconnected", "Cannot connect to new Peer after disconnecting from server."
      return
    unless stream
      util.error "To call a peer, you must provide a stream from your browser's `getUserMedia`."
      return
    options = options or {}
    options._stream = stream
    call = new MediaConnection(peer, this, options)
    @_addConnection peer, call
    call


  ###
  Add a data/media connection to this peer.
  ###
  Peer::_addConnection = (peer, connection) ->
    @connections[peer] = []  unless @connections[peer]
    @connections[peer].push connection
    return


  ###
  Retrieve a data/media connection for this peer.
  ###
  Peer::getConnection = (peer, id) ->
    connections = @connections[peer]
    return null  unless connections
    i = 0
    ii = connections.length

    while i < ii
      return connections[i]  if connections[i].id is id
      i++
    null

  Peer::_delayedAbort = (type, message) ->
    self = this
    util.setZeroTimeout ->
      self._abort type, message
      return

    return


  ###
  Destroys the Peer and emits an error message.
  The Peer is not destroyed if it's in a disconnected state, in which case
  it retains its disconnected state and its existing connections.
  ###
  Peer::_abort = (type, message) ->
    util.error "Aborting!"
    unless @_lastServerId
      @destroy()
    else
      @disconnect()
    @emitError type, message
    return


  ###
  Emits a typed error message.
  ###
  Peer::emitError = (type, err) ->
    util.error "Error:", err
    err = new Error(err)  if typeof err is "string"
    err.type = type
    @emit "error", err
    return


  ###
  Destroys the Peer: closes all active connections as well as the connection
  to the server.
  Warning: The peer can no longer create or accept connections after being
  destroyed.
  ###
  Peer::destroy = ->
    unless @destroyed
      @_cleanup()
      @disconnect()
      @destroyed = true
    return


  ###
  Disconnects every connection on this peer.
  ###
  Peer::_cleanup = ->
    if @connections
      peers = Object.keys(@connections)
      i = 0
      ii = peers.length

      while i < ii
        @_cleanupPeer peers[i]
        i++
    @emit "close"
    return


  ###
  Closes all connections to this peer.
  ###
  Peer::_cleanupPeer = (peer) ->
    connections = @connections[peer]
    j = 0
    jj = connections.length

    while j < jj
      connections[j].close()
      j += 1
    return


  ###
  Disconnects the Peer's connection to the PeerServer. Does not close any
  active connections.
  Warning: The peer can no longer create or accept connections after being
  disconnected. It also cannot reconnect to the server.
  ###
  Peer::disconnect = ->
    self = this
    util.setZeroTimeout ->
      unless self.disconnected
        self.disconnected = true
        self.open = false
        self.socket.close()  if self.socket
        self.emit "disconnected", self.id
        self._lastServerId = self.id
        self.id = null
      return

    return


  ###
  Attempts to reconnect with the same ID.
  ###
  Peer::reconnect = ->
    if @disconnected and not @destroyed
      util.log "Attempting reconnection to server with ID " + @_lastServerId
      @disconnected = false
      @_initializeServerConnection()
      @_initialize @_lastServerId
    else if @destroyed
      throw new Error("This peer cannot reconnect to the server. It has already been destroyed.")
    else if not @disconnected and not @open

      # Do nothing. We're still connecting the first time.
      util.error "In a hurry? We're still trying to make the initial connection!"
    else
      throw new Error("Peer " + @id + " cannot reconnect because it is not disconnected from the server!")
    return


  ###
  Get a list of available peer IDs. If you're running your own server, you'll
  want to set allow_discovery: true in the PeerServer options. If you're using
  the cloud server, email team@peerjs.com to get the functionality enabled for
  your key.
  ###
  Peer::listAllPeers = (cb) ->
    cb = cb or ->

    self = this
    http = new XMLHttpRequest()
    protocol = (if @options.secure then "https://" else "http://")
    url = protocol + @options.host + ":" + @options.port + @options.path + @options.key + "/peers"
    queryString = "?ts=" + new Date().getTime() + "" + Math.random()
    url += queryString

    # If there's no ID we need to wait for one before trying to init socket.
    http.open "get", url, true
    http.onerror = (e) ->
      self._abort "server-error", "Could not get peers from the server."
      cb []
      return

    http.onreadystatechange = ->
      return  if http.readyState isnt 4
      if http.status is 401
        helpfulError = ""
        if self.options.host isnt util.CLOUD_HOST
          helpfulError = "It looks like you're using the cloud server. You can email " + "team@peerjs.com to enable peer listing for your API key."
        else
          helpfulError = "You need to enable `allow_discovery` on your self-hosted" + " PeerServer to use this feature."
        throw new Error("It doesn't look like you have permission to list peers IDs. " + helpfulError)
      else if http.status isnt 200
        cb []
      else
        cb JSON.parse(http.responseText)
      return

    http.send null
    return

  return Peer

)
