local M = {}

local diff = require "vcsigns.diff"

-- Minus part doesn't matter for the hunk navigation tests.
--  1
--  2 A
--  3 A
--  4
--  5 B
--  6 B
--  7 B
--  8
--  9
-- 10 C
-- 11
local navigation_test_hunks = {
  { plus_start = 2, plus_count = 2, minus_start = -1, minus_count = -1 },
  { plus_start = 5, plus_count = 3, minus_start = -1, minus_count = -1 },
  { plus_start = 10, plus_count = 1, minus_start = -1, minus_count = -1 },
}

M.next_hunk = {
  test_cases = {
    { lnum = 1, expected_target = 2 },
    { lnum = 2, expected_target = 5 },
    { lnum = 3, expected_target = 5 },
    { lnum = 4, expected_target = 5 },
    { lnum = 5, expected_target = 10 },
    { lnum = 6, expected_target = 10 },
    { lnum = 7, expected_target = 10 },
    { lnum = 8, expected_target = 10 },
    { lnum = 9, expected_target = 10 },
    { lnum = 10, expected_target = nil },
    { lnum = 11, expected_target = nil },
    { lnum = 1, expected_target = 5, count = 2 },
    { lnum = 2, expected_target = 10, count = 2 },
    { lnum = 6, expected_target = 10, count = 2 },
  },
  test = function(case)
    local hunk =
      diff.next_hunk(case.lnum, navigation_test_hunks, case.count or 1)
    if not hunk then
      if case.expected_target == nil then
        return -- This is expected, no hunk found.
      end
      error "No hunk found"
    end
    assert(
      hunk.plus_start == case.expected_target,
      string.format(
        "Expected hunk at %d, got %d",
        case.expected_target,
        hunk.plus_start
      )
    )
  end,
}

M.prev_hunk = {
  test_cases = {
    { lnum = 1, expected_target = nil },
    { lnum = 2, expected_target = nil },
    { lnum = 3, expected_target = nil },
    { lnum = 4, expected_target = 2 },
    { lnum = 5, expected_target = 2 },
    { lnum = 6, expected_target = 2 },
    { lnum = 7, expected_target = 2 },
    { lnum = 8, expected_target = 5 },
    { lnum = 9, expected_target = 5 },
    { lnum = 10, expected_target = 5 },
    { lnum = 11, expected_target = 10 },
    { lnum = 11, expected_target = 5, count = 2 },
    { lnum = 10, expected_target = 2, count = 2 },
    { lnum = 4, expected_target = 2, count = 2 },
  },
  test = function(case)
    local hunk =
      diff.prev_hunk(case.lnum, navigation_test_hunks, case.count or 1)
    if not hunk then
      if case.expected_target == nil then
        return -- This is expected, no hunk found.
      end
      error "No hunk found"
    end
    assert(
      hunk.plus_start == case.expected_target,
      string.format(
        "Expected hunk at %d, got %d",
        case.expected_target,
        hunk.plus_start
      )
    )
  end,
}

M.cur_hunk = {
  test_cases = {
    { lnum = 2, expected_target = 2 },
    { lnum = 3, expected_target = 2 },
    { lnum = 4, expected_target = nil },
    { lnum = 5, expected_target = 5 },
    { lnum = 6, expected_target = 5 },
    { lnum = 7, expected_target = 5 },
    { lnum = 8, expected_target = nil },
    { lnum = 9, expected_target = nil },
    { lnum = 10, expected_target = 10 },
    { lnum = 11, expected_target = nil },
  },
  test = function(case)
    local hunk = diff.cur_hunk(case.lnum, navigation_test_hunks)
    if not hunk then
      if case.expected_target == nil then
        return -- This is expected, no hunk found.
      end
      error "No hunk found"
    end
    assert(
      hunk.plus_start == case.expected_target,
      string.format(
        "Expected hunk at %d, got %d",
        case.expected_target,
        hunk.plus_start
      )
    )
  end,
}

local deletion_test_hunks = {
  { plus_start = 0, plus_count = 0, minus_start = -1, minus_count = -1 },
  { plus_start = 4, plus_count = 0, minus_start = -1, minus_count = -1 },
}

M.cur_hunk_deletions = {
  test_cases = {
    { lnum = 1, expected_target = 0 },
    { lnum = 2, expected_target = nil },
    { lnum = 3, expected_target = nil },
    { lnum = 4, expected_target = 4 },
    { lnum = 5, expected_target = nil },
  },
  test = function(case)
    local hunk = diff.cur_hunk(case.lnum, deletion_test_hunks)
    if not hunk then
      if case.expected_target == nil then
        return -- This is expected, no hunk found.
      end
      error "No hunk found"
    end
    assert(
      hunk.plus_start == case.expected_target,
      string.format(
        "Expected hunk at %d, got %d",
        case.expected_target,
        hunk.plus_start
      )
    )
  end,
}

return M
