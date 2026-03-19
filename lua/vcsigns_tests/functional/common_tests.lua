-- Common test definitions that work across all VCS systems.
-- These tests use the VcsAdapter interface to be VCS-agnostic.

local M = {}

local helpers = require "vcsigns_tests.functional.helpers"
local repo_mod = require "vcsigns.repo"
local state = require "vcsigns.state"
local testing = require "vclib.testing"

--- Generate detection test for a VCS adapter.
---@param adapter VcsAdapter
---@return table test_suite
function M.detection_tests(adapter)
  return adapter:wrap {
    test_cases = {
      detect_repo = {
        description = "Detect " .. adapter.name .. " repository and find root",
      },
    },
    test = function(repo, _)
      repo:write_file("test.txt", "line1\nline2\n")
      repo:commit_file("test.txt", "Initial commit")

      vim.cmd("edit " .. vim.fn.fnameescape(repo:path "test.txt"))
      local bufnr = vim.api.nvim_get_current_buf()

      local vcs = repo_mod.detect_vcs(bufnr)

      assert(vcs ~= nil, "Failed to detect " .. adapter.name .. " repository")
      assert(
        vcs.name == adapter.name,
        "Expected " .. adapter.name .. ", got " .. vcs.name
      )
      assert(
        vcs.root == repo.repo_dir,
        "Root mismatch: expected " .. repo.repo_dir .. ", got " .. vcs.root
      )

      vim.cmd "bdelete!"
    end,
  }
end

--- Generate show_file tests for a VCS adapter.
---@param adapter VcsAdapter
---@return table test_suite
function M.show_file_tests(adapter)
  return adapter:wrap {
    test_cases = {
      show_current_commit = {
        description = "Show file content at current commit",
        commit_offset = 0,
        expected_lines = { "version3" },
      },
      show_previous_commit = {
        description = "Show file content at previous commit",
        commit_offset = 1,
        expected_lines = { "version2" },
      },
      show_multiple_commits_back = {
        description = "Show file content at grandparent commit",
        commit_offset = 2,
        expected_lines = { "version1" },
      },
    },
    test = function(repo, case)
      local test_file = repo:path "test.txt"
      repo:write_file("test.txt", "version1\n")
      repo:commit_file("test.txt", "First commit")
      repo:write_file("test.txt", "version2\n")
      repo:commit_file("test.txt", "Second commit")
      repo:write_file("test.txt", "version3\n")
      repo:commit_file("test.txt", "Third commit")

      vim.cmd("edit " .. vim.fn.fnameescape(test_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local vcs = repo_mod.detect_vcs(bufnr)
      assert(vcs ~= nil, "Failed to detect " .. adapter.name .. " repository")
      state.repo_get(vcs.root).commit_offset = case.commit_offset

      local lines = helpers.wait_for_async(function()
        return repo_mod.show_file(bufnr, vcs)
      end)

      assert(lines ~= nil, "Expected content in commit")
      testing.assert_list_eq(
        lines,
        case.expected_lines,
        "File content mismatch"
      )

      vim.cmd "bdelete!"
    end,
  }
end

--- Generate error_handling tests for a VCS adapter.
---@param adapter VcsAdapter
---@return table test_suite
function M.error_handling_tests(adapter)
  return adapter:wrap {
    test_cases = {
      file_not_in_commit = {
        description = "Handle file that doesn't exist in target commit",
        repo_setup = function(repo)
          repo:write_file("dummy.txt", "dummy\n")
          repo:commit_file("dummy.txt", "Initial commit")
          repo:write_file("new.txt", "new content\n")
        end,
        file_to_edit = "new.txt",
      },
      new_file = {
        description = "Handle newly added file not yet in VCS",
        repo_setup = function(repo)
          repo:write_file("test.txt", "content\n")
          repo:commit_file("test.txt", "First commit")
          repo:remove_file "test.txt"
          repo:commit_all "Remove test.txt"
          repo:write_file("test.txt", "new content\n")
        end,
        file_to_edit = "test.txt",
      },
    },
    test = function(repo, case)
      case.repo_setup(repo)
      vim.cmd("edit " .. vim.fn.fnameescape(repo:path(case.file_to_edit)))
      local bufnr = vim.api.nvim_get_current_buf()
      local vcs = repo_mod.detect_vcs(bufnr)
      assert(vcs ~= nil, "Failed to detect " .. adapter.name .. " repository")

      -- File doesn't exist in current commit, should return empty file {}.
      local lines = helpers.wait_for_async(function()
        return repo_mod.show_file(bufnr, vcs)
      end)
      assert(lines ~= nil, "Expected empty table, got nil")
      assert(
        #lines == 0,
        "Expected empty file (0 lines), got " .. #lines .. " lines"
      )

      vim.cmd "bdelete!"
    end,
  }
end

function M.file_edge_case_tests(adapter)
  return adapter:wrap {
    test_cases = {
      empty_file = {
        description = "Handle empty files",
        file = {
          path = "empty.txt",
          content = "",
        },
        expected_lines = {},
      },
      whitespace_only = {
        description = "Handle files with only whitespace",
        file = {
          path = "whitespace.txt",
          content = "   \n\t\n  \n",
        },
        expected_lines = { "   ", "\t", "  " },
      },
      file_with_spaces = {
        description = "Handle file paths with spaces",
        file = {
          path = "file with spaces.txt",
          content = "content\n",
        },
        expected_lines = { "content" },
      },
    },
    test = function(repo, case)
      local test_file = repo:path(case.file.path)
      repo:write_file(case.file.path, case.file.content)
      repo:commit_file(case.file.path, "Test commit")
      local expected_content = case.expected_lines

      vim.cmd("edit " .. vim.fn.fnameescape(test_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local vcs = repo_mod.detect_vcs(bufnr)
      assert(vcs ~= nil, "Failed to detect git repository")

      local lines = helpers.wait_for_async(function()
        return repo_mod.show_file(bufnr, vcs)
      end)

      assert(lines ~= nil, "Expected content, got nil")
      assert(
        #lines == #expected_content,
        "Line count mismatch: expected "
          .. #expected_content
          .. ", got "
          .. #lines
      )
      for i = 1, #expected_content do
        assert(
          lines[i] == expected_content[i],
          "Line "
            .. i
            .. " mismatch: expected '"
            .. expected_content[i]
            .. "', got '"
            .. lines[i]
            .. "'"
        )
      end

      vim.cmd "bdelete!"
    end,
  }
end

--- Generate blame tests for a VCS adapter.
---@param adapter VcsAdapter
---@return table test_suite
function M.blame_tests(adapter)
  return adapter:wrap {
    test_cases = {
      basic_blame = {
        description = "Get blame annotations for a file",
        file_content = "line1\nline2\n\n\nline3\n",
        expected_line_count = 5,
      },
      single_line = {
        description = "Get blame for single-line file",
        file_content = "single line\n",
        expected_line_count = 1,
      },
      empty_file = {
        description = "Get blame for empty file",
        file_content = "",
        expected_line_count = 0,
      },
    },
    test = function(repo, case)
      local test_file = repo:path "blame_test.txt"
      repo:write_file("blame_test.txt", case.file_content)
      repo:commit_file("blame_test.txt", "Test commit")

      vim.cmd("edit " .. vim.fn.fnameescape(test_file))
      local bufnr = vim.api.nvim_get_current_buf()

      local vcs = repo_mod.detect_vcs(bufnr)
      assert(vcs ~= nil, "Failed to detect " .. adapter.name .. " repository")

      -- Get blame annotations with nil template (use defaults).
      local annotations = helpers.wait_for_async(function()
        if vcs.blame then
          local rel_path = vim.fn.fnamemodify(test_file, ":.")
          return vcs:blame(rel_path, nil)
        else
          return nil
        end
      end)

      if case.expected_line_count == 0 then
        -- Empty file should return empty annotations or nil.
        assert(
          annotations == nil or #annotations == 0,
          "Expected empty annotations for empty file"
        )
      else
        assert(annotations ~= nil, "Expected blame annotations, got nil")
        assert(
          #annotations == case.expected_line_count,
          "Line count mismatch: expected "
            .. case.expected_line_count
            .. ", got "
            .. #annotations
        )

        -- Verify line content matches the expected content.
        local lines = vim.split(case.file_content, "\n", { plain = true })
        -- Verify structure of each annotation.
        for i, ann in ipairs(annotations) do
          local label = string.format("Annotation %d", i)
          assert(ann.line_num ~= nil, label .. " missing line_num")
          assert(
            type(ann.line_num) == "number",
            label .. " line_num is not a number"
          )
          assert(ann.annotation ~= nil, label .. " missing annotation")
          assert(
            type(ann.annotation) == "string",
            label .. " annotation is not a string"
          )
          assert(ann.annotation ~= "", label .. " has empty annotation string")
          assert(ann.content ~= nil, "Annotation " .. i .. " missing content")
          assert(
            type(ann.content) == "string",
            label .. " content is not a string"
          )

          assert(
            ann.content == lines[i],
            string.format(
              "Line %d content mismatch: expected '%s', got '%s'",
              i,
              lines[i],
              ann.content
            )
          )
        end
      end

      vim.cmd "bdelete!"
    end,
  }
end

return M
