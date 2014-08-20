"use strict"

((root, factory) ->
  if typeof define is "function" and define.amd
    define [], -> root.Negotiator = factory()
  else if typeof exports is "object"
    module.exports = factory()
  else
    root.Negotiator = factory()
)(@, () ->

  ## Negotiator
  # ---
  # Manages all negotiations between Peers.
  Negotiator =
    pcs:
      data: {}
      media: {}

    # type => {peerId: {pc_id: pc}}.
    #providers: {}, // provider's id => providers (there may be multiple providers/client.
    queue: [] # connections that are delayed due to a PC being in use.

  Negotiator._idPrefix = "pc_"

  # Returns a PeerConnection object set up correctly (for data, media).
  Negotiator.startConnection = (connection, options) ->
    pc = Negotiator._getPeerConnection(connection, options)

    # Add the stream.
    pc.addStream options._stream  if connection.type is "media" and options._stream

    # Set the connection's PC.
    connection.pc = connection.peerConnection = pc

    # What do we need to do now?
    if options.originator
      if connection.type is "data"

        # Create the datachannel.
        config = {}

        # Dropping reliable:false support, since it seems to be crashing
        # Chrome.
        #if (util.supports.sctp && !options.reliable) {
        #        // If we have canonical reliable support...
        #        config = {maxRetransmits: 0};
        #      }

        # Fallback to ensure older browsers don't crash.
        config = reliable: options.reliable  unless util.supports.sctp
        dc = pc.createDataChannel(connection.label, config)
        connection.initialize dc
      Negotiator._makeOffer connection  unless util.supports.onnegotiationneeded
    else
      Negotiator.handleSDP "OFFER", connection, options.sdp

  Negotiator._getPeerConnection = (connection, options) ->
    unless Negotiator.pcs[connection.type]
      util.error "#{connection.type} is not a valid connection type. Maybe you overrode the `type` property somewhere."

    unless Negotiator.pcs[connection.type][connection.peer]
      Negotiator.pcs[connection.type][connection.peer] = {}

    peerConnections = Negotiator.pcs[connection.type][connection.peer]
    pc = undefined

    # Not multiplexing while FF and Chrome have not-great support for it.
    #if (options.multiplex) {
    #    ids = Object.keys(peerConnections);
    #    for (var i = 0, ii = ids.length; i < ii; i += 1) {
    #      pc = peerConnections[ids[i]];
    #      if (pc.signalingState === 'stable') {
    #        break; // We can go ahead and use this PC.
    #      }
    #    }
    #  } else
    # Simplest case: PC id already provided for us.
    pc = Negotiator.pcs[connection.type][connection.peer][options.pc]  if options.pc
    pc = Negotiator._startPeerConnection(connection)  if not pc or pc.signalingState isnt "stable"
    pc

  #Negotiator._addProvider = function(provider) {
  #  if ((!provider.id && !provider.disconnected) || !provider.socket.open) {
  #    // Wait for provider to obtain an ID.
  #    provider.on('open', function(id) {
  #      Negotiator._addProvider(provider);
  #    });
  #  } else {
  #    Negotiator.providers[provider.id] = provider;
  #  }
  #}

  # Start a PC
  Negotiator._startPeerConnection = (connection) ->
    util.log "Creating RTCPeerConnection."
    id = Negotiator._idPrefix + util.randomToken()
    optional = {}
    if connection.type is "data" and not util.supports.sctp
      optional = optional: [RtpDataChannels: true]

    # Interop req for chrome.
    else optional = optional: [DtlsSrtpKeyAgreement: true]  if connection.type is "media"
    pc = new RTCPeerConnection(connection.provider.options.config, optional)
    Negotiator.pcs[connection.type][connection.peer][id] = pc
    Negotiator._setupListeners connection, pc, id
    pc

  # Set up various WebRTC listeners.
  Negotiator._setupListeners = (connection, pc, pc_id) ->
    peerId = connection.peer
    connectionId = connection.id
    provider = connection.provider

    # ICE CANDIDATES.
    util.log "Listening for ICE candidates."
    pc.onicecandidate = (evt) ->
      if evt.candidate
        util.log "Received ICE candidates for:", connection.peer
        provider.socket.send
          type: "CANDIDATE"
          payload:
            candidate: evt.candidate
            type: connection.type
            connectionId: connection.id

          dst: peerId

      return

    pc.oniceconnectionstatechange = ->
      switch pc.iceConnectionState
        when "disconnected", "failed"
          util.log "iceConnectionState is disconnected, closing connections to " + peerId
          connection.close()
        when "completed"
          pc.onicecandidate = util.noop


    # Fallback for older Chrome impls.
    pc.onicechange = pc.oniceconnectionstatechange

    # ONNEGOTIATIONNEEDED (Chrome)
    util.log "Listening for `negotiationneeded`"
    pc.onnegotiationneeded = ->
      util.log "`negotiationneeded` triggered"
      if pc.signalingState is "stable"
        Negotiator._makeOffer connection
      else
        util.log "onnegotiationneeded triggered when not stable. Is another connection being established?"
      return


    # DATACONNECTION.
    util.log "Listening for data channel"

    # Fired between offer and answer, so options should already be saved
    # in the options hash.
    pc.ondatachannel = (evt) ->
      util.log "Received data channel"
      dc = evt.channel
      connection = provider.getConnection(peerId, connectionId)
      connection.initialize dc
      return


    # MEDIACONNECTION.
    util.log "Listening for remote stream"
    pc.onaddstream = (evt) ->
      util.log "Received remote stream"
      stream = evt.stream
      provider.getConnection(peerId, connectionId).addStream stream
      return

    return

  Negotiator.cleanup = (connection) ->
    util.log "Cleaning up PeerConnection to " + connection.peer
    pc = connection.pc
    if !!pc and (pc.readyState isnt "closed" or pc.signalingState isnt "closed")
      pc.close()
      connection.pc = null
    return

  Negotiator._makeOffer = (connection) ->
    pc = connection.pc
    pc.createOffer ((offer) ->
      util.log "Created offer."
      if not util.supports.sctp and connection.type is "data" and connection.reliable
        offer.sdp = Reliable.higherBandwidthSDP(offer.sdp)

      pc.setLocalDescription offer, (->
        util.log "Set localDescription: offer", "for:", connection.peer
        connection.provider.socket.send
          type: "OFFER"
          payload:
            sdp: offer
            type: connection.type
            label: connection.label
            connectionId: connection.id
            reliable: connection.reliable
            serialization: connection.serialization
            metadata: connection.metadata
            browser: util.browser

          dst: connection.peer

        return
      ), (err) ->
        connection.provider.emitError "webrtc", err
        util.log "Failed to setLocalDescription, ", err
        return

      return
    ), ((err) ->
      connection.provider.emitError "webrtc", err
      util.log "Failed to createOffer, ", err
      return
    ), connection.options.constraints

  Negotiator._makeAnswer = (connection) ->
    pc = connection.pc
    pc.createAnswer ((answer) ->
      util.log "Created answer."
      if not util.supports.sctp and connection.type is "data" and connection.reliable
        answer.sdp = Reliable.higherBandwidthSDP(answer.sdp)

      pc.setLocalDescription answer, (->
        util.log "Set localDescription: answer", "for:", connection.peer
        connection.provider.socket.send
          type: "ANSWER"
          payload:
            sdp: answer
            type: connection.type
            connectionId: connection.id
            browser: util.browser

          dst: connection.peer

        return
      ), (err) ->
        connection.provider.emitError "webrtc", err
        util.log "Failed to setLocalDescription, ", err
        return

      return
    ), (err) ->
      connection.provider.emitError "webrtc", err
      util.log "Failed to create answer, ", err

  # Handle an SDP
  Negotiator.handleSDP = (type, connection, sdp) ->
    sdp = new RTCSessionDescription(sdp)
    pc = connection.pc
    util.log "Setting remote description", sdp
    pc.setRemoteDescription sdp, (->
      util.log "Set remoteDescription:", type, "for:", connection.peer
      Negotiator._makeAnswer connection  if type is "OFFER"
    ), (err) ->
      connection.provider.emitError "webrtc", err
      util.log "Failed to setRemoteDescription, ", err

  # Handle a candidate.
  Negotiator.handleCandidate = (connection, ice) ->
    candidate = ice.candidate
    sdpMLineIndex = ice.sdpMLineIndex
    connection.pc.addIceCandidate new RTCIceCandidate(
      sdpMLineIndex: sdpMLineIndex
      candidate: candidate
    )
    util.log "Added ICE candidate for:", connection.peer

  return Negotiator

)
