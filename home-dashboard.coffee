log = (level, msg) ->
  if typeof console != 'undefined'
    console.log "home-dashboard : #{level} : #{msg}"

Messages = new Meteor.Collection 'messages'
Rooms = new Meteor.Collection 'rooms'

WeatherReports = new Meteor.Collection 'weather_reports'


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
    getAuthorImage: (author) ->
      if author.services.twitter
        return author.services.twitter.profile_image_url.replace('_normal', '')
      else if author.services.google
        return author.services.google.picture
      else if author.services.facebook
        return "http://graph.facebook.com/#{author.services.facebook.id}/picture?type=large"
      else
        throw new Error "no author image"

    say: (msg) ->
      $.say msg
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
      currentRoom =
        name: 'lobby'
    roomName = currentRoom.name
    console.log "Looking for messages in #{roomName}"
    Messages.find {room: roomName}, {sort: {timestamp: -1}}

  Template.room.room = ->
    Rooms.findOne {}, {sort: {timestamp: -1}}

  Template.room.roomName = ->
    room = Rooms.findOne {}, {sort: {timestamp: -1}}
    if not room
      return 'VOID'
    if room.name is 'lobby'
      return 'lobby'
    else
      return "#{room.name} room"

  captureAndSendMessage = ->
    msg = $('input[name="new-message"]').val()
    $('input[name="new-message"]').val('')
    if msg
      log 'info', msg

      currentRoom = Rooms.findOne {}, {sort: {timestamp: -1}}
      if not currentRoom
        currentRoom =
          name: 'lobby'
      roomName = currentRoom.name

      if msg[0] is '/'
        roomIndex = msg.indexOf('/room ')
        if roomIndex >= 0
          room =
            name: msg.substr(roomIndex + 6)
            timestamp: Date.now()

          Rooms.insert room, (obj, _id) ->
            if typeof obj is 'undefined'
              log 'info', "room logged '#{_id}'"
            else
              log 'warning', 'error inserting a new room'
        imageIndex = msg.indexOf('/image ')
        if imageIndex >= 0
          image =
            imageUrl: msg.substr(imageIndex + 7)
            timestamp: Date.now()
            author: Meteor.user()
            room: roomName

          Messages.insert image
        youtubeIndex = msg.indexOf('/youtube ')
        if youtubeIndex >= 0
          youtube =
            youtube: encodeURIComponent(msg.substr(youtubeIndex + 9))
            timestamp: Date.now()
            author: Meteor.user()
            room: roomName

          Messages.insert youtube
      else
        message =
          msg: msg
          timestamp: Date.now()
          author: Meteor.user()
          room: roomName
        Messages.insert message, (obj, _id) ->
          if typeof obj is 'undefined'
            log 'info', "message logged '#{_id}'"
          else
            log 'warning', 'error inserting a new message'
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
          console.log 'info', 'collected weather data'
          WeatherReports.remove _id: $ne: _id

  Meteor.startup ->
    console.log 'Starting Fort Borilliam'
    collectWeatherReport()
    Meteor.setInterval collectWeatherReport, 5 * 60 * 1000
    lobby = Rooms.findOne {name: 'lobby'}
    if not lobby
      lobby =
        name: 'lobby'
        timestamp: Date.now()
      Rooms.insert lobby, (obj, _id) ->
        if typeof obj is 'undefined'
          log 'info', "room logged '#{_id}'"
        else
          log 'warning', 'error inserting a new room'

@Rooms = Rooms
@Messages = Messages
@WeatherReports = WeatherReports
@formatDate = formatDate
@dumpColl = dumpColl
