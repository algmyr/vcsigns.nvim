local common = require "vcsigns.repo_def.common"
local patch = require "vclib.patch"
local util = require "vcsigns.util"

--- Construct a jj revset for the nth ancestors of @.
---@param offset integer
---@return string
local function _jj_target(offset)
  return string.format("roots(ancestors(@, %d))", offset + 1)
end

--- Construct a jj fileset to match an exact file path.
---@param path string
---@return string
local function _jj_exact_path(path)
  -- Most basic thing. Will fail if path contains a quote.
  -- If someone runs into this I will question their life choices.
  return 'file:"' .. path .. '"'
end

--- Reverse apply a git-format patch to reconstruct the old file.
--- Assumes the patch contains exactly one file's changes.
---@param current_lines string[] The current file contents (at @).
---@param patch_output string The git diff output.
---@return string[]|nil The reconstructed old file contents, or nil on error.
local function _reverse_apply_patch(current_lines, patch_output)
  local parsed = patch.parse_single_file_patch(patch_output)

  if not parsed then
    -- No hunks found, file is unchanged.
    return current_lines
  end

  local inverted = patch.invert_patch(parsed)
  return patch.apply_patch(current_lines, inverted)
end

---@type VcsInterface
return {
  name = "Jujutsu",
  detect = {
    cmd = function()
      return { "jj", "--ignore-working-copy", "root" }
    end,
    check = common.check_and_extract_root,
  },
  show = function(target, root, lines_cb)
    -- Get content at @ and reverse-apply diff to reconstruct target content.
    -- This works more generally than getting the content of the commit before
    -- which can fail if there are merges.
    local current_cmd = {
      "jj",
      "--ignore-working-copy",
      "file",
      "show",
      "-r",
      "@",
      "--",
      _jj_exact_path(target.file),
    }
    util.run_with_timeout(current_cmd, { cwd = root }, function(current_out)
      local current_lines = common.content_to_lines(current_out.stdout)
      if not current_lines then
        lines_cb(nil)
        return
      end

      local diff_cmd = {
        "jj",
        "--ignore-working-copy",
        "diff",
        "--git",
        "-r",
        _jj_target(target.commit) .. "::@",
        "--",
        _jj_exact_path(target.file),
      }
      util.run_with_timeout(diff_cmd, { cwd = root }, function(diff_out)
        if not diff_out.stdout or diff_out.stdout == "" then
          -- No diff means file is unchanged.
          lines_cb(current_lines)
          return
        end

        local old_lines = _reverse_apply_patch(current_lines, diff_out.stdout)
        lines_cb(old_lines)
      end)
    end)
  end,
  resolve_rename = function(target, root, resolved_cb)
    local cmd = {
      "jj",
      "--ignore-working-copy",
      "diff",
      "-r",
      _jj_target(target.commit) .. "::@",
      "-s",
      _jj_exact_path(target.file),
    }
    util.run_with_timeout(cmd, { cwd = root }, function(out)
      if out.code ~= 0 then
        resolved_cb(nil)
        return
      end
      if not out.stdout then
        resolved_cb(nil)
        return
      end
      local lines = vim.split(vim.trim(out.stdout), "\n")
      local move_spec = lines[#lines]:sub(3)
      local res, replacements = move_spec:gsub("{(.*) => (.*)}", "%1")
      if replacements == 0 then
        -- Not a rename.
        resolved_cb(nil)
        return
      end
      resolved_cb(res)
    end)
  end,
}
