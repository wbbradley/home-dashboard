log = (level, msg) ->
  if typeof console != 'undefined'
    console.log "home-dashboard : #{level} : #{msg}"

Messages = new Meteor.Collection 'messages'
Rooms = new Meteor.Collection 'rooms'

WeatherReports = new Meteor.Collection 'weather_reports'

findRoom = (name) ->
  if not name
    throw new Error 'No name passed to findRoom'
  room = Rooms.findOne {lcname: (name or '').toLowerCase()}, {sort: {timestamp: -1}}
  return room

if Meteor.isClient
  # Accounts.ui.config
  #   requestPermissions:
  #     facebook: ['rsvp_event']

  dumpColl = (coll) ->
    coll.find().forEach (item) ->
      console.log item

  append_time_unit = (diff, unit_name, unit, ret) ->
    if diff > unit
      units = Math.floor diff / unit
      diff -= units * unit
      ret += "#{units} #{unit_name}"
      if units isnt 1
        ret += 's'
    if diff > 0 and units > 0
      ret += ', '
    else if units > 0
      ret += ' ago'
    [diff, ret]

  formatDate = (date) ->
    minute = 60
    hour = 60 * minute
    day = 24 * hour
    week = 7 * day
    moon = 28 * day
    diff = Math.round (Date.now() - date) / 1000.0
    orig_diff = diff
    ret = ''
    if diff >= 60
      diff = diff - (diff % 60)
      [diff, ret] = append_time_unit diff, 'moon', moon, ret
      [diff, ret] = append_time_unit diff, 'week', week, ret
      [diff, ret] = append_time_unit diff, 'day', day, ret
      [diff, ret] = append_time_unit diff, 'hour', hour, ret
      [diff, ret] = append_time_unit diff, 'minute', minute, ret
    else
      ret = 'just now'
    ret

  Template.message.helpers
    'date-render': (timestamp) ->
      formatDate(timestamp)

  Template.message.helpers
    getAuthorImage: (authorId) ->
      author = Meteor.users.findOne {_id:authorId}
      unknown = "http://b.vimeocdn.com/ps/346/445/3464459_300.jpg"
      if author
        if author.services.twitter
          return author.services.twitter.profile_image_url.replace('_normal', '') or unknown
        else if author.services.google
          return author.services.google.picture or unknown
        else if author.services.facebook
          return "http://graph.facebook.com/#{author.services.facebook.id}/picture?type=large"
      return unknown

    say: (msg) ->
      # $.say msg
      msg


  Template['weather-report'].weather = ->
    WeatherReports.findOne {}, {sort: {local_epoch: -1}}

  Template.messages.roomName = ->
    room = Rooms.findOne {}, {sort: {timestamp: -1}}
    if not room
      return 'VOID'
    if room.name is 'lobby'
      return 'lobby'
    else
      return "#{room.name}"

  Template.messages.messages = ->
    currentRoom = Rooms.findOne {}, {sort: {timestamp: -1}}
    if not currentRoom
      return []
    Messages.find {roomId: currentRoom._id}, {sort: {timestamp: -1}}

  Template.room.room = ->
    Rooms.findOne {}, {sort: {timestamp: -1}}

  Template.room.roomName = ->
    room = Rooms.findOne {}, {sort: {timestamp: -1}}
    if not room
      return 'VOID'
    if room.lcname is 'lobby'
      return 'lobby'
    else
      return "#{room.name} room"

  @switchToRoom = (roomName) ->
    room = findRoom roomName
    if room
      room.timestamp = Date.now()
      Rooms.update room._id, room
    else
      Rooms.insert
        name: roomName
        lcname: roomName.toLowerCase()
        timestamp: Date.now()

  captureAndSendMessage = ->
    msg = $('input[name="new-message"]').val()
    $('input[name="new-message"]').val('')
    if msg
      log 'info', msg

      currentRoom = Rooms.findOne {}, {sort: {timestamp: -1}}

      if msg[0] is '/'
        roomIndex = msg.indexOf('/room ')
        if roomIndex >= 0
          roomName = msg.substr(roomIndex + 6)
          switchToRoom roomName

        imageIndex = msg.indexOf('/image ')
        if imageIndex >= 0
          Messages.insert
            imageUrl: msg.substr(imageIndex + 7)
            timestamp: Date.now()
            authorId: Meteor.user()._id
            roomId: currentRoom._id

        youtubeIndex = msg.indexOf('/youtube ')
        if youtubeIndex >= 0
          Messages.insert
            youtube: encodeURIComponent(msg.substr(youtubeIndex + 9))
            timestamp: Date.now()
            authorId: Meteor.user()._id
            roomId: currentRoom._id
      else
        Messages.insert
          msg: msg
          timestamp: Date.now()
          author: Meteor.user()._id
          roomId: currentRoom._id

  Template['send-message'].events
    'keypress input[name="new-message"]': (event) ->
      if event.which is 13
        captureAndSendMessage()
        return false
      return
    'click input[name=send]' : ->
      captureAndSendMessage()
      

if Meteor.isServer
  collectWeatherReport = ->
    # http://www.wunderground.com/weather/api/d/docs?d=data/conditions
    weather_api_url = 'http://api.wunderground.com/api/8389a57897d1480d/conditions/q/CA/San_Francisco.json'
    Meteor.http.get weather_api_url, (error, result) ->
      if result isnt null
        WeatherReports.insert result.data.current_observation, (obj, _id) ->
          log 'info', 'collected weather data'
          WeatherReports.remove _id: $ne: _id

  Meteor.startup ->
    console.log 'Starting Fort Borilliam'
    collectWeatherReport()
    Meteor.setInterval collectWeatherReport, 5 * 60 * 1000

    lobby = findRoom 'lobby'
    if lobby
      lobbyId = lobby._id
    else
      lobbyId = Rooms.insert
        name: 'lobby'
        lcname: 'lobby'
        timestamp: Date.now()

    Rooms.find().forEach (room) ->
      Rooms.update room._id, room, (error, _id) ->
        Messages.find({room:room.lcname}).forEach (message) ->
          message.roomId = _id
          log 'info', "message _id = #{message.roomId}"
          delete message.room
          message.authorId = message.author._id
          delete message.author
          Messages.update message._id, message

    Messages.find().forEach (message) ->
      message.authorId = message.author._id
      if not message.room and message.roomId is null
        message.roomId = lobbyId
      Messages.update message._id, message


@Rooms = Rooms
@Messages = Messages
@WeatherReports = WeatherReports
@formatDate = formatDate
@dumpColl = dumpColl
