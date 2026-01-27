local common = require "vcsigns.repo_def.common"
local util = require "vcsigns.util"

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
    local cmd = {
      "hg",
      "cat",
      "--config",
      "extensions.color=!",
      "--rev",
      string.format(".~%d", target.commit),
      "--",
      target.file,
    }
    util.run_with_timeout(cmd, { cwd = root }, function(out)
      lines_cb(common.content_to_lines(out.stdout))
    end)
  end,
  -- Rename resolution not implemented for Mercurial.
  resolve_rename = nil,
}
