## PeerCoffee: WebRTC + Pusher + Coffee [![Build Status](https://travis-ci.org/voxxit/peercoffee.svg?branch=master)](https://travis-ci.org/voxxit/peercoffee) [![Built with Grunt](https://cdn.gruntjs.com/builtwith.png)](http://gruntjs.com/)

Based on the wonderful [PeerJS](http://peerjs.com) library, **PeerCoffee** is a fully-tested library baked with CoffeeScript which offers a developer-friendly API for WebRTC, using [Pusher](http://pusher.com) as the signaling server.

### Getting Started

Use [bower](http://bower.io) to install the JavaScript library:

    $ bower install peercoffee

Then, load the script onto your site, and add a peer for the local user:

```coffee
localPeer = new PeerCoffee.Peer()
```

At this point, the possibilities are endless! Perhaps you instruct the users to give the URL they are on to another user.

```coffee
localPeer.withMedia (localStream) ->

  call = localPeer.call('remote-peer')

  call.on 'stream', (remoteStream) ->
    # Do something with the stream
    # e.g. add it to a <video> element
```

Peers can also listen for calls:

```coffee
localPeer.on 'call', (call) ->

  # Get the local stream first
  localPeer.withMedia (localStream) ->

    # Answer the call; sending back a local stream
    call.answer(localStream)

    # Then wait for the remote stream to start
    call.on 'stream', (remoteStream) ->
      # Do something with the stream
      # e.g. add it to a <video> element
```

### Documentation

Find annotated documentation for the PeerCoffee API here:

- [`PeerCoffee.DataConnection`](http://voxxit.com/peercoffee/peer.html)
- [`PeerCoffee.MediaConnection`](http://voxxit.com/peercoffee/peer.html)
- [`PeerCoffee.Negotiator`](http://voxxit.com/peercoffee/peer.html)
- [`PeerCoffee.Peer`](http://voxxit.com/peercoffee/peer.html)
- [`PeerCoffee.Socket`](http://voxxit.com/peercoffee/socket.html)
- [`PeerCoffee.util`](http://voxxit.com/peercoffee/util.html)
