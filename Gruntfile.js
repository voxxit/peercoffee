module.exports = function(grunt) {

  var banner = '/*! peerjs build: <%= pkg.version %> - Copyright(c) 2013 Michelle Bu <michelle@michellebu.com> */\n'

  grunt.initConfig({
    pkg: grunt.file.readJSON('package.json'),
    concat: {
      options: {
        banner: banner
      },
      dist: {
        // the files to concatenate
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
        ],
        // the location of the resulting JS file
        dest: 'dist/peer.js'
      }
    },
    uglify: {
      options: {
        banner: banner
      },
      dist: {
        files: {
          'dist/peer.min.js': ['<%= concat.dist.dest %>']
        }
      }
    },
    mocha: {
      test: {
        src: ['test/**/*.html'],
        dest: "test/results.html"
      },
    },
    watch: {
      files: ['<%= jshint.files %>'],
      tasks: ['jshint', 'qunit']
    }
  });

  require('load-grunt-tasks')(grunt);

  grunt.registerTask('test', ['mocha']);
  grunt.registerTask('default', ['concat', 'uglify']);

};
