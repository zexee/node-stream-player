Speaker = require('speaker')
lame = require('lame')
request = require('request')
events = require('events')
fs = require('fs')

# http://stackoverflow.com/a/646643
String::startsWith ?= (s) -> @slice(0, s.length) == s
String::endsWith   ?= (s) -> s == '' or @slice(-s.length) == s

audioOptions = {
  channels: 2,
  bitDepth: 16,
  sampleRate: 44100,
  mode: lame.STEREO
}

self = null

class StreamPlayer extends events.EventEmitter

  constructor: () ->
    super()
    events.EventEmitter.call(this)
    self = this
    @queue = []
    @trackInfo = []
    @currentSong = null
    @playing = false
    @startTime = 0
    @speaker = null
    @decoder = null


  # Play the next song in the queue if it exists
  play: () ->
    if @currentSong != null
      @resume()
    else if @queue.length > 0 && !@playing
      @getStream(@queue[0], @playStream)
      @playing = true
      @queue.shift()
      @currentSong = self.trackInfo.shift()
    else if @playing
      return new Error('A song is already playing.')
    else
      return new Error('The queue is empty.')

  # Stop playing
  stop: () ->
    @playing = false
    @currentSong = null
    @speaker.removeAllListeners 'close'
    @speaker.end()

  # Pause the current playing audio stream
  pause: () ->
    @playing = false
    @speaker.removeAllListeners 'close'
    @speaker.end()

  # Pipe the decoded audio stream back to a speaker
  resume: () ->
    @speaker = new Speaker(audioOptions)
    @decoder.pipe(@speaker)
    @playing = true
    @speaker.once 'close', () ->
      loadNextSong()

  # Remove a song with the given id metadata attribute
  remove: (id) ->
    index = @trackInfo.map( (info) -> return info.id ).indexOf(parseInt(id, 10))
    @trackInfo.splice(index, 1)
    @queue.splice(index, 1)


  # Add a song and metadata to the queue
  add: (url, track) ->
    @queue.push(url)
    @trackInfo.push(track)
    @emit('song added', url, track)

  # Returns the metadata for the song that is currently playing
  nowPlaying: () ->
    if @playing
      return {track: @currentSong, timestamp: @startTime}
    else
      throw new Error('No song is currently playing.')

  # Returns if there is a song currently playing
  isPlaying: () ->
    return @playing

  # Returns the metadata for the songs that are in the queue
  getQueue: () ->
    return @trackInfo

  # Get the audio stream
  getStream: (url, callback) ->
    if url.startsWith('http')
      request.get(url).on 'response', (res) ->
        if res.headers['content-type'] == 'audio/mpeg'
          callback(res)
        else
          self.emit('invalid url', url)
          loadNextSong()
    else
      stream = fs.createReadStream(url)
      callback(stream)


  # Decode the stream and pipe it to our speakers
  playStream: (stream) ->
    self.decoder = new lame.Decoder()
    self.speaker = new Speaker(audioOptions)
    stream.pipe(self.decoder).once 'format', () ->
      self.decoder.pipe(self.speaker)
      self.startTime = Date.now();
      self.emit('play start', self.currentSong)
      self.speaker.once 'close', () ->
        loadNextSong()


# Load the next song in the queue if there is one
loadNextSong = () ->
  self.emit('play end', self.currentSong)
  self.currentSong = null
  self.playing = false
  self.play()


module.exports = StreamPlayer
