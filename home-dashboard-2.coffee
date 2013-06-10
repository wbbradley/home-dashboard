log = (level, msg) ->
  if typeof console != 'undefined'
    console.log "home-dashboard : #{level} : #{msg}"

if Meteor.isClient
  Template.message.foo = ->
    "Message: "

  Template.messages.events
    'click input[name=send]' : ->
      log 'info', $('input[name="new-message"]').val()
      

if Meteor.isServer
  Meteor.startup ->
    # code to run on server at startup
