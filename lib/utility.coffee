_ = require('lodash')

class Utility

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
    { url:  "stun.l.google.com:19302" }
    { url: "stun1.l.google.com:19302" }
    { url: "stun2.l.google.com:19302" }
    { url: "stun3.l.google.com:19302" }
    { url: "stun4.l.google.com:19302" }
  ]

  # Default server connection details.
  @server: {
    host: "0.peerjs.com"
    port: 9000
  }

  # Ensure alphanumeric IDs do not begin with spaces, dashes
  # or underscores.
  @validateId: (id) ->
    /^[A-Za-z0-9]+(?:[ _-][A-Za-z0-9]+)*$/.test(id)

  # Alias for `validateId`
  @validateKey: @validateId

  # Generate a random token.
  @randomToken: ->
    Math.random().toString(36).substr(2)

  ##### Working with Blobs

  # **NOTE**: The only way to read content from a `Blob` is to
  # use a `FileReader`

  # **chunk** will split a `Blob` into chuns no more than 16,000 `bytes`
  # (16KB) by default.
  #
  # You should not try to send more than 16KB at a time via the
  # `DataChannel.send()` API. This is currently due to a limitation of
  # Chrome, is temporary and will be removed in a future update to
  # the SCTP protocol (EOR + ndata).
  #
  # Until then, you should break data into <16KB chunks and send
  # each chunk individually. Each chunk should be sent with `id`,
  # `index` and `total` values so they can be put back together
  # in order.
  @chunk: (blob, bytes = 16000) ->
    index = 0
    size  = blob.size
    total = Math.ceil(size / bytes)
    id    = @randomToken()

    for byte in [0...size] by bytes
      id:    id
      index: index
      total: total
      slice: blob.slice(byte, byte + bytes)

  # **blobToArrayBuffer** will reads the content of a `Blob`, and return a
  # typed array to the `callback` function as the first argument.
  @blobToArrayBuffer: (blob, callback) ->
    reader = new FileReader()

    reader.addEventListener "loadend", ->
      callback(reader.result) if _.isFunction(callback)

    reader.readAsArrayBuffer(blob)

  # **blobToBinaryString** will reads the content of a `Blob`, and return a
  # string to the `callback` function as the first argument.
  @blobToBinaryString: (blob, callback) ->
    reader = new FileReader()

    reader.addEventListener "loadend", ->
      callback(reader.result) if _.isFunction(callback)

    reader.readAsBinaryString(blob)

  # **binaryStringToArrayBuffer** converts a `String` to a typed `Array`.
  @binaryStringToArrayBuffer: (string) ->
    buffer = new ArrayBuffer(string.length * 2) # 2 bytes for each character
    bufferView = new Uint16Array(buffer)

    for i in string.length
      bufferView[i] = string.charCodeAt(i)

    return buffer

# Utility.Log
# ---
# The `Utility.Log` class ensures consistent logging by setting
# and adhearing to appropriate log levels.
class Utility.Log

  @levels:
    SILENT: 5
    ERROR:  4
    WARN:   3
    INFO:   2
    DEBUG:  1
    TRACE:  0

  # Default log level is **SILENT** (no output to the console)
  @level: Log.levels.SILENT

  constructor: (level) ->
    @set(level || Log.levels.SILENT)

  find: (key) ->
    Log.levels[key] or throw new Error("Invalid key: #{key}")

  # Sets the log level, and instantiates the allowed
  # error functions. If the key passed doesn't match a
  # log level in `Log.levels`, an `Error` is thrown.
  set: (key) ->
    Log.level = @find(key)

    @error = @warn = @info = @debug = @trace = _.noop

    for name, val in Log.levels
      if val isnt 0 and val >= Log.level
        @[key.toLowerCase()] = @log(key)

  # Internal method which prefixes the log output by the requested
  # log key.
  #
  # *Example console output:*
  #
  #     > new Log().debug(1,2,3)
  #     # PeerJS: [DEBUG] 1 2 3
  #
  log: (key, logs...) ->
    if @find(key) >= Log.level
      prefixes = ["PeerJS:", "[#{key}]"]

      for log in logs
        if log instanceof Error
          log = "(#{log.name}) #{log.message}"

      console[name.toLowerCase()].apply(console, logs)

# Export to Node.JS, if available, or fall back to `window`
root = exports ? window

root.Utility = Utility
