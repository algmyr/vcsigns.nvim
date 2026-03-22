-- JJ specific edge case tests.

local M = {}

local helpers = require "vcrepo_tests.functional.helpers"
local repo_mod = require "vcsigns.repo"
local state = require "vcsigns.state"
local testing = require "vclib.testing"
local vcs_adapter = require "vcrepo.testing.vcs_adapter"

local adapter = vcs_adapter.new "jj"
if not adapter.available then
  return M
end

M.jj_rename_resolution = adapter:wrap {
  test_cases = {
    follow_file_rename = {
      description = "Track file rename and get old content",
    },
  },
  ---@param repo VcsRepo
  ---@param _ table
  test = function(repo, _)
    -- Long common suffix is enough to trigger rename detection.
    local common_suffix = "0\n1\n2\n3\n4\n5\n6\n7\n8\n9"
    local v1 = "version 1\n" .. common_suffix
    local v2 = "version 2\n" .. common_suffix
    local v3 = "version 3\n" .. common_suffix
    local v1_lines = vim.split(v1, "\n", { plain = true })
    local v2_lines = vim.split(v2, "\n", { plain = true })
    repo:write_file("old_name.txt", v1)
    repo:commit_file("old_name.txt", "Original content")
    repo:write_file("old_name.txt", v2)
    repo:commit_file("old_name.txt", "Modify content")
    repo:run_cmd { "mv", "old_name.txt", "new_name.txt" }
    repo:commit_all "Rename file"
    repo:write_file("new_name.txt", v3)

    -- Open the renamed file
    vim.cmd("edit " .. vim.fn.fnameescape(repo:path "new_name.txt"))
    local bufnr = vim.api.nvim_get_current_buf()

    local vcs = repo_mod.detect_vcs(bufnr)
    assert(vcs ~= nil, "Failed to detect jj repository")

    local function content_at(offset)
      state.repo_get(vcs.root).commit_offset = offset
      return helpers.wait_for_async(function()
        return repo_mod.show_file(bufnr, vcs)
      end)
    end

    testing.assert_list_eq(
      content_at(0),
      v2_lines,
      "At 0, expected version 2 at current commit"
    )
    testing.assert_list_eq(
      content_at(1),
      v2_lines,
      "At 1, expected version 2 at previous commit"
    )
    testing.assert_list_eq(
      content_at(2),
      v1_lines,
      "At 2, expected version 1 pre rename"
    )

    vim.cmd "bdelete!"
  end,
}

return M
