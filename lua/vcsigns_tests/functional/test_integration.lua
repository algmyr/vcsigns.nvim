local M = {}

local helpers = require "vcsigns_tests.functional.helpers"
local repo_mod = require "vcsigns.repo"
local diff = require "vcsigns.diff"
local sign = require "vcsigns.sign"
local testing = require "vclib.testing"
local vcs_adapter = require "vcsigns_tests.functional.vcs_adapter"

-- Use git for integration tests.
local git_adapter = vcs_adapter.new "git"
if not git_adapter.available then
  return M
end

local function assert_hunk(hunk, expected_minus, expected_plus)
  assert(
    hunk.minus_count == expected_minus,
    "Expected minus_count " .. expected_minus .. ", got " .. hunk.minus_count
  )
  assert(
    hunk.plus_count == expected_plus,
    "Expected plus_count " .. expected_plus .. ", got " .. hunk.plus_count
  )
end

M.diff_computation = git_adapter:wrap {
  test_cases = {
    added_lines = {
      description = "Compute diff for added lines",
      lines_before = [[
        line1
        line2
      ]],
      lines_after = [[
        line1
        line2
        added1
        added2
      ]],
      check_hunks = function(hunks)
        assert(#hunks == 1, "Expected 1 hunk, got " .. #hunks)
        assert_hunk(hunks[1], 0, 2)
      end,
    },
    changed_lines = {
      description = "Compute diff for changed lines",
      lines_before = [[
        line1
        line2
        line3
      ]],
      lines_after = [[
        line1
        modified
        line3
      ]],
      check_hunks = function(hunks)
        assert(#hunks == 1, "Expected 1 hunk, got " .. #hunks)
        assert_hunk(hunks[1], 1, 1)
      end,
    },
    deleted_lines = {
      description = "Compute diff for deleted lines",
      lines_before = [[
        line1
        line2
        line3
        line4
      ]],
      lines_after = [[
        line1
        line4
      ]],
      check_hunks = function(hunks)
        assert(#hunks == 1, "Expected 1 hunk, got " .. #hunks)
        assert_hunk(hunks[1], 2, 0)
      end,
    },
    mixed_changes = {
      description = "Compute diff for mixed add/change/delete",
      lines_before = [[
        line1
        line2
        line3
        line4
      ]],
      lines_after = [[
        line1
        changed
        line3
        line4
        added
      ]],
      check_hunks = function(hunks)
        assert(#hunks == 2, "Expected 2 hunks, got " .. #hunks)
        assert_hunk(hunks[1], 1, 1)
        assert_hunk(hunks[2], 0, 1)
      end,
    },
  },
  test = function(repo, case)
    local lines_before = testing.dedent(case.lines_before)
    local lines_after = testing.dedent(case.lines_after)
    repo:write_file("test.txt", lines_before)
    repo:commit_file("test.txt", "Initial commit")
    repo:write_file("test.txt", lines_after)

    vim.cmd("edit " .. vim.fn.fnameescape(repo:path "test.txt"))
    local bufnr = vim.api.nvim_get_current_buf()

    local vcs = repo_mod.detect_vcs(bufnr)
    assert(vcs ~= nil, "Failed to detect git repository")

    local vcs_lines = helpers.wait_for_callback(function(cb)
      repo_mod.show_file(bufnr, vcs, cb)
    end)
    assert(vcs_lines ~= nil, "Failed to get VCS content")
    local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local hunks = diff.compute_diff(vcs_lines, buf_lines)

    assert(hunks ~= nil, "Failed to compute hunks")
    assert(#hunks > 0, "Expected hunks, got none")
    case.check_hunks(hunks)

    vim.cmd "bdelete!"
  end,
}

local function assert_sign(signs, line_num, expected_type)
  if expected_type == nil then
    assert(
      signs[line_num] == nil,
      "Expected no sign at line " .. line_num .. ", got one"
    )
    return
  end
  local s = signs[line_num]
  assert(s ~= nil, "Expected sign at line " .. line_num .. ", got nil")
  assert(
    bit.band(s.type, expected_type) ~= 0,
    "Expected sign type " .. expected_type .. " at line " .. line_num
  )
end

M.sign_placement = git_adapter:wrap {
  test_cases = {
    signs_for_additions = {
      description = "Place ADD signs for new lines",
      lines_before = [[
        line1
        line2
      ]],
      lines_after = [[
        line1
        line2
        added
      ]],
      check_signs = function(signs)
        assert_sign(signs, 1, nil)
        assert_sign(signs, 2, nil)
        assert_sign(signs, 3, sign.SignType.ADD)
      end,
    },
    signs_for_changes = {
      description = "Place CHANGE signs for modified lines",
      lines_before = [[
        line1
        line2
        line3
      ]],
      lines_after = [[
        line1
        modified
        line3
      ]],
      check_signs = function(signs)
        assert_sign(signs, 1, nil)
        assert_sign(signs, 2, sign.SignType.CHANGE)
        assert_sign(signs, 3, nil)
      end,
    },
    signs_for_deletions = {
      description = "Place DELETE signs for removed lines",
      lines_before = [[
        line1
        line2
        line3
      ]],
      lines_after = [[
        line1
        line3
      ]],
      check_signs = function(signs)
        assert_sign(signs, 1, sign.SignType.DELETE_BELOW)
        assert_sign(signs, 2, nil)
      end,
    },
  },
  test = function(repo, case)
    local lines_before = testing.dedent(case.lines_before)
    local lines_after = testing.dedent(case.lines_after)
    repo:write_file("test.txt", lines_before)
    repo:commit_file("test.txt", "Initial commit")
    repo:write_file("test.txt", lines_after)

    vim.cmd("edit " .. vim.fn.fnameescape(repo:path "test.txt"))
    local bufnr = vim.api.nvim_get_current_buf()

    local vcs = repo_mod.detect_vcs(bufnr)
    assert(vcs ~= nil, "Failed to detect git repository")
    local vcs_lines = helpers.wait_for_callback(function(cb)
      repo_mod.show_file(bufnr, vcs, cb)
    end)

    local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local hunks = diff.compute_diff(vcs_lines, buf_lines)

    local result = sign.compute_signs(hunks, #buf_lines)

    assert(result ~= nil, "Failed to compute signs")
    assert(result.signs ~= nil, "Signs table is nil")

    case.check_signs(result.signs)

    vim.cmd "bdelete!"
  end,
}

M.target_commit_switching = git_adapter:wrap {
  test_cases = {
    switch_to_previous = {
      description = "Switch target from HEAD to HEAD~1",
    },
  },
  test = function(repo, _)
    repo:write_file("test.txt", "version1\n")
    repo:commit_file("test.txt", "First")
    repo:write_file("test.txt", "version2\n")
    repo:commit_file("test.txt", "Second")
    repo:write_file("test.txt", "version3\n")
    repo:commit_file("test.txt", "Third")

    vim.cmd("edit " .. vim.fn.fnameescape(repo:path "test.txt"))
    local bufnr = vim.api.nvim_get_current_buf()

    local vcs = repo_mod.detect_vcs(bufnr)
    assert(vcs ~= nil, "Failed to detect git repository")
    local state = require "vcsigns.state"

    state.repo_get(vcs.root).commit_offset = 0
    local lines_at_head = helpers.wait_for_callback(function(cb)
      repo_mod.show_file(bufnr, vcs, cb)
    end)

    assert(lines_at_head ~= nil, "Failed to get HEAD content")
    assert(lines_at_head[1] == "version3", "Expected version3 at HEAD")

    state.repo_get(vcs.root).commit_offset = 1
    local lines_at_head1 = helpers.wait_for_callback(function(cb)
      repo_mod.show_file(bufnr, vcs, cb)
    end)

    assert(lines_at_head1 ~= nil, "Failed to get HEAD~1 content")
    assert(lines_at_head1[1] == "version2", "Expected version2 at HEAD~1")

    vim.cmd "bdelete!"
  end,
}

M.empty_diff = git_adapter:wrap {
  test_cases = {
    no_changes = {
      description = "Handle case where buffer matches VCS",
    },
  },
  test = function(repo, _)
    repo:write_file("test.txt", "unchanged\n")
    repo:commit_file("test.txt", "Initial")

    vim.cmd("edit " .. vim.fn.fnameescape(repo:path "test.txt"))
    local bufnr = vim.api.nvim_get_current_buf()

    local vcs = repo_mod.detect_vcs(bufnr)
    local vcs_lines = helpers.wait_for_callback(function(cb)
      repo_mod.show_file(bufnr, vcs, cb)
    end)

    local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local hunks = diff.compute_diff(vcs_lines, buf_lines)

    assert(hunks ~= nil, "Hunks should not be nil")
    assert(#hunks == 0, "Expected no hunks for unchanged file, got " .. #hunks)

    vim.cmd "bdelete!"
  end,
}

return M
