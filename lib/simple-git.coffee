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

    # blaming = false
    # atom.commands.add 'atom-workspace', 'git:toggle-blame', ->
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
            h.treatErrors h.runGitCommand('commit', '-m', commit)
          else
            h.treatErrors h.runGitCommand('commit', filename, '-m', commit)
        diffEditor = new DiffEditor(editor)
        startLine = cont.match(/@@.*?(\d+)/)[1]
        cont = cont.replace(/(.*?\n)*?@@.*?\n/, '')
        diffEditor.setDiff(h.getFilename(), cont, parseInt(startLine))
        diffEditor.view.classList.add('commit')
      else
        atom.notifications.addError("Failed to commit", detail: "Nothing to commit...
        Did you forgot to add files, or the current file have any changes?")
#
#   deactivate() {
#   },
#
#   serialize() {
#   },
# };
