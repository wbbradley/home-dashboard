log = (level, msg) ->
  if typeof console != 'undefined'
    console.log "home-dashboard : #{level} : #{msg}"

Messages = new Meteor.Collection 'messages'

if Meteor.isClient
  Template.message.foo = ->
    "Message: "

  Template.messages.messages = ->
    Messages.find {}

  Template.messages.events
    'click input[name=deleteAll]' : ->
      Messages.find().forEach (message) ->
        Messages.remove message._id
    'click input[name=send]' : ->
      msg = $('input[name="new-message"]').val()
      $('input[name="new-message"]').val('')
      if msg
        log 'info', msg
        Messages.insert msg: msg, (obj, _id) ->
          if typeof obj is 'undefined'
            log 'info', "message logged '#{_id}'"
          else
            log 'warning', 'error inserting a new message'
      

if Meteor.isServer
  Meteor.startup ->
    # code to run on server at startup
@Messages = Messages
