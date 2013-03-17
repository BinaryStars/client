class Annotator.Plugin.Bridge extends Annotator.Plugin
  # These events maintain the awareness of annotations between the two
  # communicating annotators.
  events:
    'beforeAnnotationCreated': 'beforeAnnotationCreated'
    'annotationDeleted': 'annotationDeleted'
    'annotationsLoaded': 'annotationsLoaded'

  # Plugin configuration
  options:

    # Origins allowed to communicate on the channel
    origin: '*'

    # Scope identifier to distinguish this channel from any others
    scope: 'annotator:bridge'

    # Formats an annotation for sending across the bridge
    formatter: (annotation) -> annotation

    # Parses an annotation received from the bridge
    parser: (annotation) -> annotation

    # Merge function. If specified, it will be called with the local copy of
    # an annotation and a parsed copy received as an argument to an RPC call
    # to reconcile any differences. The default behavior is to merge all
    # keys of the remote object into the local copy
    merge: (local, remote) ->
      for k, v of remote
        local[k] = v
      local

  # Cache of annotations which have crossed the bridge for fast, encapsulated
  # association of annotations received in arguments to window-local copies.
  cache: {}

  pluginInit: ->
    @options.onReady = this.onReady
    @channel = Channel.build @options

  # Assign a non-enumerable tag to objects which cross the bridge.
  # This tag is used to identify the objects between message.
  _tag: (msg, tag) ->
    return msg if msg.$$tag
    tag = tag or (window.btoa Math.random())
    Object.defineProperty msg, '$$tag', value: tag
    @cache[tag] = msg
    msg

  # Call the configured parser and tag the result
  _parse: ({tag, msg}) ->
    local = @cache[tag]
    remote = @options.parser msg

    if local?
      merged = @options.merge local, remote
    else
      merged = remote

    this._tag merged, tag

  # Tag the object and format it with the configured formatter
  _format: (annotation) ->
    this._tag annotation
    msg = @options.formatter annotation
    tag: annotation.$$tag
    msg: msg

  beforeAnnotationCreated: (annotation) =>
    unless annotation.$$tag?
      tag = this.createAnnotation()
      this._tag annotation, tag

  annotationDeleted: (annotation) =>
    return unless @cache[annotation.$$tag?]
    delete @cache[annotation.$$tag]
    this.deleteAnnotation annotation

  annotationsLoaded: (annotations) =>
    this.setupAnnotation a for a in annotations

  onReady: =>
    @channel

    ## Remote method call bindings
    .bind('createAnnotation', (txn, tag) =>
      annotation = this._tag {}, tag
      @annotator.publish 'beforeAnnotationCreated', annotation
      this._format annotation
    )

    .bind('setupAnnotation', (txn, annotation) =>
      this._format (@annotator.setupAnnotation (this._parse annotation))
    )

    .bind('updateAnnotation', (txn, annotation) =>
      this._format (@annotator.updateAnnotation (this._parse annotation))
    )

    .bind('deleteAnnotation', (txn, annotation) =>
      delete @cache[annotation.tag]
      this._format (@annotator.deleteAnnotation (this._parse annotation))
    )

    ## Notifications
    .bind('showEditor', (ctx, annotation) =>
      @annotator.showEditor (this._parse annotation)
    )

    .bind('showViewer', (ctx, annotations) =>
      @annotator.showEditor (this._parse a for a in annotations)
    )

  createAnnotation: (cb) ->
    tag = window.btoa Math.random()
    @channel.call
      method: 'createAnnotation'
      params: tag
      success: (annotation) => cb? null, this._parse annotation
      error: cb
    tag

  setupAnnotation: (annotation, cb) ->
    @channel.call
      method: 'setupAnnotation'
      params: this._format annotation
      success: (annotation) => cb? null, this._parse annotation
      error: cb

  updateAnnotation: (annotation, cb) ->
    @channel.call
      method: 'updateAnnotation'
      params: this._format annotation
      success: (annotation) => cb? null, this._parse annotation
      error: cb

  deleteAnnotation: (annotation, cb) ->
    @channel.notify
      method: 'deleteAnnotation'
      params: this._format annotation
      success: (annotation) => cb? null, this._parse annotation
      error: cb

  showEditor: (annotation) ->
    @channel.notify
      method: 'showEditor'
      params: this._format annotation

  showViewer: (annotations) ->
    @channel.notify
      method: 'showViewer'
      params: (this._format a for a in annotations)