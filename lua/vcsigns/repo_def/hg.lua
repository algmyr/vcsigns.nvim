local common = require "vcsigns.repo_def.common"

---@type VcsInterface
return {
  name = "Mercurial",
  detect = {
    cmd = function()
      return { "hg", "root" }
    end,
    check = common.check_and_extract_root,
  },
  show = {
    cmd = function(target)
      return {
        "hg",
        "cat",
        "--config",
        "extensions.color=!",
        "--rev",
        string.format(".~%d", target.commit),
        "--",
        target.file,
      }
    end,
    check = common.check_accept_any,
  },
  -- Rename resolution not implemented for Mercurial.
  resolve_rename = nil,
}
