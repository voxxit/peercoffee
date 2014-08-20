describe "adapter", ->

  it "sets RTCPeerConnection", ->
    expect(RTCPeerConnection).to.be.a "function"

  it "sets RTCSessionDescription", ->
    expect(RTCSessionDescription).to.be.a "function"
