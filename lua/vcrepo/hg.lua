local common = require "vcrepo.common"
local util = require "vcrepo.util"
local run = require "vclib.run"

--- Construct a revset for the target commit.
---@param target TargetRevision The target containing anchor and offset.
---@return string
local function _diffbase(target_rev)
  if target_rev.revset then
    return target_rev.revset
  end
  return string.format("(%s)~%d", target_rev.anchor, target_rev.offset)
end

---@type VcsInterface
return {
  name = "Mercurial",
  head_revision = ".",
  detect = function(dir)
    -- Check if hg executable exists.
    if vim.fn.executable "hg" == 0 then
      return nil
    end

    local cmd = { "hg", "root" }
    local out = run.run_with_timeout(cmd, { cwd = dir }):wait()
    if out.code ~= 0 or not out.stdout then
      return nil
    end
    return vim.trim(out.stdout)
  end,
  ---@async
  show = function(self, target)
    target = common.resolve_target(self, target)
    local revset = _diffbase(target.rev)
    -- stylua: ignore
    local cmd = {
      "hg", "cat", "--config", "extensions.color=!",
      "--rev", revset,
      "--",
      target.file,
    }
    local out = util.run_async(cmd, { cwd = self.root })
    return common.content_to_lines(out.stdout)
  end,
  ---@async
  get_changed_files = function(self, target_rev)
    target_rev = common.resolve_target_revision(self, target_rev)
    local revset = _diffbase(target_rev) .. "~1"
    local cmd = {
      "hg",
      "status",
      "--no-status",
      "--rev",
      string.format("%s:%s", revset, target_rev.anchor),
    }
    local out = util.run_async(cmd, { cwd = self.root })
    return common.process_diff_result(out, self.root, target_rev)
  end,
  ---@async
  needs_refresh = function(self)
    return true
  end,
  -- Rename resolution not implemented for Mercurial.
  resolve_rename = nil,
  ---@async
  blame = function(self, file, template)
    -- Default template: just the short node hash.
    local annotation_template = template or "{node|short}"

    -- Full template: iterate over lines and output "annotation#SEP#lineno#SEP#line"
    local full_template = string.format(
      '{lines %% "%s%s{lineno}%s{line}\\n"}',
      annotation_template,
      common.SEP,
      common.SEP
    )

    local cmd = { "hg", "annotate", "-T", full_template, "--", file }

    local out = util.run_async(cmd, { cwd = self.root })
    if out.code ~= 0 or not out.stdout or out.stdout == "" then
      return nil
    end
    local raw_lines = vim.split(out.stdout, "\n", { plain = true })
    return common.parse_blame_annotations(raw_lines)
  end,
}
