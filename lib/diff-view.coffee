{Diff2Html} = require 'diff2html'
{ScrollView} = require 'atom-space-pen-views'
path = require 'path'
child = require 'child_process'

module.exports = class DiffView extends ScrollView
  @content: ->
    @div class: "diff-for-file", =>
      @div class: "parent-diff-view", =>
        @div class: 'diff-view for-file', outlet: "diffView"
        @div class: 'diff-logs', outlet: "logsView"

  initialize: (@filePath) ->
    super
    @filePath = null if @filePath == "Full Project"
    @fpath = if @filePath then @filePath else atom.workspace.getActiveTextEditor().getPath()

  getTitle: ->
    if @filePath
      "#{@filePath} (diff)"
    else
      "Full Project Diff"

  attached: ->
    diff = if @filePath
      child.spawnSync('git', ['diff', @fpath], cwd: path.dirname(@fpath)).stdout.toString()
    else
      child.spawnSync('git', ['diff'], cwd: path.dirname(@fpath)).stdout.toString()

    @diffView.html Diff2Html.getPrettyHtml(diff)

    cmds = ['log', '--date=short', '--format=format:%h##..##%ad##..##%an##..##%s']
    if @filePath
      cmds.push("--follow")
      cmds.push(@filePath)

    logs = child.spawnSync('git', cmds, cwd: path.dirname(@fpath))

    logs.stdout.toString().split("\n").forEach (row) =>
      [hash, date, author, message] = row.split("##..##")
      p = document.createElement('p')
      a = document.createElement('a')
      a.innerHTML = hash
      a.onclick = =>
        diff = if @filePath
          child.spawnSync('git', ['diff', "#{hash}^..#{hash}", @fpath],
                                 cwd: path.dirname(@fpath)).stdout.toString()
        else
          child.spawnSync('git', ['diff', "#{hash}^..#{hash}"],
                                 cwd: path.dirname(@fpath)).stdout.toString()
        @diffView.html Diff2Html.getPrettyHtml(diff)
      a.style.cursor = 'pointer'
      p.appendChild(a)
      p.insertAdjacentText("beforeEnd", " #{date} #{message} (#{author})")
      @logsView.append(p)
