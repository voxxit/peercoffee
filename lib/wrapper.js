// Example from: http://backbonejs.org/docs/backbone.html

(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    define([
      '../deps/js-binarypack/lib/bufferbuilder',
      '../deps/js-binarypack/lib/binarypack',
      '../deps/EventEmitter/EventEmitter',
      '../deps/reliable/lib/reliable',
      'shims/ice_candidate',
      'shims/peer_connection',
      'shims/session_description',
      'util',
      'peer',
      'dataconnection',
      'mediaconnection',
      'negotiator',
      'socket',
      'exports'
    ], function(..., exports) {
      root.Peer = factory(root, exports, ...);
    });
  } else if (typeof exports !== 'undefined') {
    var ... = require("...");

    factory(root, exports, ...)
  } else {
    root.Peer = factory(root, {}, root._, root.jQuery);
  }
}(this, function (root, Peer, ...) {

}));
