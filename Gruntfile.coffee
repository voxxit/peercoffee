module.exports = (grunt) ->

  banner = '/*! peerjs build: <%= pkg.version %> */\n'

  grunt.initConfig

    pkg: grunt.file.readJSON('package.json')

    docco:
      lib:
        src: ['lib/**/*.coffee']
        options:
          output: 'docs/'

    browserify:
      dist:
        files:
          'dist/peercoffee.js': ['lib/**/*.coffee']
        options:
          transform: ['coffeeify']
          alias: [
            './lib/util.coffee:util'
            './lib/negotiator.coffee:negotiator'
            './deps/reliable/dist/reliable:reliable'
            './lib/shims/iceCandidate.coffee:ice-candidate'
            './lib/shims/peerConnection.coffee:peer-connection'
            './lib/shims/sessionDescription.coffee:session-description'
            './lib/socket.coffee:socket'
            './lib/peer.coffee:peer'
            './lib/dataConnection.coffee:data-connection'
            './lib/mediaConnection.coffee:media-connection'
            './deps/js-binarypack/dist/binarypack.js:binarypack'
          ]

    concat:
      options:
        banner: banner
      vendor:
        src: [
          'deps/js-binarypack/lib/bufferbuilder.js',
          'deps/js-binarypack/lib/binarypack.js',
          'deps/EventEmitter/EventEmitter.js',
          'deps/reliable/lib/reliable.js'
        ]
        dest: 'dist/peercoffee.vendor.js'
      dist:
        src: ['dist/peercoffee.vendor.js', 'dist/peercoffee.src.js']
        dest: 'dist/peercoffee.js'

    coffee:
      options:
        bare: true
      dist:
        files:
          'dist/peercoffee.src.js': ['lib/**/*.coffee']
      test:
        options:
          join: false
        expand: true
        cwd: 'lib/'
        src: ['**/*.coffee']
        dest: 'test/lib'
        ext: '.js'

    uglify:
      options:
        banner: banner
      dist:
        files:
          'dist/peercoffee.min.js': ['dist/peercoffee.js']

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

  grunt.registerTask('build', ['concat:vendor', 'coffee:dist', 'concat:dist', 'uglify'])
  grunt.registerTask('build:test', ['coffee:test'])

  grunt.registerTask('test', ['mocha'])
  grunt.registerTask('default', ['concat:vendor', 'coffee', 'concat:dist', 'uglify'])
