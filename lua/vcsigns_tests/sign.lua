local M = {}

local sign = require "vcsigns.sign"
local testing = require "vcsigns_tests.testing"

---@param s1 integer
---@param c1 integer
---@param s2 integer
---@param c2 integer
---@return Hunk
local function _make_hunk(s1, c1, s2, c2)
  return {
    minus_start = s1,
    minus_count = c1,
    plus_start = s2,
    plus_count = c2,
  }
end

local NONE = "none"
local ADD = "SignAdd"
local CHANGE = "SignChange"
local DELETE = "SignDelete"
local CHANGE_DELETE = "SignChangeDelete"
local DELETE_FIRST_LINE = "SignDeleteFirstLine"

M.fold_levels = {
  test_cases = {
    change = {
      hunks = {
        _make_hunk(3, 2, 3, 2),
      },
      expected = { NONE, NONE, CHANGE, CHANGE, NONE },
    },
    addition = {
      hunks = {
        _make_hunk(2, 0, 3, 2),
      },
      expected = { NONE, NONE, ADD, ADD, NONE },
    },
    deletion = {
      hunks = {
        _make_hunk(3, 2, 4, 0),
      },
      expected = { NONE, NONE, NONE, DELETE, NONE },
    },
    deletion_at_start = {
      hunks = {
        _make_hunk(1, 3, 0, 0),
      },
      expected = { DELETE_FIRST_LINE, NONE, NONE, NONE },
    },
    changedelete_at_start = {
      hunks = {
        _make_hunk(1, 3, 1, 1),
      },
      expected = { CHANGE_DELETE, NONE, NONE, NONE },
    },
    delete3_add2 = {
      hunks = {
        _make_hunk(2, 4, 2, 2),
      },
      expected = { DELETE, CHANGE, CHANGE, NONE },
    },
    add1_delete3 = {
      hunks = {
        _make_hunk(2, 4, 2, 2),
      },
      expected = { DELETE, CHANGE, CHANGE, NONE },
    },
  },
  test = function(case)
    local highlighs = {}
    for i = 1, #case.expected do
      highlighs[i] = NONE
    end
    local function add_sign(line, sign)
      assert(
        highlighs[line] == NONE,
        "Tried to add multiple signs to the same line"
      )
      assert(
        line >= 1 and line <= #case.expected,
        "Tried to add sign to line outside of expected range"
      )
      highlighs[line] = sign.hl
    end

    sign.add_signs_impl(case.hunks, add_sign)

    testing.assert_list_eq(highlighs, case.expected)
  end,
}

return M
