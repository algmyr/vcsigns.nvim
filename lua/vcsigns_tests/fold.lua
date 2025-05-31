local M = {}

local fold = require "vcsigns.fold"
local testing = require "vcsigns_tests.testing"

M.fold_levels = {
  test_cases = {
    simple = {
      hunks = {
        { plus_start = 8, plus_count = 2, minus_start = -1, minus_count = -1 },
      },
      context = { 3 },
      expected = {
        1, --  1|
        1, --  2|
        1, --  3|
        1, --  4|
        0, --  5| 3
        0, --  6| 2
        0, --  7| 1
        0, --  8| +
        0, --  9| +
        0, -- 10| 1
        0, -- 11| 2
        0, -- 12| 3
        1, -- 13|
        1, -- 14|
      },
    },
    documentation_example = {
      hunks = {
        { plus_start = 8, plus_count = 2, minus_start = -1, minus_count = -1 },
      },
      context = { 1, 3 },
      expected = {
        2, --  1|
        2, --  2|
        2, --  3|
        2, --  4|
        1, --  5|   3
        1, --  6|   2
        0, --  7| 1
        0, --  8| +
        0, --  9| +
        0, -- 10| 1
        1, -- 11|   2
        1, -- 12|   3
        2, -- 13|
        2, -- 14|
      },
    },
    complicated_example = {
      hunks = {
        { plus_start = 2, plus_count = 1, minus_start = -1, minus_count = -1 },
        { plus_start = 3, plus_count = 1, minus_start = -1, minus_count = -1 },
        { plus_start = 5, plus_count = 1, minus_start = -1, minus_count = -1 },
        { plus_start = 8, plus_count = 1, minus_start = -1, minus_count = -1 },
        { plus_start = 12, plus_count = 1, minus_start = -1, minus_count = -1 },
        { plus_start = 17, plus_count = 1, minus_start = -1, minus_count = -1 },
        { plus_start = 23, plus_count = 1, minus_start = -1, minus_count = -1 },
      },
      context = { 1, 2 },
      expected = {
        0, --  1| 1
        0, --  2| +
        0, --  3| +
        0, --  4| 1
        0, --  5| +
        0, --  6| 1
        0, --  7| 1
        0, --  8| +
        0, --  9| 1
        1, -- 10|   2
        0, -- 11| 1
        0, -- 12| +
        0, -- 13| 1
        1, -- 14|   2
        1, -- 15|   2
        0, -- 16| 1
        0, -- 17| +
        0, -- 18| 1
        1, -- 19|   2
        2, -- 20|
        1, -- 21|   2
        0, -- 22| 1
        0, -- 23| +
      },
    },
  },
  test = function(case)
    local levels =
      fold.get_levels_impl(case.hunks, case.context, #case.expected)
    testing.assert_list_eq(levels, case.expected)
  end,
}

return M
