log = (level, msg) ->
  if typeof console != 'undefined'
    console.log "home-dashboard : #{level} : #{msg}"

Messages = new Meteor.Collection 'messages'

if Meteor.isClient
  dumpColl = (coll) ->
    coll.find().forEach (item) ->
      console.log item

  append_time_unit = (diff, unit_name, unit, ret) ->
    if diff > unit
      units = Math.floor diff / unit
      diff -= units * unit
      if units is 1
        ret += "#{unit} #{unit_name}"
      else
        ret += "#{units} #{unit_name}s"
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
      else
        throw new Error "no author image"


  Template.message.foo = ->
    "Message: "

  Template.messages.messages = ->
    Messages.find {}, {sort: {timestamp: -1}}

  Template.messages.events
    'click input[name=deleteAll]' : ->
      Messages.find().forEach (message) ->
        Messages.remove message._id
    'click input[name=send]' : ->
      msg = $('input[name="new-message"]').val()
      $('input[name="new-message"]').val('')
      if msg
        log 'info', msg
        message =
          msg: msg
          timestamp: Date.now()
          author: Meteor.user()
        Messages.insert message, (obj, _id) ->
          if typeof obj is 'undefined'
            log 'info', "message logged '#{_id}'"
          else
            log 'warning', 'error inserting a new message'
      

if Meteor.isServer
  Meteor.startup ->
    # code to run on server at startup
@Messages = Messages
@formatDate = formatDate
@dumpColl = dumpColl
