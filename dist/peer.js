(function(root, factory) {
  if (typeof define === "function" && define.amd) {
    return define([], function() {
      return root.DataConnection = factory();
    });
  } else if (typeof exports === "object") {
    return module.exports = factory();
  } else {
    return root.DataConnection = factory();
  }
})(this, function() {
  var DataConnection;
  DataConnection = function(peer, provider, options) {
    if (!(this instanceof DataConnection)) {
      return new DataConnection(peer, provider, options);
    }
    EventEmitter.call(this);
    this.options = util.extend({
      serialization: "binary",
      reliable: false
    }, options);
    this.open = false;
    this.type = "data";
    this.peer = peer;
    this.provider = provider;
    this.id = this.options.connectionId || DataConnection._idPrefix + util.randomToken();
    this.label = this.options.label || this.id;
    this.metadata = this.options.metadata;
    this.serialization = this.options.serialization;
    this.reliable = this.options.reliable;
    this._buffer = [];
    this._buffering = false;
    this.bufferSize = 0;
    this._chunkedData = {};
    if (this.options._payload) {
      this._peerBrowser = this.options._payload.browser;
    }
    Negotiator.startConnection(this, this.options._payload || {
      originator: true
    });
  };
  util.inherits(DataConnection, EventEmitter);
  DataConnection._idPrefix = "dc_";

  /*
  Called by the Negotiator when the DataChannel is ready.
   */
  DataConnection.prototype.initialize = function(dc) {
    this._dc = this.dataChannel = dc;
    this._configureDataChannel();
  };
  DataConnection.prototype._configureDataChannel = function() {
    var self;
    self = this;
    if (util.supports.sctp) {
      this._dc.binaryType = "arraybuffer";
    }
    this._dc.onopen = function() {
      util.log("Data channel connection success");
      self.open = true;
      self.emit("open");
    };
    if (!util.supports.sctp && this.reliable) {
      this._reliable = new Reliable(this._dc, util.debug);
    }
    if (this._reliable) {
      this._reliable.onmessage = function(msg) {
        self.emit("data", msg);
      };
    } else {
      this._dc.onmessage = function(e) {
        self._handleDataMessage(e);
      };
    }
    this._dc.onclose = function(e) {
      util.log("DataChannel closed for:", self.peer);
      self.close();
    };
  };
  DataConnection.prototype._handleDataMessage = function(e) {
    var ab, chunkInfo, data, datatype, id, self;
    self = this;
    data = e.data;
    datatype = data.constructor;
    if (this.serialization === "binary" || this.serialization === "binary-utf8") {
      if (datatype === Blob) {
        util.blobToArrayBuffer(data, function(ab) {
          data = util.unpack(ab);
          self.emit("data", data);
        });
        return;
      } else if (datatype === ArrayBuffer) {
        data = util.unpack(data);
      } else if (datatype === String) {
        ab = util.binaryStringToArrayBuffer(data);
        data = util.unpack(ab);
      }
    } else {
      if (this.serialization === "json") {
        data = JSON.parse(data);
      }
    }
    if (data.__peerData) {
      id = data.__peerData;
      chunkInfo = this._chunkedData[id] || {
        data: [],
        count: 0,
        total: data.total
      };
      chunkInfo.data[data.n] = data.data;
      chunkInfo.count += 1;
      if (chunkInfo.total === chunkInfo.count) {
        delete this._chunkedData[id];
        data = new Blob(chunkInfo.data);
        this._handleDataMessage({
          data: data
        });
      }
      this._chunkedData[id] = chunkInfo;
      return;
    }
    this.emit("data", data);
  };

  /*
  Exposed functionality for users.
   */

  /*
  Allows user to close connection.
   */
  DataConnection.prototype.close = function() {
    if (!this.open) {
      return;
    }
    this.open = false;
    Negotiator.cleanup(this);
    this.emit("close");
  };

  /*
  Allows user to send data.
   */
  DataConnection.prototype.send = function(data, chunked) {
    var blob, needsChunking, self;
    if (!this.open) {
      this.emit("error", new Error("Connection is not open. You should listen for the `open` event before sending messages."));
      return;
    }
    if (this._reliable) {
      this._reliable.send(data);
      return;
    }
    self = this;
    if (this.serialization === "json") {
      this._bufferedSend(JSON.stringify(data));
    } else if (this.serialization === "binary" || this.serialization === "binary-utf8") {
      blob = util.pack(data);
      needsChunking = util.chunkedBrowsers[this._peerBrowser] || util.chunkedBrowsers[util.browser];
      if (needsChunking && !chunked && blob.size > util.chunkedMTU) {
        this._sendChunks(blob);
        return;
      }
      if (!util.supports.sctp) {
        util.blobToBinaryString(blob, function(str) {
          self._bufferedSend(str);
        });
      } else if (!util.supports.binaryBlob) {
        util.blobToArrayBuffer(blob, function(ab) {
          self._bufferedSend(ab);
        });
      } else {
        this._bufferedSend(blob);
      }
    } else {
      this._bufferedSend(data);
    }
  };
  DataConnection.prototype._bufferedSend = function(msg) {
    if (this._buffering || !this._trySend(msg)) {
      this._buffer.push(msg);
      this.bufferSize = this._buffer.length;
    }
  };
  DataConnection.prototype._trySend = function(msg) {
    var e, self;
    try {
      this._dc.send(msg);
    } catch (_error) {
      e = _error;
      this._buffering = true;
      self = this;
      setTimeout((function() {
        self._buffering = false;
        self._tryBuffer();
      }), 100);
      return false;
    }
    return true;
  };
  DataConnection.prototype._tryBuffer = function() {
    var msg;
    if (this._buffer.length === 0) {
      return;
    }
    msg = this._buffer[0];
    if (this._trySend(msg)) {
      this._buffer.shift();
      this.bufferSize = this._buffer.length;
      this._tryBuffer();
    }
  };
  DataConnection.prototype._sendChunks = function(blob) {
    var blobs, i, ii;
    blobs = util.chunk(blob);
    i = 0;
    ii = blobs.length;
    while (i < ii) {
      blob = blobs[i];
      this.send(blob, true);
      i += 1;
    }
  };
  DataConnection.prototype.handleMessage = function(message) {
    var payload;
    payload = message.payload;
    switch (message.type) {
      case "ANSWER":
        this._peerBrowser = payload.browser;
        return Negotiator.handleSDP(message.type, this, payload.sdp);
      case "CANDIDATE":
        return Negotiator.handleCandidate(this, payload.candidate);
      default:
        return util.warn("Unrecognized message type:", message.type, "from peer:", this.peer);
    }
  };
  return DataConnection;
});

(function(root, factory) {
  if (typeof define === "function" && define.amd) {
    return define([], function() {
      return root.MediaConnection = factory();
    });
  } else if (typeof exports === "object") {
    return module.exports = factory();
  } else {
    return root.MediaConnection = factory();
  }
})(this, function() {
  var MediaConnection;
  MediaConnection = function(peer, provider, options) {
    if (!(this instanceof MediaConnection)) {
      return new MediaConnection(peer, provider, options);
    }
    EventEmitter.call(this);
    this.options = util.extend({}, options);
    this.open = false;
    this.type = "media";
    this.peer = peer;
    this.provider = provider;
    this.metadata = this.options.metadata;
    this.localStream = this.options._stream;
    this.id = this.options.connectionId || MediaConnection._idPrefix + util.randomToken();
    if (this.localStream) {
      Negotiator.startConnection(this, {
        _stream: this.localStream,
        originator: true
      });
    }
  };
  util.inherits(MediaConnection, EventEmitter);
  MediaConnection._idPrefix = "mc_";
  MediaConnection.prototype.addStream = function(remoteStream) {
    util.log("Receiving stream", remoteStream);
    this.remoteStream = remoteStream;
    this.emit("stream", remoteStream);
  };
  MediaConnection.prototype.handleMessage = function(message) {
    var payload;
    payload = message.payload;
    switch (message.type) {
      case "ANSWER":
        Negotiator.handleSDP(message.type, this, payload.sdp);
        return this.open = true;
      case "CANDIDATE":
        return Negotiator.handleCandidate(this, payload.candidate);
      default:
        return util.warn("Unrecognized message type:", message.type, "from peer:", this.peer);
    }
  };
  MediaConnection.prototype.answer = function(stream) {
    var i, ii, messages;
    if (this.localStream) {
      util.warn("Local stream already exists on this MediaConnection. Are you answering a call twice?");
      return;
    }
    this.options._payload._stream = stream;
    this.localStream = stream;
    Negotiator.startConnection(this, this.options._payload);
    messages = this.provider._getMessages(this.id);
    i = 0;
    ii = messages.length;
    while (i < ii) {
      this.handleMessage(messages[i]);
      i += 1;
    }
    this.open = true;
  };
  MediaConnection.prototype.close = function() {
    if (!this.open) {
      return;
    }
    this.open = false;
    Negotiator.cleanup(this);
    this.emit("close");
  };
  return MediaConnection;
});

(function(root, factory) {
  if (typeof define === "function" && define.amd) {
    return define([], function() {
      return root.Negotiator = factory();
    });
  } else if (typeof exports === "object") {
    return module.exports = factory();
  } else {
    return root.Negotiator = factory();
  }
})(this, function() {
  var Negotiator;
  Negotiator = {
    pcs: {
      data: {},
      media: {}
    },
    queue: []
  };
  Negotiator._idPrefix = "pc_";
  Negotiator.startConnection = function(connection, options) {
    var config, dc, pc;
    pc = Negotiator._getPeerConnection(connection, options);
    if (connection.type === "media" && options._stream) {
      pc.addStream(options._stream);
    }
    connection.pc = connection.peerConnection = pc;
    if (options.originator) {
      if (connection.type === "data") {
        config = {};
        if (!util.supports.sctp) {
          config = {
            reliable: options.reliable
          };
        }
        dc = pc.createDataChannel(connection.label, config);
        connection.initialize(dc);
      }
      if (!util.supports.onnegotiationneeded) {
        return Negotiator._makeOffer(connection);
      }
    } else {
      return Negotiator.handleSDP("OFFER", connection, options.sdp);
    }
  };
  Negotiator._getPeerConnection = function(connection, options) {
    var pc, peerConnections;
    if (!Negotiator.pcs[connection.type]) {
      util.error("" + connection.type + " is not a valid connection type. Maybe you overrode the `type` property somewhere.");
    }
    if (!Negotiator.pcs[connection.type][connection.peer]) {
      Negotiator.pcs[connection.type][connection.peer] = {};
    }
    peerConnections = Negotiator.pcs[connection.type][connection.peer];
    pc = void 0;
    if (options.pc) {
      pc = Negotiator.pcs[connection.type][connection.peer][options.pc];
    }
    if (!pc || pc.signalingState !== "stable") {
      pc = Negotiator._startPeerConnection(connection);
    }
    return pc;
  };
  Negotiator._startPeerConnection = function(connection) {
    var id, optional, pc;
    util.log("Creating RTCPeerConnection.");
    id = Negotiator._idPrefix + util.randomToken();
    optional = {};
    if (connection.type === "data" && !util.supports.sctp) {
      optional = {
        optional: [
          {
            RtpDataChannels: true
          }
        ]
      };
    } else {
      if (connection.type === "media") {
        optional = {
          optional: [
            {
              DtlsSrtpKeyAgreement: true
            }
          ]
        };
      }
    }
    pc = new RTCPeerConnection(connection.provider.options.config, optional);
    Negotiator.pcs[connection.type][connection.peer][id] = pc;
    Negotiator._setupListeners(connection, pc, id);
    return pc;
  };
  Negotiator._setupListeners = function(connection, pc, pc_id) {
    var connectionId, peerId, provider;
    peerId = connection.peer;
    connectionId = connection.id;
    provider = connection.provider;
    util.log("Listening for ICE candidates.");
    pc.onicecandidate = function(evt) {
      if (evt.candidate) {
        util.log("Received ICE candidates for:", connection.peer);
        provider.socket.send({
          type: "CANDIDATE",
          payload: {
            candidate: evt.candidate,
            type: connection.type,
            connectionId: connection.id
          },
          dst: peerId
        });
      }
    };
    pc.oniceconnectionstatechange = function() {
      switch (pc.iceConnectionState) {
        case "disconnected":
        case "failed":
          util.log("iceConnectionState is disconnected, closing connections to " + peerId);
          return connection.close();
        case "completed":
          return pc.onicecandidate = util.noop;
      }
    };
    pc.onicechange = pc.oniceconnectionstatechange;
    util.log("Listening for `negotiationneeded`");
    pc.onnegotiationneeded = function() {
      util.log("`negotiationneeded` triggered");
      if (pc.signalingState === "stable") {
        Negotiator._makeOffer(connection);
      } else {
        util.log("onnegotiationneeded triggered when not stable. Is another connection being established?");
      }
    };
    util.log("Listening for data channel");
    pc.ondatachannel = function(evt) {
      var dc;
      util.log("Received data channel");
      dc = evt.channel;
      connection = provider.getConnection(peerId, connectionId);
      connection.initialize(dc);
    };
    util.log("Listening for remote stream");
    pc.onaddstream = function(evt) {
      var stream;
      util.log("Received remote stream");
      stream = evt.stream;
      provider.getConnection(peerId, connectionId).addStream(stream);
    };
  };
  Negotiator.cleanup = function(connection) {
    var pc;
    util.log("Cleaning up PeerConnection to " + connection.peer);
    pc = connection.pc;
    if (!!pc && (pc.readyState !== "closed" || pc.signalingState !== "closed")) {
      pc.close();
      connection.pc = null;
    }
  };
  Negotiator._makeOffer = function(connection) {
    var pc;
    pc = connection.pc;
    return pc.createOffer((function(offer) {
      util.log("Created offer.");
      if (!util.supports.sctp && connection.type === "data" && connection.reliable) {
        offer.sdp = Reliable.higherBandwidthSDP(offer.sdp);
      }
      pc.setLocalDescription(offer, (function() {
        util.log("Set localDescription: offer", "for:", connection.peer);
        connection.provider.socket.send({
          type: "OFFER",
          payload: {
            sdp: offer,
            type: connection.type,
            label: connection.label,
            connectionId: connection.id,
            reliable: connection.reliable,
            serialization: connection.serialization,
            metadata: connection.metadata,
            browser: util.browser
          },
          dst: connection.peer
        });
      }), function(err) {
        connection.provider.emitError("webrtc", err);
        util.log("Failed to setLocalDescription, ", err);
      });
    }), (function(err) {
      connection.provider.emitError("webrtc", err);
      util.log("Failed to createOffer, ", err);
    }), connection.options.constraints);
  };
  Negotiator._makeAnswer = function(connection) {
    var pc;
    pc = connection.pc;
    return pc.createAnswer((function(answer) {
      util.log("Created answer.");
      if (!util.supports.sctp && connection.type === "data" && connection.reliable) {
        answer.sdp = Reliable.higherBandwidthSDP(answer.sdp);
      }
      pc.setLocalDescription(answer, (function() {
        util.log("Set localDescription: answer", "for:", connection.peer);
        connection.provider.socket.send({
          type: "ANSWER",
          payload: {
            sdp: answer,
            type: connection.type,
            connectionId: connection.id,
            browser: util.browser
          },
          dst: connection.peer
        });
      }), function(err) {
        connection.provider.emitError("webrtc", err);
        util.log("Failed to setLocalDescription, ", err);
      });
    }), function(err) {
      connection.provider.emitError("webrtc", err);
      return util.log("Failed to create answer, ", err);
    });
  };
  Negotiator.handleSDP = function(type, connection, sdp) {
    var pc;
    sdp = new RTCSessionDescription(sdp);
    pc = connection.pc;
    util.log("Setting remote description", sdp);
    return pc.setRemoteDescription(sdp, (function() {
      util.log("Set remoteDescription:", type, "for:", connection.peer);
      if (type === "OFFER") {
        return Negotiator._makeAnswer(connection);
      }
    }), function(err) {
      connection.provider.emitError("webrtc", err);
      return util.log("Failed to setRemoteDescription, ", err);
    });
  };
  Negotiator.handleCandidate = function(connection, ice) {
    var candidate, sdpMLineIndex;
    candidate = ice.candidate;
    sdpMLineIndex = ice.sdpMLineIndex;
    connection.pc.addIceCandidate(new RTCIceCandidate({
      sdpMLineIndex: sdpMLineIndex,
      candidate: candidate
    }));
    return util.log("Added ICE candidate for:", connection.peer);
  };
  return Negotiator;
});

(function(root, factory) {
  if (typeof define === "function" && define.amd) {
    return define([], function() {
      return root.Peer = factory();
    });
  } else if (typeof exports === "object") {
    return module.exports = factory();
  } else {
    return root.Peer = factory();
  }
})(this, function() {

  /*
  A peer who can initiate connections with other peers.
   */
  var Peer;
  Peer = function(id, options) {
    if (!(this instanceof Peer)) {
      return new Peer(id, options);
    }
    EventEmitter.call(this);
    if (id && id.constructor === Object) {
      options = id;
      id = undefined;
    } else {
      if (id) {
        id = id.toString();
      }
    }
    options = util.extend({
      debug: 0,
      host: util.CLOUD_HOST,
      port: util.CLOUD_PORT,
      key: "peerjs",
      path: "/",
      token: util.randomToken(),
      config: util.defaultConfig
    }, options);
    this.options = options;
    if (options.host === "/") {
      options.host = window.location.hostname;
    }
    if (options.path[0] !== "/") {
      options.path = "/" + options.path;
    }
    if (options.path[options.path.length - 1] !== "/") {
      options.path += "/";
    }
    if (options.secure === undefined && options.host !== util.CLOUD_HOST) {
      options.secure = util.isSecure();
    }
    if (options.logFunction) {
      util.setLogFunction(options.logFunction);
    }
    util.setLogLevel(options.debug);
    if (!util.supports.audioVideo && !util.supports.data) {
      this._delayedAbort("browser-incompatible", "The current browser does not support WebRTC");
      return;
    }
    if (!util.validateId(id)) {
      this._delayedAbort("invalid-id", "ID \"" + id + "\" is invalid");
      return;
    }
    if (!util.validateKey(options.key)) {
      this._delayedAbort("invalid-key", "API KEY \"" + options.key + "\" is invalid");
      return;
    }
    if (options.secure && options.host === "0.peerjs.com") {
      this._delayedAbort("ssl-unavailable", "The cloud server currently does not support HTTPS. Please run your own PeerServer to use HTTPS.");
      return;
    }
    this.destroyed = false;
    this.disconnected = false;
    this.open = false;
    this.connections = {};
    this._lostMessages = {};
    this._initializeServerConnection();
    if (id) {
      this._initialize(id);
    } else {
      this._retrieveId();
    }
  };
  util.inherits(Peer, EventEmitter);
  Peer.prototype._initializeServerConnection = function() {
    var self;
    self = this;
    this.socket = new Socket(this.options.secure, this.options.host, this.options.port, this.options.path, this.options.key);
    this.socket.on("message", function(data) {
      self._handleMessage(data);
    });
    this.socket.on("error", function(error) {
      self._abort("socket-error", error);
    });
    this.socket.on("disconnected", function() {
      if (!self.disconnected) {
        self.emitError("network", "Lost connection to server.");
        self.disconnect();
      }
    });
    this.socket.on("close", function() {
      if (!self.disconnected) {
        self._abort("socket-closed", "Underlying socket is already closed.");
      }
    });
  };

  /*
  Get a unique ID from the server via XHR.
   */
  Peer.prototype._retrieveId = function(cb) {
    var http, protocol, queryString, self, url;
    self = this;
    http = new XMLHttpRequest();
    protocol = (this.options.secure ? "https://" : "http://");
    url = protocol + this.options.host + ":" + this.options.port + this.options.path + this.options.key + "/id";
    queryString = "?ts=" + new Date().getTime() + "" + Math.random();
    url += queryString;
    http.open("get", url, true);
    http.onerror = function(e) {
      var pathError;
      util.error("Error retrieving ID", e);
      pathError = "";
      if (self.options.path === "/" && self.options.host !== util.CLOUD_HOST) {
        pathError = " If you passed in a `path` to your self-hosted PeerServer, " + "you'll also need to pass in that same path when creating a new" + " Peer.";
      }
      self._abort("server-error", "Could not get an ID from the server." + pathError);
    };
    http.onreadystatechange = function() {
      if (http.readyState !== 4) {
        return;
      }
      if (http.status !== 200) {
        http.onerror();
        return;
      }
      self._initialize(http.responseText);
    };
    http.send(null);
  };

  /*
  Initialize a connection with the server.
   */
  Peer.prototype._initialize = function(id) {
    this.id = id;
    this.socket.start(this.id, this.options.token);
  };

  /*
  Handles messages from the server.
   */
  Peer.prototype._handleMessage = function(message) {
    var connection, connectionId, i, id, ii, messages, payload, peer, type, _results;
    type = message.type;
    payload = message.payload;
    peer = message.src;
    switch (type) {
      case "OPEN":
        this.emit("open", this.id);
        return this.open = true;
      case "ERROR":
        return this._abort("server-error", payload.msg);
      case "ID-TAKEN":
        return this._abort("unavailable-id", "ID `" + this.id + "` is taken");
      case "INVALID-KEY":
        return this._abort("invalid-key", "API KEY \"" + this.options.key + "\" is invalid");
      case "LEAVE":
        util.log("Received leave message from", peer);
        return this._cleanupPeer(peer);
      case "EXPIRE":
        return this.emitError("peer-unavailable", "Could not connect to peer " + peer);
      case "OFFER":
        connectionId = payload.connectionId;
        connection = this.getConnection(peer, connectionId);
        if (connection) {
          return util.warn("Offer received for existing Connection ID:", connectionId);
        } else {
          if (payload.type === "media") {
            connection = new MediaConnection(peer, this, {
              connectionId: connectionId,
              _payload: payload,
              metadata: payload.metadata
            });
            this._addConnection(peer, connection);
            this.emit("call", connection);
          } else if (payload.type === "data") {
            connection = new DataConnection(peer, this, {
              connectionId: connectionId,
              _payload: payload,
              metadata: payload.metadata,
              label: payload.label,
              serialization: payload.serialization,
              reliable: payload.reliable
            });
            this._addConnection(peer, connection);
            this.emit("connection", connection);
          } else {
            util.warn("Received malformed connection type:", payload.type);
            return;
          }
          messages = this._getMessages(connectionId);
          i = 0;
          ii = messages.length;
          _results = [];
          while (i < ii) {
            connection.handleMessage(messages[i]);
            _results.push(i += 1);
          }
          return _results;
        }
        break;
      default:
        if (!payload) {
          util.warn("You received a malformed message from " + peer + " of type " + type);
          return;
        }
        id = payload.connectionId;
        connection = this.getConnection(peer, id);
        if (connection && connection.pc) {
          return connection.handleMessage(message);
        } else if (id) {
          return this._storeMessage(id, message);
        } else {
          return util.warn("You received an unrecognized message:", message);
        }
    }
  };

  /*
  Stores messages without a set up connection, to be claimed later.
   */
  Peer.prototype._storeMessage = function(connectionId, message) {
    if (!this._lostMessages[connectionId]) {
      this._lostMessages[connectionId] = [];
    }
    this._lostMessages[connectionId].push(message);
  };

  /*
  Retrieve messages from lost message store
   */
  Peer.prototype._getMessages = function(connectionId) {
    var messages;
    messages = this._lostMessages[connectionId];
    if (messages) {
      delete this._lostMessages[connectionId];
      return messages;
    } else {
      return [];
    }
  };

  /*
  Returns a DataConnection to the specified peer. See documentation for a
  complete list of options.
   */
  Peer.prototype.connect = function(peer, options) {
    var connection;
    if (this.disconnected) {
      util.warn("You cannot connect to a new Peer because you called " + ".disconnect() on this Peer and ended your connection with the" + " server. You can create a new Peer to reconnect, or call reconnect" + " on this peer if you believe its ID to still be available.");
      this.emitError("disconnected", "Cannot connect to new Peer after disconnecting from server.");
      return;
    }
    connection = new DataConnection(peer, this, options);
    this._addConnection(peer, connection);
    return connection;
  };

  /*
  Returns a MediaConnection to the specified peer. See documentation for a
  complete list of options.
   */
  Peer.prototype.call = function(peer, stream, options) {
    var call;
    if (this.disconnected) {
      util.warn("You cannot connect to a new Peer because you called " + ".disconnect() on this Peer and ended your connection with the" + " server. You can create a new Peer to reconnect.");
      this.emitError("disconnected", "Cannot connect to new Peer after disconnecting from server.");
      return;
    }
    if (!stream) {
      util.error("To call a peer, you must provide a stream from your browser's `getUserMedia`.");
      return;
    }
    options = options || {};
    options._stream = stream;
    call = new MediaConnection(peer, this, options);
    this._addConnection(peer, call);
    return call;
  };

  /*
  Add a data/media connection to this peer.
   */
  Peer.prototype._addConnection = function(peer, connection) {
    if (!this.connections[peer]) {
      this.connections[peer] = [];
    }
    this.connections[peer].push(connection);
  };

  /*
  Retrieve a data/media connection for this peer.
   */
  Peer.prototype.getConnection = function(peer, id) {
    var connections, i, ii;
    connections = this.connections[peer];
    if (!connections) {
      return null;
    }
    i = 0;
    ii = connections.length;
    while (i < ii) {
      if (connections[i].id === id) {
        return connections[i];
      }
      i++;
    }
    return null;
  };
  Peer.prototype._delayedAbort = function(type, message) {
    var self;
    self = this;
    util.setZeroTimeout(function() {
      self._abort(type, message);
    });
  };

  /*
  Destroys the Peer and emits an error message.
  The Peer is not destroyed if it's in a disconnected state, in which case
  it retains its disconnected state and its existing connections.
   */
  Peer.prototype._abort = function(type, message) {
    util.error("Aborting!");
    if (!this._lastServerId) {
      this.destroy();
    } else {
      this.disconnect();
    }
    this.emitError(type, message);
  };

  /*
  Emits a typed error message.
   */
  Peer.prototype.emitError = function(type, err) {
    util.error("Error:", err);
    if (typeof err === "string") {
      err = new Error(err);
    }
    err.type = type;
    this.emit("error", err);
  };

  /*
  Destroys the Peer: closes all active connections as well as the connection
  to the server.
  Warning: The peer can no longer create or accept connections after being
  destroyed.
   */
  Peer.prototype.destroy = function() {
    if (!this.destroyed) {
      this._cleanup();
      this.disconnect();
      this.destroyed = true;
    }
  };

  /*
  Disconnects every connection on this peer.
   */
  Peer.prototype._cleanup = function() {
    var i, ii, peers;
    if (this.connections) {
      peers = Object.keys(this.connections);
      i = 0;
      ii = peers.length;
      while (i < ii) {
        this._cleanupPeer(peers[i]);
        i++;
      }
    }
    this.emit("close");
  };

  /*
  Closes all connections to this peer.
   */
  Peer.prototype._cleanupPeer = function(peer) {
    var connections, j, jj;
    connections = this.connections[peer];
    j = 0;
    jj = connections.length;
    while (j < jj) {
      connections[j].close();
      j += 1;
    }
  };

  /*
  Disconnects the Peer's connection to the PeerServer. Does not close any
  active connections.
  Warning: The peer can no longer create or accept connections after being
  disconnected. It also cannot reconnect to the server.
   */
  Peer.prototype.disconnect = function() {
    var self;
    self = this;
    util.setZeroTimeout(function() {
      if (!self.disconnected) {
        self.disconnected = true;
        self.open = false;
        if (self.socket) {
          self.socket.close();
        }
        self.emit("disconnected", self.id);
        self._lastServerId = self.id;
        self.id = null;
      }
    });
  };

  /*
  Attempts to reconnect with the same ID.
   */
  Peer.prototype.reconnect = function() {
    if (this.disconnected && !this.destroyed) {
      util.log("Attempting reconnection to server with ID " + this._lastServerId);
      this.disconnected = false;
      this._initializeServerConnection();
      this._initialize(this._lastServerId);
    } else if (this.destroyed) {
      throw new Error("This peer cannot reconnect to the server. It has already been destroyed.");
    } else if (!this.disconnected && !this.open) {
      util.error("In a hurry? We're still trying to make the initial connection!");
    } else {
      throw new Error("Peer " + this.id + " cannot reconnect because it is not disconnected from the server!");
    }
  };

  /*
  Get a list of available peer IDs. If you're running your own server, you'll
  want to set allow_discovery: true in the PeerServer options. If you're using
  the cloud server, email team@peerjs.com to get the functionality enabled for
  your key.
   */
  Peer.prototype.listAllPeers = function(cb) {
    var http, protocol, queryString, self, url;
    cb = cb || function() {};
    self = this;
    http = new XMLHttpRequest();
    protocol = (this.options.secure ? "https://" : "http://");
    url = protocol + this.options.host + ":" + this.options.port + this.options.path + this.options.key + "/peers";
    queryString = "?ts=" + new Date().getTime() + "" + Math.random();
    url += queryString;
    http.open("get", url, true);
    http.onerror = function(e) {
      self._abort("server-error", "Could not get peers from the server.");
      cb([]);
    };
    http.onreadystatechange = function() {
      var helpfulError;
      if (http.readyState !== 4) {
        return;
      }
      if (http.status === 401) {
        helpfulError = "";
        if (self.options.host !== util.CLOUD_HOST) {
          helpfulError = "It looks like you're using the cloud server. You can email " + "team@peerjs.com to enable peer listing for your API key.";
        } else {
          helpfulError = "You need to enable `allow_discovery` on your self-hosted" + " PeerServer to use this feature.";
        }
        throw new Error("It doesn't look like you have permission to list peers IDs. " + helpfulError);
      } else if (http.status !== 200) {
        cb([]);
      } else {
        cb(JSON.parse(http.responseText));
      }
    };
    http.send(null);
  };
  return Peer;
});

(function(root, factory) {
  if (typeof define === "function" && define.amd) {
    return define([], function() {
      return root.RTCIceCandidate = factory();
    });
  } else if (typeof exports === "object") {
    return module.exports = factory();
  } else {
    return root.RTCIceCandidate = factory();
  }
})(this, function() {
  return root.RTCIceCandidate || root.mozRTCIceCandidate;
});

(function(root, factory) {
  if (typeof define === "function" && define.amd) {
    return define([], function() {
      return root.RTCPeerConnection = factory();
    });
  } else if (typeof exports === "object") {
    return module.exports = factory();
  } else {
    return root.RTCPeerConnection = factory();
  }
})(this, function() {
  return root.RTCPeerConnection || root.mozRTCPeerConnection || root.webkitRTCPeerConnection;
});

(function(root, factory) {
  if (typeof define === "function" && define.amd) {
    return define([], function() {
      return root.RTCSessionDescription = factory();
    });
  } else if (typeof exports === "object") {
    return module.exports = factory();
  } else {
    return root.RTCSessionDescription = factory();
  }
})(this, function() {
  return window.RTCSessionDescription || window.mozRTCSessionDescription;
});

(function(root, factory) {
  if (typeof define === "function" && define.amd) {
    return define([], function() {
      return root.Socket = factory();
    });
  } else if (typeof exports === "object") {
    return module.exports = factory();
  } else {
    return root.Socket = factory();
  }
})(this, function() {
  var Socket;
  Socket = function(secure, host, port, path, key) {
    var httpProtocol, wsProtocol;
    if (!(this instanceof Socket)) {
      return new Socket(secure, host, port, path, key);
    }
    EventEmitter.call(this);
    this.disconnected = false;
    this._queue = [];
    httpProtocol = (secure ? "https://" : "http://");
    wsProtocol = (secure ? "wss://" : "ws://");
    this._httpUrl = httpProtocol + host + ":" + port + path + key;
    return this._wsUrl = wsProtocol + host + ":" + port + path + "peerjs?key=" + key;
  };
  util.inherits(Socket, EventEmitter);
  Socket.prototype.start = function(id, token) {
    this.id = id;
    this._httpUrl += "/" + id + "/" + token;
    this._wsUrl += "&id=" + id + "&token=" + token;
    this._startXhrStream();
    return this._startWebSocket();
  };
  Socket.prototype._startWebSocket = function(id) {
    var self;
    self = this;
    if (this._socket) {
      return;
    }
    this._socket = new WebSocket(this._wsUrl);
    this._socket.onmessage = function(event) {
      var data, e;
      try {
        data = JSON.parse(event.data);
        self.emit("message", data);
      } catch (_error) {
        e = _error;
        util.log("Invalid server message", event.data);
        return;
      }
    };
    this._socket.onclose = function(event) {
      util.log("Socket closed.");
      self.disconnected = true;
      self.emit("disconnected");
    };
    this._socket.onopen = function() {
      if (self._timeout) {
        clearTimeout(self._timeout);
        setTimeout((function() {
          self._http.abort();
          self._http = null;
        }), 5000);
      }
      self._sendQueuedMessages();
      util.log("Socket open");
    };
  };
  Socket.prototype._startXhrStream = function(n) {
    var e, self;
    try {
      self = this;
      this._http = new XMLHttpRequest();
      this._http._index = 1;
      this._http._streamIndex = n || 0;
      this._http.open("post", this._httpUrl + "/id?i=" + this._http._streamIndex, true);
      this._http.onreadystatechange = function() {
        if (this.readyState === 2 && this.old) {
          this.old.abort();
          delete this.old;
        } else if (this.readyState > 2 && this.status === 200 && this.responseText) {
          self._handleStream(this);
        } else if (this.status !== 200) {
          clearTimeout(self._timeout);
          self.emit("disconnected");
        }
      };
      this._http.send(null);
      this._setHTTPTimeout();
    } catch (_error) {
      e = _error;
      util.log("XMLHttpRequest not available; defaulting to WebSockets");
    }
  };
  Socket.prototype._handleStream = function(http) {
    var bufferedMessage, e, index, message, messages;
    messages = http.responseText.split("\n");
    if (http._buffer) {
      while (http._buffer.length > 0) {
        index = http._buffer.shift();
        bufferedMessage = messages[index];
        try {
          bufferedMessage = JSON.parse(bufferedMessage);
        } catch (_error) {
          e = _error;
          http._buffer.shift(index);
          break;
        }
        this.emit("message", bufferedMessage);
      }
    }
    message = messages[http._index];
    if (message) {
      http._index += 1;
      if (http._index === messages.length) {
        if (!http._buffer) {
          http._buffer = [];
        }
        http._buffer.push(http._index - 1);
      } else {
        try {
          message = JSON.parse(message);
        } catch (_error) {
          e = _error;
          util.log("Invalid server message", message);
          return;
        }
        this.emit("message", message);
      }
    }
  };
  Socket.prototype._setHTTPTimeout = function() {
    var self;
    self = this;
    this._timeout = setTimeout(function() {
      var old;
      old = self._http;
      if (!self._wsOpen()) {
        self._startXhrStream(old._streamIndex + 1);
        self._http.old = old;
      } else {
        old.abort();
      }
    }, 25000);
  };
  Socket.prototype._wsOpen = function() {
    return this._socket && this._socket.readyState === 1;
  };
  Socket.prototype._sendQueuedMessages = function() {
    var i, ii;
    i = 0;
    ii = this._queue.length;
    while (i < ii) {
      this.send(this._queue[i]);
      i += 1;
    }
  };
  Socket.prototype.send = function(data) {
    var http, message, url;
    if (this.disconnected) {
      return;
    }
    if (!this.id) {
      this._queue.push(data);
      return;
    }
    if (!data.type) {
      this.emit("error", "Invalid message");
      return;
    }
    message = JSON.stringify(data);
    if (this._wsOpen()) {
      this._socket.send(message);
    } else {
      http = new XMLHttpRequest();
      url = this._httpUrl + "/" + data.type.toLowerCase();
      http.open("post", url, true);
      http.setRequestHeader("Content-Type", "application/json");
      http.send(message);
    }
  };
  Socket.prototype.close = function() {
    if (!this.disconnected && this._wsOpen()) {
      this._socket.close();
      this.disconnected = true;
    }
  };
  return Socket;
});

(function(root, factory) {
  if (typeof define === "function" && define.amd) {
    return define([], function() {
      return root.util = factory();
    });
  } else if (typeof exports === "object") {
    return module.exports = factory();
  } else {
    return root.util = factory();
  }
})(this, function() {
  var dataCount, defaultConfig, util;
  defaultConfig = {
    iceServers: [
      {
        url: "stun:stun.l.google.com:19302"
      }
    ]
  };
  dataCount = 1;
  util = {
    noop: function() {},
    CLOUD_HOST: "0.peerjs.com",
    CLOUD_PORT: 9000,
    chunkedBrowsers: {
      Chrome: 1
    },
    chunkedMTU: 16300,
    logLevel: 0,
    setLogLevel: function(level) {
      var debugLevel;
      debugLevel = parseInt(level, 10);
      if (!isNaN(parseInt(level, 10))) {
        util.logLevel = debugLevel;
      } else {
        util.logLevel = (level ? 3 : 0);
      }
      util.log = util.warn = util.error = util.noop;
      if (util.logLevel > 0) {
        util.error = util._printWith("ERROR");
      }
      if (util.logLevel > 1) {
        util.warn = util._printWith("WARNING");
      }
      if (util.logLevel > 2) {
        util.log = util._print;
      }
    },
    setLogFunction: function(fn) {
      if (fn.constructor !== Function) {
        util.warn("The log function you passed in is not a function. Defaulting to regular logs.");
      } else {
        util._print = fn;
      }
    },
    _printWith: function(prefix) {
      return function() {
        var copy;
        copy = Array.prototype.slice.call(arguments_);
        copy.unshift(prefix);
        util._print.apply(util, copy);
      };
    },
    _print: function() {
      var copy, err, i, l;
      err = false;
      copy = Array.prototype.slice.call(arguments_);
      copy.unshift("PeerJS: ");
      i = 0;
      l = copy.length;
      while (i < l) {
        if (copy[i] instanceof Error) {
          copy[i] = "(" + copy[i].name + ") " + copy[i].message;
          err = true;
        }
        i++;
      }
      if (err) {
        console.error.apply(console, copy);
      } else {
        console.log.apply(console, copy);
      }
    },
    defaultConfig: defaultConfig,
    browser: (function() {
      if (window.mozRTCPeerConnection) {
        return "Firefox";
      } else if (window.webkitRTCPeerConnection) {
        return "Chrome";
      } else if (window.RTCPeerConnection) {
        return "Supported";
      } else {
        return "Unsupported";
      }
    })(),
    supports: (function() {
      var audioVideo, binaryBlob, data, dc, e, negotiationDC, negotiationPC, onnegotiationneeded, pc, reliableDC, reliablePC, sctp;
      if (typeof RTCPeerConnection === "undefined") {
        return {};
      }
      data = true;
      audioVideo = true;
      binaryBlob = false;
      sctp = false;
      onnegotiationneeded = !!window.webkitRTCPeerConnection;
      pc = void 0;
      dc = void 0;
      try {
        pc = new RTCPeerConnection(defaultConfig, {
          optional: [
            {
              RtpDataChannels: true
            }
          ]
        });
      } catch (_error) {
        e = _error;
        data = false;
        audioVideo = false;
      }
      if (data) {
        try {
          dc = pc.createDataChannel("_PEERJSTEST");
        } catch (_error) {
          e = _error;
          data = false;
        }
      }
      if (data) {
        try {
          dc.binaryType = "blob";
          binaryBlob = true;
        } catch (_error) {}
        reliablePC = new RTCPeerConnection(defaultConfig, {});
        try {
          reliableDC = reliablePC.createDataChannel("_PEERJSRELIABLETEST", {});
          sctp = reliableDC.reliable;
        } catch (_error) {}
        reliablePC.close();
      }
      if (audioVideo) {
        audioVideo = !!pc.addStream;
      }
      if (!onnegotiationneeded && data) {
        negotiationPC = new RTCPeerConnection(defaultConfig, {
          optional: [
            {
              RtpDataChannels: true
            }
          ]
        });
        negotiationPC.onnegotiationneeded = function() {
          onnegotiationneeded = true;
          if (util && util.supports) {
            util.supports.onnegotiationneeded = true;
          }
        };
        negotiationDC = negotiationPC.createDataChannel("_PEERJSNEGOTIATIONTEST");
        setTimeout((function() {
          negotiationPC.close();
        }), 1000);
      }
      if (pc) {
        pc.close();
      }
      return {
        audioVideo: audioVideo,
        data: data,
        binaryBlob: binaryBlob,
        binary: sctp,
        reliable: sctp,
        sctp: sctp,
        onnegotiationneeded: onnegotiationneeded
      };
    })(),
    validateId: function(id) {
      return !id || /^[A-Za-z0-9]+(?:[ _-][A-Za-z0-9]+)*$/.exec(id);
    },
    validateKey: function(key) {
      return !key || /^[A-Za-z0-9]+(?:[ _-][A-Za-z0-9]+)*$/.exec(key);
    },
    debug: false,
    inherits: function(ctor, superCtor) {
      ctor.super_ = superCtor;
      ctor.prototype = Object.create(superCtor.prototype, {
        constructor: {
          value: ctor,
          enumerable: false,
          writable: true,
          configurable: true
        }
      });
    },
    extend: function(dest, source) {
      var key;
      for (key in source) {
        if (source.hasOwnProperty(key)) {
          dest[key] = source[key];
        }
      }
      return dest;
    },
    pack: BinaryPack.pack,
    unpack: BinaryPack.unpack,
    log: function() {
      var copy, err, i, l;
      if (util.debug) {
        err = false;
        copy = Array.prototype.slice.call(arguments_);
        copy.unshift("PeerJS: ");
        i = 0;
        l = copy.length;
        while (i < l) {
          if (copy[i] instanceof Error) {
            copy[i] = "(" + copy[i].name + ") " + copy[i].message;
            err = true;
          }
          i++;
        }
        if (err) {
          console.error.apply(console, copy);
        } else {
          console.log.apply(console, copy);
        }
      }
    },
    setZeroTimeout: (function(global) {
      var handleMessage, messageName, setZeroTimeoutPostMessage, timeouts;
      setZeroTimeoutPostMessage = function(fn) {
        timeouts.push(fn);
        global.postMessage(messageName, "*");
      };
      handleMessage = function(event) {
        if (event.source === global && event.data === messageName) {
          if (event.stopPropagation) {
            event.stopPropagation();
          }
          if (timeouts.length) {
            timeouts.shift()();
          }
        }
      };
      timeouts = [];
      messageName = "zero-timeout-message";
      if (global.addEventListener) {
        global.addEventListener("message", handleMessage, true);
      } else {
        if (global.attachEvent) {
          global.attachEvent("onmessage", handleMessage);
        }
      }
      return setZeroTimeoutPostMessage;
    }, this),
    chunk: function(bl) {
      var b, chunk, chunks, end, index, size, start, total;
      chunks = [];
      size = bl.size;
      start = index = 0;
      total = Math.ceil(size / util.chunkedMTU);
      while (start < size) {
        end = Math.min(size, start + util.chunkedMTU);
        b = bl.slice(start, end);
        chunk = {
          __peerData: dataCount,
          n: index,
          data: b,
          total: total
        };
        chunks.push(chunk);
        start = end;
        index += 1;
      }
      dataCount += 1;
      return chunks;
    },
    blobToArrayBuffer: function(blob, cb) {
      var fr;
      fr = new FileReader();
      fr.onload = function(evt) {
        cb(evt.target.result);
      };
      fr.readAsArrayBuffer(blob);
    },
    blobToBinaryString: function(blob, cb) {
      var fr;
      fr = new FileReader();
      fr.onload = function(evt) {
        cb(evt.target.result);
      };
      fr.readAsBinaryString(blob);
    },
    binaryStringToArrayBuffer: function(binary) {
      var byteArray, i;
      byteArray = new Uint8Array(binary.length);
      i = 0;
      while (i < binary.length) {
        byteArray[i] = binary.charCodeAt(i) & 0xff;
        i++;
      }
      return byteArray.buffer;
    },
    randomToken: function() {
      return Math.random().toString(36).substr(2);
    },
    isSecure: function() {
      return location.protocol === "https:";
    }
  };
  return util;
});
