{CompositeDisposable} = require 'atom'
h = require './helper-fns'
DiffEditor = require './editor'

module.exports =
  activate: (state) ->
    atom.commands.add 'atom-workspace', 'git-repository:update-master', ->
      h.runAsyncGitCommand('checkout', 'master').then (code) ->
        if code == 0
          h.runAsyncGitCommand('pull', 'origin')

    atom.commands.add 'atom-workspace', 'git:quick-commit-current-file', =>
      @commitWithDiff(['diff', 'HEAD', h.getFilename()], h.getFilename())

    atom.commands.add 'atom-workspace', 'git:commit', =>
      @commitWithDiff(['diff', '--staged'])

    atom.commands.add 'atom-workspace', 'git:push-current-branch', ->
      h.runAsyncGitCommand('push', '--set-upstream', 'origin', h.currentBranch())

    atom.commands.add 'atom-workspace', 'git:add-current-file', ->
      h.treatErrors h.runGitCommand('add', h.getFilename())

    atom.commands.add 'atom-workspace', 'git:revert-current-file', ->
      h.treatErrors h.runGitCommand('checkout', h.getFilename())

    atom.commands.add 'atom-workspace', 'git:show-diff-for-current-file', ->
      path = atom.workspace.getActiveTextEditor().getPath()
      out = h.runGitCommand('diff', '-U999999', path)
        .stdout.toString()
      diff.newDiffView(path, out)

    # atom.commands.add 'atom-workspace', 'git:diff-layer', ->
    #   path = atom.workspace.getActiveTextEditor().getPath()
    #   out = h.runGitCommand('diff', '-U999999', path)
    #     .stdout.toString()
    #   diff.newDiffView(path, out)

    atom.commands.add 'atom-workspace', 'git:toggle-blame', => @blame()
    #   editor = atom.workspace.getActiveTextEditor()
    #   editor.blaming ?= false
    #   visibleGutter = $('::shadow div').find('div.gutter:visible')
    #   editor.lines = {}
    #
    #   if editor.blaming
    #     editor.blaming = false
    #     visibleGutter.css('width', editor.defaultSize)
    #   else
    #     editor.blaming = true
    #     editor.defaultSize = visibleGutter.css('width')
    #     visibleGutter.css('width', '250px')
    #     path = editor.getPath()
    #     blames = h.runGitCommand('blame', '-c', path).stdout.toString().split("\n")
    #     blames.forEach (row, number) ->
    #       [commit, author, timestamp] = row.split("\t")
    #       if author
    #         editor.lines[number] =
    #           author: author.substring(1)
    #           commit: commit
    #           time: timestamp
    #
    #   editor.observer ?= new MutationObserver (mutations) => mutations.forEach (m) =>
    #     for element in m.addedNodes
    #       updateElement(element)
    #   editor.observer.observe(visibleGutter[0], childList: true, subtree: true)
    #
    #   updateElement = (element) ->
    #     element = $(element)
    #     if editor.blaming
    #       line = element.data('buffer-row')
    #       return unless editor.lines[line]
    #       {author, commit, time} = editor.lines[line]
    #
    #       small = element.find('small.blame')
    #       if small.length == 0
    #         small = $('<small>').addClass('blame')
    #         element.prepend(small)
    #       name = author.trim().replace(/\s.*/, '')
    #       small.html("#{name} ").attr('title', "#{commit} (#{author}) at #{time}")
    #     else
    #       element.find('small.blame').detach()
    #
    #   # Re-update
    #   for element in visibleGutter.find('div.line-number')
    #     updateElement(element)
  #   this.subscriptions.add(atom.commands.add('atom-workspace', {
  #     'simple-git:toggle': () => this.toggle()
  #   }));
  # },

  commitWithDiff: (gitParams, filename) ->
    cont = h.runGitCommand(gitParams...).stdout.toString()

    if cont
      editor = h.promptEditor "Type your commit message", (commit) ->
        if filename
          h.treatErrors h.runGitCommand('commit', filename, '-m', commit)
        else
          h.treatErrors h.runGitCommand('commit', '-m', commit)
      diffEditor = new DiffEditor(editor)
      startLine = cont.match(/@@.*?(\d+)/)[1]
      cont = cont.replace(/(.*?\n)*?@@.*?\n/, '')
      diffEditor.setDiff(h.getFilename(), cont, parseInt(startLine))
      diffEditor.view.classList.add('commit')
    else
      atom.notifications.addError("Failed to commit", detail: "Nothing to commit...
      Did you forgot to add files, or the current file have any changes?")

  blame: ->
    editor = atom.workspace.getActiveTextEditor()
    editor.blameDecorations ?= []

    if editor.blameDecorations.length == 0
      blames = @getBlames(editor.getPath())

      for line, {author, commit, time} of blames
        div = document.createElement('div')
        div.textContent = "#{author} made these changes on commit #{commit} at #{time}"
        div.classList.add('blame')
        div.classList.add('decoration')
        # div.style.marginTop = '20px'
        # div.style.marginBottom = '10px'
        marker = editor.markScreenPosition([parseInt(line), 0])
        editor.blameDecorations.push(marker)
        editor.decorateMarker(marker, type: 'block', position: 'before', item: div)

    else
      editor.blameDecorations.forEach (m) -> m.destroy()
      editor.blameDecorations = []

  getBlames: (path) ->
    formatted = {}
    blames = h.runGitCommand('blame', '-c', path).stdout.toString().split("\n")
    lastLine = {}

    blames.forEach (row, number) =>
      [commit, author, timestamp] = row.split("\t")
      data = if author
        {author: author.substring(1).trim(), commit: commit, time: timestamp}
      else
        {author: "YOU", commit: '<none>', time: '<none>'}
      formatted[number] = data if !@sameLines(data, lastLine)
      lastLine = data

    formatted

  sameLines: (d1, d2) ->
    {author, commit, time} = d1
    [a1, c1, t1] = [author, commit, time]
    {author, commit, time} = d2
    [a2, c2, t2] = [author, commit, time]

    a1 == a2 && c1 == c2 && t1 == t2
#
#   deactivate() {
#   },
#
#   serialize() {
#   },
# };
