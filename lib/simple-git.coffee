{CompositeDisposable} = require 'atom'
h = require './helper-fns'
DiffEditor = require './editor'
{Diff2Html} = require 'diff2html'
{ScrollView} = require 'atom-space-pen-views'
class Scroll extends ScrollView
  @content: ->
    @div()
  initialize: (txt) ->
    super
    @text(txt)

module.exports =
  config:
    denyCommit:
      description: "Deny commits on master branch"
      type: 'boolean'
      default: true
    denyPush:
      description: "Deny pushes to remote master branch"
      type: 'boolean'
      default: true

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
      if atom.config.get('simple-git.denyPush') && h.currentBranch() == "master"
        atom.notifications.addError("Failed to push",
          detail: "You can't push to master.\nPlease create a branch and push from there")
        return

      h.runAsyncGitCommand('push', '--set-upstream', 'origin', h.currentBranch())

    atom.commands.add 'atom-workspace', 'git:add-current-file', ->
      h.treatErrors h.runGitCommand('add', h.getFilename())

    atom.commands.add 'atom-workspace', 'git:revert-current-file', ->
      h.treatErrors h.runGitCommand('checkout', h.getFilename())

    atom.commands.add 'atom-workspace', 'git:new-branch-from-current', ->
      h.prompt "Branch's name", (branch) ->
        h.treatErrors h.runGitCommand('checkout', '-b', branch)

    atom.commands.add 'atom-workspace', 'git:show-diff-for-current-file', ->
      path = atom.workspace.getActiveTextEditor().getPath()
      # out = h.runGitCommand('diff', '-U999999', path)
      out = h.runGitCommand('diff', path)
        .stdout.toString()
      # contents = out.replace(/(.*?\n)*?@@.*?\n/, '')

      # startLine = out.match(/@@.*?(\d+)/)[1]
      # cont = out.replace(/(.*?\n)*?@@.*?\n/, '')
      # parts = path.split(/[\/\\]/)
      # file = parts[parts.length-1]
      atom.workspace.open("(diff) #{file}").then (editor) ->
        diffEditor = new DiffEditor(editor)
        # diffEditor.setDiff(file, contents, 1)
        diffEditor.setDiff(file, cont, startLine)

        # # LOGS
        # div = $('<div>')
        # $('::shadow div').find('.scroll-view:visible').parent().append(div)
        # div.append(
        #   $('<p>').append(
        #     $('<a>').html("HEAD").on('click', => diffEditor.setDiff(filePath, contents))
        #   )
        # )
        #
        # out = child.spawnSync('git', ['log', '--date=short',
        #   '--format=format:%h##..##%ad##..##%an##..##%s', '--follow', filePath],
        #   cwd: path.dirname(path))
        #
        # out.stdout.toString().split("\n").forEach (row) =>
        #   [hash, date, author, message] = row.split("##..##")
        #   p = $('<p>')
        #   a = $('<a>').html(hash).on 'click', =>
        #     diff = child.spawnSync('git', ['diff',
        #       "#{hash}^..#{hash}", filePath], cwd: path.dirname(filePath)).stdout.toString()
        #     diffEditor.setDiff(file, diff.replace(/(.*?\n)*?@@.*?\n/, ''))
        #   a.css('cursor', 'pointer')
        #   p.append(a).append(" #{date} #{message} (#{author})")
        #   div.append(p)
        #
        # div.css(width: '400px', height: '100%', float: 'right', 'background': 'white')
        # div.css('margin-right': '15px', 'overflow': 'scroll')

    atom.commands.add 'atom-workspace', 'git:toggle-blame', => @toggleBlame()

  commitWithDiff: (gitParams, filename) ->
    if atom.config.get('simple-git.denyCommit') && h.currentBranch() == "master"
      atom.notifications.addError("Failed to commit",
        detail: "You can't commit into master.\nPlease create a branch and commit from there")
      return

    cont = h.runGitCommand(gitParams...).stdout.toString()

    if cont
      div = h.prompt "Type your commit message", (commit) ->
        if filename
          h.treatErrors h.runGitCommand('commit', filename, '-m', commit)
        else
          h.treatErrors h.runGitCommand('commit', '-m', commit)

      div2 = document.createElement('div')
      div2.classList.add('diff-view', 'commit')
      div2.innerHTML = Diff2Html.getPrettyHtml(cont)
      div.append(div2)
    else
      atom.notifications.addError("Failed to commit", detail: "Nothing to commit...
      Did you forgot to add files, or the
      current file have any changes?")

  toggleBlame: ->
    editor = atom.workspace.getActiveTextEditor()
    if !editor.blameDecorations
      editor.blameDecorations = []
      editor.onDidSave =>
        @toggleBlame()
        @toggleBlame()

    if editor.blameDecorations.length == 0
      blames = @getBlames(editor.getPath())

      for line, {author, commit, time} of blames
        div = document.createElement('div')
        div.textContent = "#{author} made these changes on commit #{commit} at #{time}"
        div.classList.add('blame')
        div.classList.add('decoration')
        marker = editor.markScreenPosition([parseInt(line), 0])
        editor.blameDecorations.push(marker)
        editor.decorateMarker(marker, type: 'block', position: 'before', item: div)

    else
      editor.blameDecorations.forEach (m) -> m.destroy()
      editor.blameDecorations = []

  getBlames: (path) ->
    formatted = {}
    blames = h.runGitCommand('blame', '-M', '-w', '-c', path).stdout.toString().split("\n")
    lastLine = {}

    blames.forEach (row, number) =>
      [commit, author, timestamp] = row.split("\t")
      data = if author && commit != '00000000'
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
