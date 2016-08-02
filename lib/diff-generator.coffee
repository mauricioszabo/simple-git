diff = require('diff')

module.exports =
  fromLines: (previous, next) ->
    diffs = diff.diffLines(previous, next)
    result = [{}]

    lastElement = -> result[result.length-1]

    for element in diffs
      if element.removed
        lastElement().del = element.value
      else
        [first, rest...] = element.value.split("\n")
        @addIntoList(lastElement(), first, element.added)
        for row in rest
          obj = {}
          @addIntoList(obj, row, element.added)
          result.push(obj)
      console.log "Element", element, "Result: #{JSON.stringify result}"

    console.log result
    result

  addIntoList: (diffRow, text, added) ->
    if added
      diffRow.add = text
    else
      diffRow.same = text
