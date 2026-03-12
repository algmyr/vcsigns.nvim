local common = require "vcsigns.repo_def.common"
local util = require "vcsigns.util"
local run = require "vclib.run"

---@type VcsInterface
return {
  name = "Git",
  detect = {
    cmd = function()
      return { "git", "rev-parse", "--show-toplevel" }
    end,
    check = common.check_and_extract_root,
  },
  show = function(target, root, lines_cb)
    local cmd = {
      "git",
      "show",
      string.format("HEAD~%d", target.commit) .. ":./" .. target.file,
    }
    run.run_with_timeout(cmd, { cwd = root }, function(out)
      lines_cb(common.content_to_lines(out.stdout))
    end)
  end,
  needs_refresh = function(self, needs_refresh_cb)
    needs_refresh_cb(true)
  end,
  -- Rename resolution not implemented for git.
  resolve_rename = nil,
}
