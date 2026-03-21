local common = require "vcrepo.common"
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
  show = function(self, target, lines_cb)
    -- stylua: ignore
    local cmd = {
      "hg", "cat", "--config", "extensions.color=!",
      "--rev", string.format(".~%d", target.commit),
      "--",
      target.file,
    }
    run.run_with_timeout(cmd, { cwd = self.root }, function(out)
      lines_cb(common.content_to_lines(out.stdout))
    end)
  end,
  needs_refresh = function(self, needs_refresh_cb)
    needs_refresh_cb(true)
  end,
  -- Rename resolution not implemented for Mercurial.
  resolve_rename = nil,
  blame = function(self, file, template, annotations_cb)
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

    run.run_with_timeout(cmd, { cwd = self.root }, function(out)
      if out.code ~= 0 or not out.stdout or out.stdout == "" then
        annotations_cb(nil)
        return
      end
      local raw_lines = vim.split(out.stdout, "\n", { plain = true })
      local annotations = common.parse_blame_annotations(raw_lines)
      annotations_cb(annotations)
    end)
  end,
}
