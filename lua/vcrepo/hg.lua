local common = require "vcrepo.common"
local util = require "vcrepo.util"
local run = require "vclib.run"

---@type VcsInterface
return {
  name = "Mercurial",
  detect = {
    cmd = function()
      return { "hg", "root" }
    end,
    check = common.check_and_extract_root,
  },
  show = function(target, root, lines_cb)
    -- stylua: ignore
    local cmd = {
      "hg", "cat", "--config", "extensions.color=!",
      "--rev", string.format(".~%d", target.commit),
      "--",
      target.file,
    }
    run.run_with_timeout(cmd, { cwd = root }, function(out)
      lines_cb(common.content_to_lines(out.stdout))
    end)
  end,
  needs_refresh = function(self, needs_refresh_cb)
    needs_refresh_cb(true)
  end,
  -- Rename resolution not implemented for Mercurial.
  resolve_rename = nil,
}
