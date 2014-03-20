console.log "Starting home-dashboard..."

@default_settings =
  private:
    domain: "gmail.com"
    sendBroadcastEmail: false
    admins: [
      'williambbradley@gmail.com'
    ]
    whitelist:
      emails: []
      twitter: ['wbbradley']
  public:
    title: "Home Dashboard"
    server: "http://localhost:3000/"
    karma: true
    pageSize: 10

log = (level, msg) ->
  if typeof console != 'undefined'
    console.log "home-dashboard : #{level} : #{msg}"

Invites = new Meteor.Collection 'invites'
Messages = new Meteor.Collection 'messages'
Beers = new Meteor.Collection 'beers'
Comments = new Meteor.Collection 'comments'
Rooms = new Meteor.Collection 'rooms'
Items = new Meteor.Collection 'items'
WeatherReports = new Meteor.Collection 'weather_reports'
Globals = new Meteor.Collection 'globals'

subscribeList =
  'users': Meteor.users
  'messages': Messages
  'beers': Beers
  'comments': Comments
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
    if typeof(value) is 'object'
      if typeof(global.value) is 'object'
        value = _.extend global.value, value
    Globals.update {_id: global._id},
      $set:
        value: value
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

userEmailAddress = (user) ->
  return user?.services?.google?.email or user?.services?.facebook?.email

##################################################################
if Meteor.isClient
  Meteor.settings = Meteor.settings or {}
  Meteor.settings.public = _.defaults Meteor.settings.public or {}, default_settings.public

  @goToFirstPage = ->
      Session.set 'skipAhead', 0

  @currentRoom = () ->
    Rooms.findOne {}, {sort: {timestamp: -1}}

  Session.set 'pageSize', Meteor.settings.public.pageSize

  goToFirstPage()

  @pickFile = () ->
    filepicker.pick (InkBlob) ->
      switch InkBlob.mimetype
        when 'image/gif' then addImageByUrl InkBlob.url
        else addImageByUrl "#{InkBlob.url}/convert?w=640&fit=clip&format=jpg&quality=95"

  document.title = Meteor.settings.public.title
  dumpColl = (coll) ->
    coll.find().forEach (item) ->
      console.log item

  showNewerMessages = ->
    newSkip = Session.get('skipAhead') - Session.get('pageSize')
    if newSkip < 0
      newSkip = 0
    Session.set 'skipAhead', newSkip
    smoothScroll 'messages'

  showOlderMessages = ->
    Session.set 'skipAhead', Session.get('skipAhead') + Session.get('pageSize')
    smoothScroll 'messages'

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

  Template.header.helpers
    messagesReady: ->
      subscriptions.messages.ready()

  addComment = (_id) ->
    # Messages.update {_id: _id},
    #   $set:
    #     meme: true
    #     memeTitle: 'title'
    #     memeSubtitle: 'subtitle'

  Template.body.helpers
    background: ->
      @getGlobal('background') or ''
    messagesReady: ->
      subscriptions.messages.ready()

  Template.message.helpers
    'date-render': (timestamp) ->
      formatDate(timestamp)

  Template.message.ownerOrAdmin = ->
    userId = Meteor.user()?._id
    return userId is @authorId or isAdminUser userId

  Template.message.lovable = ->
    userId = Meteor.user()?._id
    userLoveIds = @userLoveIds or []
    return @authorId isnt userId and userLoveIds.indexOf(userId) is -1

  Template.message.author = ->
    Meteor.users.findOne {_id:@authorId}

  Template.message.comments = ->
    Comments.find {msgId: @_id}, {sort: {timestamp: 1}}
  
  captureAndSendComment = (message, el) ->
    $input = $(el).closest('nav.comment').find('input[type=text]')
    text = $input.val()
    $input.val('')
    Comments.insert
      text: text
      msgId: message._id
      authorId: Meteor.user()._id
      timestamp: Date.now()

  Template.message.events
    'click .delete-btn': () ->
      Messages.update {_id: @_id},
        $set: {deleted: true}
    'keypress input[name="text"]': (event) ->
      if event.which is 13
        captureAndSendComment @, event.target
        return false
      return
    'click .comment-btn': () ->
      captureAndSendComment @, event.target
    'click .meme-btn': () ->
      makeMeme @_id
    'click .comment-btn': () ->
      addComment @_id
    'click .love-btn': () ->
      if Meteor.user()?._id?
        log 'info', "#{Meteor.user().profile.name} liked a post"
        Messages.update {_id: @_id},
          $addToSet: {userLoveIds: Meteor.user()._id}

  @getUserImage = (authorId) ->
    author = Meteor.users.findOne {_id:authorId}
    unknown = "http://b.vimeocdn.com/ps/346/445/3464459_300.jpg"
    if author
      if author.image
        return author.image
      if author.services?
        if author.services.twitter
          return author.services.twitter.profile_image_url.replace('_normal', '') or unknown
        else if author.services.google
          return author.services.google.picture or unknown
        else if author.services.facebook
          return "http://graph.facebook.com/#{author.services.facebook.id}/picture?type=large"
      email = userEmailAddress author
      if email
        return "http://www.gravatar.com/avatar/#{md5(email.toLowerCase())}?s=150"
    return unknown

  @getUserName = (authorId) ->
    author = Meteor.users.findOne {_id:authorId}
    return author.profile.name or 'Unknown'

  @isAdminUser = (userId) ->
    user = Meteor.users.findOne {_id:userId}
    user.isAdmin

  Template.message.helpers
    withAuthor: (userId, options) ->
      author = Meteor.users.findOne {_id: userId}, {sort: {timestamp: -1}}
      authorContext =
        name: author.profile.name
        image: getUserImage userId
      return options.fn authorContext
    ifNotLoved: (context, options) ->
      userLoveIds = @['userLoveIds'] or []
      if userLoveIds.indexOf(Meteor.user()._id) is -1
        return options.fn @
      else
        return options.inverse @
    ifOwner: (context, options) ->
      userId = Meteor.user()?._id
      if userId is @authorId or isAdminUser userId
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

    getAuthorName: (authorId) ->
      getUserName authorId

    say: (msg) ->
      # $.say msg
      msg


  Template.messages.helpers
    eachItem: (context, options) ->
      currentRoom = currentRoom()
      if currentRoom?._id
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
      else
        return options.inverse @

  Template.messages.roomName = ->
    room = Rooms.findOne {}, {sort: {timestamp: -1}}
    if not room
      return 'VOID'
    if room.name is 'lobby'
      return 'lobby'
    else
      return "#{room.name}"

  Deps.autorun ->
    Template.messages.messages = ->
      currentRoom = Rooms.findOne {}, {sort: {timestamp: -1}}
      if not currentRoom
        return []
      findCriteria =
        roomId: currentRoom._id
        deleted: null
      cursor_count = Messages.find findCriteria, {sort: {timestamp: -1}}
      queryParams =
        sort: timestamp: -1
        limit: Session.get('pageSize')
        skip: Session.get('skipAhead')
      cursor = Messages.find findCriteria, queryParams
      Template.messages.messageCount = cursor_count.count()
      return cursor

  Template.messages.newerMessagesExist = ->
    Template.messages.messageCount > 0 and Session.get('skipAhead') > 0

  Template.messages.olderMessagesExist = ->
    Template.messages.messageCount > Session.get('pageSize') + Session.get('skipAhead')

  Template.currentUserImage.imageUrl = ->
    if Meteor.user()
      getUserImage Meteor.user()._id
    else
      ''

  Template.body.roomName = ->
    room = Rooms.findOne {}, {sort: {timestamp: -1}}
    if not room
      return ''
    if room.lcname is 'lobby'
      return 'lobby'
    else
      return "#{room.name} room"

  @balanceText = (event) ->
    $(event.target).parent().textfill
      maxFontPixels: 180
      maxWidth: $(event.target).parents('.meme-container').width() - 40

  @updateMeme = (_id) ->
    title = $("#meme-#{_id}-title")[0]?.innerHTML or ''
    subtitle = $("#meme-#{_id}-subtitle")[0]?.innerHTML or ''
      
    Messages.update {_id: _id},
      $set:
        memeTitle: title
        memeSubtitle: subtitle


  Template.memeDisplay.rendered = Template.memificator.rendered = ->
    $firstNode = $(@firstNode)
    maxWidth = $firstNode.width() - 40
    $firstNode.find('.meme-text').each ->
      $(@).parent().textfill
        maxFontPixels: 180
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
    currentRoom or= currentRoom()
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
    room or= currentRoom()
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

  @addImageByUrl = (imageUrl) ->
    if imageUrl
      Messages.insert
        imageUrl: imageUrl
        timestamp: Date.now()
        authorId: Meteor.user()._id
        roomId: currentRoom()._id
      goToFirstPage()

  @hadBeers = (count) ->
    count = parseFloat(count)
    if count > 0
      Beers.insert
        timestamp: Date.now()
        userId: Meteor.user()._id


  @search = (search) ->
    searchString = search
    Meteor.call 'search', search, Meteor.user()._id, currentRoom()._id


  @addMemeByUrl = (imageUrl) ->
    if imageUrl
      Messages.insert
        imageUrl: imageUrl
        timestamp: Date.now()
        authorId: Meteor.user()._id
        roomId: currentRoom()._id
        meme: true
        memeTitle: 'title'
        memeSubtitle: 'subtitle'
      goToFirstPage()

  @addYouTubePlaylist = (youtube) ->
    if youtube
      Messages.insert
        youtube: encodeURIComponent youtube
        timestamp: Date.now()
        authorId: Meteor.user()._id
        roomId: currentRoom()._id
      goToFirstPage()

  @inviteByEmail = (emailInvited) ->
    Meteor.call 'inviteByEmail', emailInvited, Meteor.user()._id

  @updateProfileImage = (imageUrl) ->
    if /^http/.test imageUrl
      Meteor.call 'updateProfileImage', imageUrl

  captureAndSendMessage = ->
    msg = $('input[name="new-message"]').val()
    $('input[name="new-message"]').val('')
    if msg
      log 'info', msg

      cmdTable =
        room: switchToRoom
        place: placeItem
        take: takeItem
        image: addImageByUrl
        meme: addMemeByUrl
        youtube: addYouTubePlaylist
        invite: inviteByEmail
        face: updateProfileImage
        beers: hadBeers
        search: search

      re = /^\/([^ ]+) (.*)$/
      match = re.exec msg
      if match
        cmd = match[1]
        arg = match[2]
        if cmd of cmdTable
          cmdTable[cmd] arg
      else
        # handle lone image urls
        reImage = /.*(http[s]?:\/\/.*(JPG|JPEG|GIF|PNG|jpg|jpeg|gif|png))(\s|$).*/
        match = msg.match reImage
        if match
          addImageByUrl match[1]
        else
          cmdTable.search msg

        Session.set 'skipAhead', 0

  Template['send-message'].helpers
    filepickerEnabled: ->
      return Boolean(getGlobal 'filepickerApiKey')

  Template['send-message'].events
    'keypress input[name="new-message"]': (event) ->
      if event.which is 13
        captureAndSendMessage()
        return false
      return
    'click [name=send]' : ->
      captureAndSendMessage()

  karmaCalc = () ->
    points = 0
    if Meteor.user()
      userId = Meteor.user()._id
      findCriteria =
        authorId: userId
        deleted: $ne: true
      cursor = Messages.find findCriteria
      cursor.forEach (message) ->
        if message.userLoveIds?
          points += message.userLoveIds.length
    return points: points

  for name, template of Template
    template.settings = Meteor.settings.public
    if Meteor.settings.public.karma is true
      template.karma = karmaCalc

  @subscriptions = {}
  for name, collection of subscribeList
    @subscriptions[name] = Meteor.subscribe name

if Meteor.isServer
  """
  Meteor.Router.add '/boris/:state', (state) ->
    if state is 'in'
      upsertGlobal 'boris', true
    if state is 'out'
      upsertGlobal 'boris', false
  Meteor.Router.add '/boris', () ->
    if getGlobal('boris')
      return "boris is here"
    else
      return "boris is not here"
  """
  @throwPermissionDenied = ->
    throw new Meteor.Error 403, "We're sorry, #{Meteor.settings.private?.domain or '<domain>'} is not open to the public. Please contact your host for an invitation."

  @addToEmailWhitelist = (email) ->
    privateSettings = Meteor.settings.private
    if _.indexOf(privateSettings.whitelist.emails, email, true) is -1
      console.log "Adding invited user '#{email}' to whitelist"
      privateSettings.whitelist.emails.push email
      privateSettings.whitelist.emails = ([].concat privateSettings.whitelist.emails).sort()
    console.log "New whitelist is [#{privateSettings.whitelist.emails.join(', ')}]"

  Meteor.methods
    search: (searchString, user_id, room_id) ->
      Meteor.http.get "https://ajax.googleapis.com/ajax/services/search/images?v=1.0&q=#{encodeURIComponent(searchString)}", (error, result) ->
        results = (JSON.parse result.content).responseData.results
        item = results[Math.floor(Math.random() * results.length)]
        words = searchString.split ' '
        half = Math.floor(words.length / 2)
        title = words.slice(0, half).join(' ')
        subTitle = words.slice(half).join(' ')
        Messages.insert
          imageUrl: item.unescapedUrl
          timestamp: Date.now()
          authorId: user_id
          roomId: room_id
          meme: true
          memeTitle: title
          memeSubtitle: subTitle

    inviteByEmail: (emailInvited, userId) ->
      check [emailInvited, userId], [String]
      user = Meteor.users.findOne userId
      console.log "#{user.profile.name} is inviting #{emailInvited}"
      invite = Invites.findOne {emailInvited: emailInvited}

      if not invite
        Invites.insert
          emailInvited: emailInvited
          fromUserId: userId
        emailSender = userEmailAddress user or null
        if emailSender
          Email.send
            to: emailInvited
            from: emailSender
            subject: "You've been invited to #{Meteor.settings.public.title}"
            text: "Hello, #{user.profile.name} has invited you to check out #{Meteor.settings.public.server}"
        email = emailInvited
        console.log "Processing invited user '#{email}'"
        addToEmailWhitelist(emailInvited)
      else
        console.log "Found an oustanding invite for #{emailInvited}"

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

  Meteor.settings = _.defaults Meteor.settings, default_settings

  check [Meteor.settings.private.admins[0]], [String]
  @adminEmail = ->
    Meteor.settings.private.admins[0]

  @initWhitelist = ->
    # Sort the whitelists
    for list_name of Meteor.settings.private.whitelist
      Meteor.settings.private.whitelist[list_name] = ([].concat Meteor.settings.private.whitelist[list_name]).sort()

    Invites.find().forEach (invite) ->
      addToEmailWhitelist invite.emailInvited
  initWhitelist()
  endsWith = (string, suffix) ->
      string.indexOf(suffix, string.length - suffix.length) isnt -1

  if Meteor.settings.private?.admins?.indexOf?
    Meteor.users.find().forEach (user) ->
      email = userEmailAddress user
      index = Meteor.settings.private.admins.indexOf email
      isAdmin = index isnt -1
      console.log "home-dashboard : info : setting '#{user.profile.name} (#{email})' isAdmin to #{isAdmin}"
      Meteor.users.update {_id: user._id}, $set: isAdmin: index isnt -1

  validUserByEmail = (user) ->
    settings = Meteor.settings.private
    email = userEmailAddress user
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

  Meteor.methods
    updateProfileImage: (image) ->
      Meteor.users.update Meteor.userId(),
        $set:
          image: image

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

  if Meteor.settings.private.sendBroadcastEmail
    # Monitor for new messages and send appropriate emails
    msgCursor = Messages.find({timestamp: {$gt: Date.now()}})
    msgCursor.observe
      added: (msg) ->
        creator = Meteor.users.findOne {_id:msg.authorId}
        Meteor.users.find().forEach (user) ->
          email = userEmailAddress user
          sender = adminEmail()
          Email.send
            to: email
            from: adminEmail()
            subject: "#{creator.profile.name} posted to #{Meteor.settings.public.title}"
            text: "Check it out at #{Meteor.settings.public.server}#message-#{msg._id}"

  commentCursor = Comments.find({timestamp: {$gt: Date.now()}})
  commentCursor.observe
    added: (comment) ->
      console.dir comment
      msg = Messages.findOne {_id:comment.msgId}
      recipients = [msg.authorId]
      Comments.find({msgId:msg._id}).forEach (earlierComment) ->
        if earlierComment.authorId not in recipients
          recipients.push earlierComment.authorId

      originalAuthor = Meteor.users.findOne {_id:msg.authorId}
      commentAuthor = Meteor.users.findOne {_id:comment.authorId}
      sender = adminEmail()
      for recipient in recipients
        if comment.authorId isnt recipient
          recipientUser = Meteor.users.findOne {_id:recipient}
          email = userEmailAddress recipientUser
          Email.send
            to: email
            from: adminEmail()
            subject: "#{commentAuthor.profile.name} replied to a post you are in on #{Meteor.settings.public.title}"
            text: "Check it out at #{Meteor.settings.public.server}#message-#{msg._id}"

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
@Beers = Beers
@Globals = Globals
@WeatherReports = WeatherReports
@formatDate = formatDate
@makeMeme = makeMeme
@addComment = addComment
@dumpColl = dumpColl
@userEmailAddress = userEmailAddress
@showNewerMessages = showNewerMessages
@showOlderMessages = showOlderMessages
