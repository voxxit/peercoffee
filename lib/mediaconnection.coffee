Negotiator = require('negotiator')
util = require('util')
EventEmitter = require('events').EventEmitter

# Wraps the streaming interface between two Peers.
MediaConnection = (peer, provider, options) ->
  return new MediaConnection(peer, provider, options)  unless this instanceof MediaConnection
  EventEmitter.call this
  @options = util.extend({}, options)
  @open = false
  @type = "media"
  @peer = peer
  @provider = provider
  @metadata = @options.metadata
  @localStream = @options._stream
  @id = @options.connectionId or MediaConnection._idPrefix + util.randomToken()
  if @localStream
    Negotiator.startConnection this,
      _stream: @localStream
      originator: true

  return

util.inherits MediaConnection, EventEmitter

MediaConnection._idPrefix = "mc_"

MediaConnection::addStream = (remoteStream) ->
  util.log "Receiving stream", remoteStream
  @remoteStream = remoteStream
  @emit "stream", remoteStream # Should we call this `open`?
  return

MediaConnection::handleMessage = (message) ->
  payload = message.payload
  switch message.type
    when "ANSWER"

      # Forward to negotiator
      Negotiator.handleSDP message.type, this, payload.sdp
      @open = true
    when "CANDIDATE"
      Negotiator.handleCandidate this, payload.candidate
    else
      util.warn "Unrecognized message type:", message.type, "from peer:", @peer

MediaConnection::answer = (stream) ->
  if @localStream
    util.warn "Local stream already exists on this MediaConnection. Are you answering a call twice?"
    return
  @options._payload._stream = stream
  @localStream = stream
  Negotiator.startConnection this, @options._payload

  # Retrieve lost messages stored because PeerConnection not set up.
  messages = @provider._getMessages(@id)
  i = 0
  ii = messages.length

  while i < ii
    @handleMessage messages[i]
    i += 1
  @open = true
  return


# Exposed functionality for users.

# Allows user to close connection.
MediaConnection::close = ->
  return  unless @open
  @open = false
  Negotiator.cleanup this
  @emit "close"
  return

exports = MediaConnection
