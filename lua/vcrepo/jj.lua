local common = require "vcrepo.common"
local util = require "vcrepo.util"
local patch = require "vclib.patch"
local run = require "vclib.run"

--- Construct a revset for the target commit.
---@param target TargetRevision The target containing anchor and offset.
---@return string
local function _diffbase(target_rev)
  if target_rev.revset then
    return target_rev.revset
  end
  return string.format(
    "roots(ancestors(" .. target_rev.anchor .. ", %d))",
    target_rev.offset + 1
  )
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

local function _flatten(seqs)
  local result = {}
  for _, seq in ipairs(seqs) do
    for _, item in ipairs(seq) do
      result[#result + 1] = item
    end
  end
  return result
end

---@param target_rev TargetRevision
---@param args string[] Extra args.
---@param files string[] File paths to include in the diff.
local function _diff_cmd(target_rev, args, files)
  local diffrev = _diffbase(target_rev)
  return _flatten {
    {
      "jj",
      "--ignore-working-copy",
      "diff",
      "-r",
      diffrev .. "::(" .. target_rev.anchor .. ")",
    },
    args,
    { "--" },
    files,
  }
end

---@type VcsInterface
return {
  name = "Jujutsu",
  head_revision = "@",
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
    target = common.resolve_target(self, target)
    -- stylua: ignore

    local current_cmd = {
      "jj", "--ignore-working-copy", "file", "show",
      "-r", target.rev.anchor,
      "--",
      _jj_exact_path(target.file),
    }
    local current_out = util.run_async(current_cmd, { cwd = self.root })
    local current_lines = common.content_to_lines(current_out.stdout)
    if not current_lines then
      return nil
    end

    -- Special case: offset=-1 means we want the content at anchor itself.
    if target.rev.offset == -1 then
      return current_lines
    end
    
    -- For offset >= 0, reverse-apply diff.
    -- This works more generally than getting the content of the commit before
    -- which can fail if there are merges.
    -- stylua: ignore
    local diff_cmd = _diff_cmd(target.rev, { "--git" }, { _jj_exact_path(target.file) })
    local diff_out = util.run_async(diff_cmd, { cwd = self.root })
    if not diff_out.stdout or diff_out.stdout == "" then
      -- No diff means file is unchanged.
      return current_lines
    end

    return _reverse_apply_patch(current_lines, diff_out.stdout)
  end,
  ---@async
  get_changed_files = function(self, target_rev)
    target_rev = common.resolve_target_revision(self, target_rev)
    local cmd = _diff_cmd(target_rev, { "--name-only" }, {})
    local out = util.run_async(cmd, { cwd = self.root })
    return common.process_diff_result(out, self.root, target_rev)
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
    target = common.resolve_target(self, target)
    local target_rev = _diffbase(target.rev)
    
    -- stylua: ignore
    local cmd = _diff_cmd(target.rev, { "-s" }, { _jj_exact_path(target.file) })
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
