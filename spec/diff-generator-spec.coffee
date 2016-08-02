gen = require('../lib/diff-generator')

describe 'DiffGenerator', ->
  it 'generates a diff', ->
    res = gen.fromLines("foo bar baz", "foo baz woo")
    expect(res).toEqual([{del: "foo bar baz", add: "foo baz woo"}])

  it 'generates a diff with multiple lines', ->
    res = gen.fromLines("a\na1\nb\nc", "a\nb\nc")
    expect(res).toEqual([{same: "a"}
                         {del: "a1\n", same: "b"}
                         {same: "c"}])

    res = gen.fromLines("0\n1\nA\nA1\nB1\nB\nC\n", "A\nA1\nB\nC\nD")
    expect(res).toEqual([{del: "0\n1\n", same: "A"}
                         {same: "A1"}
                         {del: "B1\n", same: "B"}
                         {same: "C"}
                         {add: "D", same: ""}])
