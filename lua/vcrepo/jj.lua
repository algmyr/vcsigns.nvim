local common = require "vcrepo.common"
local util = require "vcrepo.util"
local patch = require "vclib.patch"
local run = require "vclib.run"

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
  detect = function(dir)
    -- Check if jj executable exists.
    if vim.fn.executable "jj" == 0 then
      return nil
    end

    local cmd = { "jj", "--ignore-working-copy", "root" }
    local out = run.run_with_timeout(cmd, { cwd = dir }):wait()
    if out.code ~= 0 or not out.stdout then
      return nil
    end
    return vim.trim(out.stdout)
  end,
  ---@async
  show = function(self, target)
    -- Get content at @ and reverse-apply diff to reconstruct target content.
    -- This works more generally than getting the content of the commit before
    -- which can fail if there are merges.

    -- stylua: ignore
    local current_cmd = {
      "jj", "--ignore-working-copy", "file", "show",
      "-r", "@",
      "--",
      _jj_exact_path(target.file),
    }
    local current_out = util.run_async(current_cmd, { cwd = self.root })
    local current_lines = common.content_to_lines(current_out.stdout)
    if not current_lines then
      return nil
    end

    -- stylua: ignore
    local diff_cmd = {
      "jj", "--ignore-working-copy", "diff",
      "--git",
      "-r", _jj_target(target.commit) .. "::@",
      "--",
      _jj_exact_path(target.file),
    }
    local diff_out = util.run_async(diff_cmd, { cwd = self.root })
    if not diff_out.stdout or diff_out.stdout == "" then
      -- No diff means file is unchanged.
      return current_lines
    end

    return _reverse_apply_patch(current_lines, diff_out.stdout)
  end,
  ---@async
  needs_refresh = function(self)
    local last_op_id = self._last_op_id

    -- stylua: ignore
    local cmd = {
      "jj", "--ignore-working-copy", "op", "log",
      "-n", "1",
      "--no-graph",
      "-T", "id",
    }
    local out = util.run_async(cmd, { cwd = self.root })
    local needs_refresh = true
    if out.code == 0 and out.stdout then
      local current_op_id = vim.trim(out.stdout)
      needs_refresh = (not last_op_id or last_op_id ~= current_op_id)
      self._last_op_id = current_op_id
    end
    return needs_refresh
  end,
  ---@async
  resolve_rename = function(self, target)
    -- stylua: ignore
    local cmd = {
      "jj", "--ignore-working-copy", "diff",
      "-r", _jj_target(target.commit) .. "::@",
      "-s",
      _jj_exact_path(target.file),
    }
    local out = util.run_async(cmd, { cwd = self.root })
    if out.code ~= 0 or not out.stdout then
      return nil
    end
    local lines = vim.split(vim.trim(out.stdout), "\n")
    local move_spec = lines[#lines]:sub(3)
    local res, replacements = move_spec:gsub("{(.*) => (.*)}", "%1")
    if replacements == 0 then
      -- Not a rename.
      return nil
    end
    return res
  end,
  ---@async
  blame = function(self, file, template)
    -- Default template: just the short change_id.
    local annotation_template = template or "commit.change_id().shortest(8)"

    local full_template = string.format(
      [[%s ++ "%s" ++ line_number ++ "%s" ++ content]],
      annotation_template,
      common.SEP,
      common.SEP
    )

    -- stylua: ignore
    local cmd = {
      "jj", "--ignore-working-copy", "file", "annotate",
      "-r", "@",
      "-T", full_template,
      "--",
      file,
    }

    local out = util.run_async(cmd, { cwd = self.root })
    if out.code ~= 0 or not out.stdout or out.stdout == "" then
      return nil
    end
    local raw_lines = vim.split(out.stdout, "\n", { plain = true })
    return common.parse_blame_annotations(raw_lines)
  end,
}
