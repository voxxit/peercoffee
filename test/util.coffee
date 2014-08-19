expect = require("chai").expect
util   = require("../lib/util.coffee").util

describe "util", ->

  describe ".inherits", ->

    it "should make functions inherit properly", ->
      class Child

      class Parent
        test: -> 5

      util.inherits(Child, Parent)

      expect(new Child()).to.be.a(Parent)
      expect(new Child().test()).to.be.equal(5)

  # extend overwrites keys if already exists
  # leaves existing keys alone otherwise
  #
  describe ".extend", ->

    it "should copy the properties of b to a", ->
      a = { a: 1, b: 2, c: 3, d: 4 }
      b = { d: 2 }

      util.extend(b, a)

      expect(b).to.eql(a)
      expect(b.d).to.be.equal(4)

      b = { z: 2 }

      util.extend(b, a)

      expect(b.z).to.be.equal(2)

  describe ".pack", ->

    it "should be BinaryPack's `pack` function", ->
      expect(util.pack).to.be.equal(BinaryPack.pack)

  describe ".unpack", ->

    it "should be BinaryPack's `unpack` function", ->
      expect(util.unpack).to.be.equal(BinaryPack.unpack)

  # For Firefox
  describe ".log", ->

    it "should return the normal `console.log` output by default", ->
      expect(util.debug).to.be.false # by default
      expect(util.log('hi')).to.equal('hi')

    it "should log with the PeerJS: prefix when `debug` is true", ->
      util.debug = true

      expect(util.log('hi')).to.equal('PeerJS: hi')

      util.debug = false  # Back to normal

  describe ".setZeroTimeout", ->

    it "should call the function after a 0s timeout", (done) ->
      isdone = false

      util.setZeroTimeout ->
        done() if isdone is true

      isdone = true

  describe ".blobToArrayBuffer", ->

    it "should convert a Blob to an ArrayBuffer", (done) ->

      blob = new Blob(['hi'])

      util.blobToArrayBuffer blob, (result) ->

        expect(result.byteLength).to.be.equal(2)
        expect(result.slice).to.be.a('function')
        expect(result instanceof ArrayBuffer).to.be.true

        done()

  describe ".blobToBinaryString", ->

    it "should convert a Blob to a binary string", (done) ->

      blob = new Blob(['hi'])

      util.blobToBinaryString blob, (result) ->

        expect(result).to.equal('hi')

        done()

  describe ".binaryStringToArrayBuffer", ->

    it "should convert a binary string to an ArrayBuffer", ->

      ba = util.binaryStringToArrayBuffer('\0\0')

      expect(ba.byteLength).to.be.equal(2)
      expect(ba.slice).to.be.a('function')
      expect(ba instanceof ArrayBuffer).to.be.true

  describe ".randomToken", ->

    it "should never return a random string over 10000 attempts", ->
      i = 0
      tokens = {}

      while i++ < 10000
        p = util.randomToken()

        if !tokens[p] then tokens[p] = 1 else throw new Error("Duplicate token")
