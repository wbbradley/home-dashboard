log = (level, msg) ->
  if typeof console != 'undefined'
    console.log "home-dashboard : #{level} : #{msg}"

Messages = new Meteor.Collection 'messages'
Rooms = new Meteor.Collection 'rooms'
Items = new Meteor.Collection 'items'
WeatherReports = new Meteor.Collection 'weather_reports'
Globals = new Meteor.Collection 'globals'

subscribeList =
  'users': Meteor.users
  'messages': Messages
  'rooms': Rooms
  'items': Items
  'weather_reports': WeatherReports
  'globals': Globals

@getGlobal = (name, _default) ->
  _default or= null
  global = Globals.findOne {name: name}
  if global
    return global.value
  else
    if typeof(_default) is 'function'
      _default = _default()
    return _default

@upsertGlobal = (name, value) ->
  console.log "globals - upserting #{name}"
  console.log value
  global = Globals.findOne {name: name}
  if global
    Globals.update {_id: global._id},
      $set:
        value: _.extend global.value or {}, value
        timestamp: Date.now()
  else
    Globals.insert
      name: name
      value: value
      timestamp: Date.now()
    return
  
findThing = (things, name) ->
  if not name
    throw new Error 'No name passed to findRoom'
  thing = things.findOne {lcname: (name or '').toLowerCase()}, {sort: {timestamp: -1}}
  return thing

findRoom = (name) ->
  findThing Rooms, name
findItem = (name) ->
  findThing Items, name

##################################################################
if Meteor.isClient
  document.title = Meteor.settings.public.title

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

  makeMeme = (_id) ->
    Messages.update {_id: _id},
      $set:
        meme: true
        memeTitle: 'title'
        memeSubtitle: 'subtitle'

  Template.body.helpers
    background: ->
      (@getGlobal 'background') or ''
    messages_ready: ->
      subscriptions.messages.ready()

  Template['user-item'].helpers
    ifMine: (context, options) ->
      if Meteor.user()?._id is @holderId
        return options.fn @
      else
        return options.inverse @

  Template['user-items'].helpers
    items: ->
      console.log "Fetching items for user #{@_id}"
      Items.find {holderId: @_id}, {sort: {timestamp: -1}}

  Template.message.helpers
    'date-render': (timestamp) ->
      formatDate(timestamp)

  Template.message.author = ->
      Meteor.users.findOne {_id:@authorId}

  Template.message.events
    'click .delete-btn': () ->
      Messages.update {_id: @_id},
        $set: {deleted: true}
    'click .meme-btn': () ->
      makeMeme @_id
    'click .love-btn': () ->
      if Meteor.user()?._id?
        log 'info', "#{Meteor.user().profile.name} liked a post"
        Messages.update {_id: @_id},
          $addToSet: {userLoveIds: Meteor.user()._id}

  @getUserImage  = (authorId) ->
    author = Meteor.users.findOne {_id:authorId}
    unknown = "http://b.vimeocdn.com/ps/346/445/3464459_300.jpg"
    if author?.services?
      if author.services.twitter
        return author.services.twitter.profile_image_url.replace('_normal', '') or unknown
      else if author.services.google
        return author.services.google.picture or unknown
      else if author.services.facebook
        return "http://graph.facebook.com/#{author.services.facebook.id}/picture?type=large"
    return unknown

  Template.message.helpers
    ifNotLoved: (context, options) ->
      userLoveIds = @['userLoveIds'] or []
      if userLoveIds.indexOf(Meteor.user()._id) is -1
        return options.fn @
      else
        return options.inverse @
    ifOwner: (context, options) ->
      if Meteor.user()?._id is @authorId
        return options.fn @
      else
        return options.inverse @
    loveLoop: (context, options) ->
      count = @userLoveIds?.length or 0
      if count
        ret = "";
        while count > 0
          ret += options.fn @
          --count
        return ret
      else
        return options.inverse @

    getAuthorImage: (authorId) ->
      getUserImage authorId

    say: (msg) ->
      # $.say msg
      msg


  Template['weather-report'].weather = ->
    WeatherReports.findOne {}, {sort: {local_epoch: -1}}

  Template.messages.helpers
    eachItem: (context, options) ->
      currentRoom = Rooms.findOne {}, {sort: {timestamp: -1}}
      if not currentRoom?._id?
        return options.inverse @
      items = Items.find {roomId: currentRoom._id}, {sort: {timestamp: 1}}

      if items.count()
        ret = "Items in this room: ["
        sep = ""
        items.forEach (item) ->
          ret += sep
          ret += options.fn item
          sep = " | "
        ret += ']'
      else
        ret = options.inverse @
      return ret

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
    Messages.find {roomId: currentRoom._id, deleted: null},
      {sort: {timestamp: -1}}

  Template['user-items'].events
    'click .drop-btn': () ->
      placeItem @name

  Template.items.events
    'click .take-btn': () ->
      takeItem @name

  Template.items.items = ->
    currentRoom = Rooms.findOne {}, {sort: {timestamp: -1}}
    if not currentRoom
      return []
    Items.find {roomId: currentRoom._id},
      {sort: {timestamp: -1}}

  Template.users.users = ->
    Meteor.users.find {}, {sort: {'profile.name': 1}}

  Template.user.imageUrl = ->
    getUserImage @_id

  Template.currentUserImage.imageUrl = ->
    if Meteor.user()
      getUserImage Meteor.user()._id
    else
      ''

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

  @balanceText = (event) ->
    $(event.target).parent().textfill
      maxFontPixels: 80
      maxWidth: $(event.target).parents('.meme-container').width()

  @updateMeme = (_id) ->
    title = $("#meme-#{_id}-title")[0]?.innerHTML or ''
    subtitle = $("#meme-#{_id}-subtitle")[0]?.innerHTML or ''
      
    Messages.update {_id: _id},
      $set:
        memeTitle: title
        memeSubtitle: subtitle


  Template.memeDisplay.rendered = Template.memificator.rendered = ->
    $firstNode = $(@firstNode)
    maxWidth = $firstNode.width()
    $firstNode.find('.meme-text').each ->
      $(@).parent().textfill
        maxFontPixels: 80
        maxWidth: maxWidth
    return

  Template.memificator.events
    'keyup .meme-text': @balanceText
    'blur .meme-text': (event) -> window.updateMeme $(event.target).data('msg-id')
      
  @getItemImage = (itemId) ->
    item = Items.findOne {_id: itemId}
    if not item
      return
    imageUrl = window.prompt "Enter an image url for #{item.name}:"
    console.log imageUrl
    if /^http/.test imageUrl
      Items.update {_id: itemId},
        $set: {imageUrl: imageUrl}
    return

  @switchToRoom = (roomName) ->
    room = findRoom roomName
    if room
      Rooms.update {_id: room._id},
        $set: {timestamp: Date.now()}
    else
      Rooms.insert
        name: roomName
        lcname: roomName.toLowerCase()
        timestamp: Date.now()

  @takeItem = (itemName, currentRoom) ->
    if not currentRoom
      currentRoom = Rooms.findOne {}, {sort: {timestamp: -1}}
    item = findItem itemName
    if item
      if item.roomId is currentRoom._id
        if typeof item.holderId isnt 'string'
          if item.creatorId isnt Meteor.user()._id
            Items.update {_id: item._id},
              $set:
                holderId: Meteor.user()._id
                roomId: null
          else
            window.alert "You cannot hold your own creations."
        else
          window.alert "The #{item.name} already has a holder."
      else
        window.alert "The #{item.name} is not in this room."
    else
      window.alert "There is no such thing as the #{item.name}. Are you not familiar with /place?"
      

  @placeItem = (itemName, room) ->
    room or= Rooms.findOne {}, {sort: {timestamp: -1}}
    item = findItem itemName
    if item
      if item.holderId is Meteor.user()._id
        Items.update {_id: item._id},
          $set:
            holderId: null
            roomId: room._id
      else
        window.alert "You are not holding the #{item.name}"
    else
      Items.insert
        name: itemName
        lcname: itemName.toLowerCase()
        timestamp: Date.now()
        roomId: room._id
        creatorId: Meteor.user()._id
        holderId: null

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

        placeItemIndex = msg.indexOf('/place ')
        if placeItemIndex >= 0
          placeItemName = msg.substr(placeItemIndex + 7)
          placeItem placeItemName, currentRoom

        takeItemIndex = msg.indexOf('/take ')
        if takeItemIndex >= 0
          takeItemName = msg.substr(takeItemIndex + 6)
          takeItem takeItemName, currentRoom

        imageIndex = msg.indexOf('/image ')
        if imageIndex >= 0
          Messages.insert
            imageUrl: msg.substr(imageIndex + 7)
            timestamp: Date.now()
            authorId: Meteor.user()._id
            roomId: currentRoom._id

        memeIndex = msg.indexOf('/meme ')
        if memeIndex >= 0
          Messages.insert
            imageUrl: msg.substr(memeIndex + 6)
            timestamp: Date.now()
            authorId: Meteor.user()._id
            roomId: currentRoom._id
            meme: true
            memeTitle: 'title'
            memeSubtitle: 'subtitle'

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
          authorId: Meteor.user()._id
          roomId: currentRoom._id

  Template['send-message'].events
    'keypress input[name="new-message"]': (event) ->
      if event.which is 13
        captureAndSendMessage()
        return false
      return
    'click input[name=send]' : ->
      captureAndSendMessage()

  for name, template of Template
    template.settings = Meteor.settings.public

  @subscriptions = {}
  for name, collection of subscribeList
    @subscriptions[name] = Meteor.subscribe name

if Meteor.isServer
  Meteor.Router.add '/boris/:state', (state) ->
    if state == 'in'
      setGlobal 'boris', true
    if state == 'out'
      setGlobal 'boris', false
  Meteor.Router.add '/boris', () ->
    if getGlobal('boris')
      return "boris is here"
    else
      return "boris is not here"

  @throwPermissionDenied = ->
    throw new Meteor.Error 403, "We're sorry, #{Meteor.settings.private?.domain or '<domain>'} is not open to the public. Please contact your host for an invitation."

  Meteor.methods
    sendEmail: (to, from, subject, text) ->
      check([to, from, subject, text], [String])

      # Let other method calls from the same client start running,
      # without waiting for the email sending to complete.
      @unblock()

      Email.send
        to: to
        from: from
        subject: subject
        text: text

  settings = Meteor.settings.private
  for list_name of settings.whitelist
    settings.whitelist[list_name] = ([].concat settings.whitelist[list_name]).sort()

  endsWith = (string, suffix) ->
      string.indexOf(suffix, string.length - suffix.length) isnt -1

  validUserByEmail = (user) ->
    settings = Meteor.settings.private
    email = user?.services?.google?.email or user?.services?.facebook?.email
    twitter = user?.services?.twitter?.screenName
    if email
      if endsWith email, "@#{Meteor.settings.private?.domain}"
        return true
      if _.indexOf(settings.whitelist.emails, email, true) isnt -1
        return true
    if twitter
      if _.indexOf(settings.whitelist.twitter, twitter, true) isnt -1
        return true

    console.log "validUserByEmail : info : denied \"#{email or twitter}\""
    return false

  # Setup security features
  Meteor.users.deny
    update: () ->
      return true

  publishCollection = (name, collection) ->
    Meteor.publish name, () ->
      user = Meteor.users.findOne @userId
      if user
        console.log "Handling publish of #{name} to #{user.profile.name}"
        if validUserByEmail user
          return collection.find()
      return undefined

    collection.allow
      insert: (userId, doc) ->
        return validUserByEmail Meteor.users.findOne userId
      update: (userId, doc, fieldNames, modifier) ->
        return validUserByEmail Meteor.users.findOne userId
      remove: (userId, doc) ->
        return validUserByEmail Meteor.users.findOne userId

  for name, collection of subscribeList
    publishCollection name, collection


  Accounts.validateNewUser (user) ->
    if validUserByEmail user
      return true
    do @throwPermissionDenied

  collectWeatherReport = ->
    # http://www.wunderground.com/weather/api/d/docs?d=data/conditions
    weather_api_url = Meteor.settings.private.weather.url
    Meteor.http.get weather_api_url, (error, result) ->
      if result?.data?
        WeatherReports.insert result.data.current_observation, (obj, _id) ->
          log 'info', 'collected weather data'
          WeatherReports.remove _id: $ne: _id

  Meteor.startup ->
    Globals.remove {name: 'settings'}
    Globals.remove {name: 'background'}
    if not Meteor.settings.public?.title
      throw new Error "Settings are uninitialized."
    console.log "Starting #{Meteor.settings.public.title}"
    if Meteor.settings.private?.weather
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

@Rooms = Rooms
@Items = Items
@Messages = Messages
@WeatherReports = WeatherReports
@formatDate = formatDate
@makeMeme = makeMeme
@dumpColl = dumpColl
