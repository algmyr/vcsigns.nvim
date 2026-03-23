local common = require "vcrepo.common"
local util = require "vcrepo.util"
local run = require "vclib.run"

---@type VcsInterface
return {
  name = "Mercurial",
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
    local anchor = target.anchor or "."
    local revset = string.format("(%s)~%d", anchor, target.offset)
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
