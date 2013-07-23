###
#    Guts Framework for Backbone views
###
#
# Handling subviews:
# http://stackoverflow.com/questions/9337927/how-to-handle-initializing-and-rendering-subviews-in-backbone-js
# Basic render strategy:
# http://ianstormtaylor.com/rendering-views-in-backbonejs-isnt-always-simple/
verbose = false

handlebars_render = (template_name, context) ->
  template = App.Handlebars[template_name]
  if template
    if verbose
      console.log "Rendering template '#{template_name}'"
    output = template context
    return output
  else
    throw "handlebars_render : error : couldn't find template '#{template_name}'"

render = handlebars_render

isDescendant = (parent, child) ->
  node = child.parentNode
  while node isnt null
    if node is parent
      return true
    node = node.parentNode
  false

moveChildren = (elFrom, elTo) ->
  if elTo.childNodes.length
    throw 'moveChildren : error : destination tag should not have any children'

  while elFrom.childNodes.length
    elTo.appendChild elFrom.childNodes[0]


# BasicModelView always updates and is therefore only OK for basic templates
# that are not nested or involving forms.
class BasicModelView extends Backbone.View
  get_template: =>
    @options.template or @template or @className

  render: =>
    if @options.models
      context = {}
      for model_name, model of @options.models
        context[model_name] = model.toJSON()
        context[model_name + '_url'] = model.url
        context[model_name + '_cid'] = model.cid
    else
      if not @model
        throw new Error 'BasicModelView : error : model is not set'
      context =
        model: @model.toJSON()
        cid: @model.cid
        url: @model.url
    template_result = render @get_template(), context
    @$el.html(template_result)
    @

  initialize: =>
    @render()
    if not (@render_once or @options.render_once)
      if @options.models
        for model_name, model of @options.models
          @listenTo model, 'change', @render
      else
        @listenTo @model, 'change', @render
  
class CompositeModelView extends Backbone.View
  _rendered: false

  get_template: =>
    template = @template or @options.template or @className
    if @className isnt template
      throw "CompositeModelView : error : templates should be named after the semantic class (#{@className}, #{template})"
    template

  # find_view_placeholder is guaranteed to return a valid element that is the placeholder for this child_view
  # ... or throw
  find_view_placeholder: ($el, child_view) ->
    # Find the placeholder
    selector = ".#{child_view.className}"

    $placeholder = $el.find(selector)

    if $placeholder.length > 1
      throw "CompositeModelView : error : found too many placeholder elements when finding selector '#{selector}'"
    placeholder = $placeholder[0]
    if not placeholder
      throw "CompositeModelView : error : couldn\'t find placeholder element to be replaced: selector = '#{selector}'"
    if placeholder.children.length isnt 0
      throw "CompositeModelView : error : found a placeholder node (selector is '#{selector}') in your template that had children. Confused! Bailing out."
    return placeholder

  reassign_child_views: =>
    for view in @_child_views
      if view and view.el
        if isDescendant(@el, view.el)
          throw 'CompositeModelView : error : existing view elements should not be magical children'
        if isDescendant(document, view.el)
          throw 'CompositeModelView : error : orphans should not have a home'

        placeholder = @find_view_placeholder(@$el, view)

        # get the children of the child view and move them into the new placeholder
        moveChildren view.el, placeholder

        # make sure the child view knows its new home
        view.setElement placeholder, true

        if not isDescendant(@el, view.el)
          throw 'CompositeModelView : error : replaceChild didn\'t work as expected'
        if view.$el[0] isnt view.el
          throw 'CompositeModelView : error : $el is confused'
    return
     
  render: =>
    if @_rendered
      # CompositeModelView should not need to render multiple times since it is
      # associated with a model and not individual fields
      return @

    if @options.models
      context = {}
      for model_name, model of @options.models
        context[model_name] = model.toJSON()
        context[model_name + '_url'] = model.url
        context[model_name + '_cid'] = model.cid
    else
      if not @model
        throw 'CompositeModelView : error : model is not set'
      context =
        model: @model.toJSON()
        cid: @model.cid
        url: @model.url

    @_rendered = true
    template_result = render do @get_template, context
    orphans = @$el.children().detach()
    @$el.html(template_result)

    # Put the children back in their place
    @reassign_child_views()
    @

  rerender: =>
    @_rendered = false
    do @render

  initialize: =>
    template = @get_template()
    @_child_views = []
    @render()
    for binding, view of _.result(@options, 'child_views') or _.result(@, 'child_views')
      view = if typeof view is 'function' then view() else view
      if not view.className
        console.log "CompositeModelView : error : child view '#{binding}' must be initialized with a \'className\'"
        throw view
      @[binding] = view
      @_child_views.push view
    delete @child_views
    @reassign_child_views()
    if (@render_on_change or @options.render_on_change)
      if @options.models
        for model_name, model of @options.models
          @listenTo model, 'change', @rerender
      else
        @listenTo @model, 'change', @rerender
    @

class CompositeModelForm extends CompositeModelView
  initialize: =>
    if @options.models
      throw 'CompositeModelForm : error : forms do not support multiple associated models'
    super
    if not @model.has('url')
      @listenToOnce @model, 'change', @rerender

  save: =>
    @listenToOnce @model, 'sync', =>
      if verbose
        console.log 'save succeeded'
    @model.save()

  submitted: (e) =>
    e.preventDefault()
    @save()
    return false

  file_chosen: (e) =>
    # https://developer.mozilla.org/en-US/docs/Using_files_from_web_applications
    if typeof @model.set_file_field isnt 'function'
      console.log 'Guts.CompositeModelForm : warning : file inputs can be handled using Backbone.FormDataTransport.Model associated with this CompositeModelForm'
      return

    for file_element in @$('input[type=file]')
      if file_element.files.length > 0
        for file in file_element.files
          console.log "CompositeModelForm : info : loading file '#{file.name}' from file field '#{file_element.name}'"

          @model.set_file_field file_element.name, file
          @model.save()
          @listenToOnce @model, "change:#{file_element.name}", @rerender
    return


  keyup: (e) =>
    data = Backbone.Syphon.serialize(@)
    @model.set data

    if @timer
      window.clearTimeout(@timer)
    @timer = window.setTimeout @save, 2000

  events: =>
    form_events =
      'submit form': 'submitted'
      'keyup input': 'keyup'
      'keyup textarea': 'keyup'
      'change input[type=file]': 'file_chosen'
    if @extra_events
      form_events = _.extend(form_events, _.result(@, 'extra_events'))
    if @options.extra_events
      form_events = _.extend(form_events, _.result(@options, 'extra_events'))
    form_events
  

class ModelFieldView extends Backbone.View
  render: =>
    value = @options.model.get(@options.property)
    context = {}
    context[@options.property] = value
    template_result = render @get_template(), context
    @$el.html(template_result)
    @

  initialize: (options) =>
    if not @get_template()
      @render = =>
        value = @options.model.get(@options.property)
        if value
          if @options.unescaped
            @$el.html(value)
          else
            @$el.html(_.escape value)
        @
    if @options.is_form_field
      @listenToOnce @options.model, "change:#{@options.property}", @render
    else
      @render()
      @listenTo @options.model, "change:#{@options.property}", @render

class BaseCollectionView extends Backbone.View
  initialize: (options) =>
    if not options.item_view_class
      throw 'BaseCollectionView : error : You must specify an item_view_class when creating a BaseCollectionView'
    if not options.collection
      throw 'BaseCollectionView : error : You must specify a collection when creating a BaseCollectionView'
    if options.model
      console.log 'BaseCollectionView : warning : BaseCollectionView does not pay attention to \'model\''

    @_child_views = []
    @collection.each @add

    @listenTo @collection, 'add', @add
    @listenTo @collection, 'remove', @remove
 
  add: (model) =>
    childView = new @options.item_view_class
      model: model
    comparator = @collection.comparator or @options.comparator or @comparator
    if comparator
      if typeof comparator is 'string'
        comparator_string = comparator
        comparator = (model) => model.get comparator_string
      else
        throw "Guts : error : BaseCollectionView only understands function or string comparators"
      index = @collection.sortedIndex model, comparator
    else
      index = @_child_views.length

    childEl = childView.render().el

    if index < @_child_views.length
      referenceEl = @_child_views[index].el
      @el.insertBefore childEl, referenceEl
    else
      el = @$el.append(childEl)
    @_child_views.splice index, 0, childView


  remove: (model) =>
    _viewToRemove = _.where @_child_views, (view) -> view.model is model
    if not _viewToRemove or not _viewToRemove[0]
      throw "BaseCollectionView : error : couldn\'t find view to remove from collection corresponding to model #{model.cid}"
    viewToRemove = _viewToRemove[0]
    @_child_views = _.where @_child_views, (view) -> view isnt viewToRemove
    @$(viewToRemove.el).remove()

  at: (index) =>
    return @_child_views[index]


# Export Guts
class Guts
  @BasicModelView:     BasicModelView
  @CompositeModelView: CompositeModelView
  @CompositeModelForm: CompositeModelForm
  @BaseCollectionView: BaseCollectionView
  @ModelFieldView:     ModelFieldView

@Guts = Guts
