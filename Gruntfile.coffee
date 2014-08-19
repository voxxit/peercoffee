module.exports = (grunt) ->

  banner = '/*! peerjs build: <%= pkg.version %> */\n'

  grunt.initConfig

    pkg: grunt.file.readJSON('package.json')

    docco:
      lib:
        src: ['lib/**/*.coffee']
        options:
          output: 'docs/'

    modernizr:
      dist:
        devFile: "remote"
        outputFile: "deps/modernizr.js"
        extra:
          shiv: false
          printshiv: false
          load: false
          mq: false
          cssclasses: false
        extensibility:
          addtest: false
          prefixed: true
          teststyles: false
          testprops: false
          testallprops: false
          hasevents: false
          prefixes: true
          domprefixes: true
        uglify: false
        tests: ['blob_constructor', 'websockets_binary', 'getusermedia']
        parseFiles: true
        files:
          src: ["lib/**/*.coffee"]
        matchCommunityTests: true
        customTests: [
          "lib/modernizr/*.js"
        ]
    concat:
      options:
        banner: banner
      dist:
        src: [
          'deps/js-binarypack/lib/bufferbuilder.js',
          'deps/js-binarypack/lib/binarypack.js',
          'deps/EventEmitter/EventEmitter.js',
          'deps/reliable/lib/reliable.js',
          'lib/adapter.js',
          'lib/util.js',
          'lib/peer.js',
          'lib/dataconnection.js',
          'lib/mediaconnection.js',
          'lib/negotiator.js',
          'lib/socket.js'
        ]
        dest: 'dist/peer.js'

    uglify:
      options:
        banner: banner
      dist:
        files:
          'dist/peer.min.js': ['<%= concat.dist.dest %>']

    mocha:
      test:
        src: ['test/**/*.html']
        dest: "test/results.html"

    coffeelint:
      app: ['<%= docco.lib.src %>']
      options:
        max_line_length:
          value: 120

    watch:
      src:
        files: ['<%= docco.lib.src %>']
        tasks: ['coffeelint', 'docco']
      configFiles:
        files: [ 'Gruntfile.js', 'config/*.js' ]
        options:
          reload: true

  require('load-grunt-tasks')(grunt)

  grunt.registerTask('test', ['mocha'])
  grunt.registerTask('default', ['concat', 'uglify'])
