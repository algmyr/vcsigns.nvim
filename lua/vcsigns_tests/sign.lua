local M = {}

local bit = require "bit"
local sign = require "vcsigns.sign"
local testing = require "vclib.testing"

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

local ADD = { type = sign.SignType.ADD, count = 0 }
local CHANGE = { type = sign.SignType.CHANGE, count = 0 }
local function DELETE_BELOW(count)
  return { type = sign.SignType.DELETE_BELOW, count = count }
end
local function DELETE_ABOVE(count)
  return { type = sign.SignType.DELETE_ABOVE, count = count }
end

local function _union(a, b)
  local res = {}
  res.type = bit.bor(a.type, b.type)
  res.count = a.count + b.count
  return res
end

M.signs = {
  test_cases = {
    change = {
      hunks = {
        _make_hunk(3, 2, 3, 2),
      },
      expected = { nil, nil, CHANGE, CHANGE, nil },
      line_count = 5,
    },
    addition = {
      hunks = {
        _make_hunk(2, 0, 3, 2),
      },
      expected = { nil, nil, ADD, ADD, nil },
      line_count = 5,
    },
    deletion = {
      hunks = {
        _make_hunk(3, 2, 4, 0),
      },
      expected = { nil, nil, nil, DELETE_BELOW(2), nil },
      line_count = 5,
    },
    deletion_at_start = {
      hunks = {
        _make_hunk(1, 3, 0, 0),
      },
      expected = { DELETE_ABOVE(3), nil, nil, nil },
      line_count = 4,
    },
    change_delete_at_start = {
      hunks = {
        _make_hunk(1, 3, 1, 1),
      },
      expected = { _union(DELETE_ABOVE(3), CHANGE), nil, nil, nil },
      line_count = 4,
    },
    split_complicated_cases = {
      hunks = {
        _make_hunk(1, 3, 0, 0),
        _make_hunk(4, 1, 1, 1),
        _make_hunk(7, 1, 4, 1),
        _make_hunk(8, 3, 4, 0),
        _make_hunk(14, 3, 7, 0),
        _make_hunk(17, 1, 8, 1),
        _make_hunk(20, 1, 11, 1),
        _make_hunk(21, 10, 11, 0),
      },
      expected = {
        _union(DELETE_ABOVE(3), CHANGE),
        nil,
        nil,
        CHANGE,
        DELETE_ABOVE(3),
        nil,
        DELETE_BELOW(3),
        CHANGE,
        nil,
        nil,
        _union(DELETE_BELOW(10), CHANGE),
      },
      line_count = 11,
    },
    decongestion_at_top = {
      hunks = {
        _make_hunk(1, 1, 0, 0),
        _make_hunk(3, 1, 1, 0),
        _make_hunk(5, 3, 2, 0),
      },
      expected = {
        _union(DELETE_ABOVE(1), DELETE_BELOW(1)), -- Combined count 2.
        DELETE_BELOW(3),
        nil,
        nil,
        nil,
      },
      line_count = 5,
    },
    -- https://github.com/algmyr/vcsigns.nvim/issues/23
    issue_23 = {
      hunks = {
        _make_hunk(1, 2, 0, 0),
        _make_hunk(2, 0, 1, 1),
        _make_hunk(3, 1, 1, 0),
        _make_hunk(4, 1, 2, 1),
      },
      expected = {
        _union(_union(DELETE_ABOVE(2), ADD), DELETE_BELOW(1)), -- Combined count 3.
        CHANGE,
        nil,
        nil,
        nil,
      },
      line_count = 5,
    },
  },
  test = function(case)
    local result = sign.compute_signs(case.hunks, case.line_count)
    for i = 1, case.line_count do
      local actual = result.signs[i]
      local expected = case.expected[i]
      if actual and expected then
        assert(
          expected.type == actual.type,
          "Sign type mismatch at line "
            .. i
            .. ": expected "
            .. sign.sign_type_to_string(expected.type)
            .. ", got "
            .. sign.sign_type_to_string(actual.type)
        )
        assert(
          expected.count == actual.count,
          "Sign count mismatch at line "
            .. i
            .. ": expected "
            .. expected.count
            .. ", got "
            .. actual.count
        )
      elseif actual or expected then
        error(
          "Sign mismatch at line "
            .. i
            .. ": expected "
            .. (expected and sign.sign_type_to_string(expected.type) or "nil")
            .. ", got "
            .. (actual and sign.sign_type_to_string(actual.type) or "nil")
        )
      end
    end
  end,
}

return M
