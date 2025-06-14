local common = require "vcsigns.repo_def.common"

---@type Vcs
return {
  name = "Mercurial",
  detect = {
    cmd = function()
      return { "hg", "root" }
    end,
    check = common.check_successful_command,
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
}
