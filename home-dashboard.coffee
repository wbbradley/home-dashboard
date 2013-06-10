log = (level, msg) ->
  if typeof console != 'undefined'
    console.log "home-dashboard : #{level} : #{msg}"

Messages = new Meteor.Collection 'messages'

formatDate = (date) ->
    diff = Math.round((Date.now() - date) / 1000.0)
    weeks = Math.floor(diff / (7 * 24 * 3600))
    diff

if Meteor.isClient
  Template.message.helpers
    'date-render': (timestamp) ->
      formatDate(timestamp)

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
