local common = require "vcsigns.repo_def.common"

---@type Vcs
return {
  name = "Git",
  detect = {
    cmd = function()
      return { "git", "rev-parse", "--is-inside-work-tree" }
    end,
    check = common.check_successful_command,
  },
  show = {
    cmd = function(target)
      return {
        "git",
        "show",
        string.format("HEAD~%d", target.commit) .. ":./" .. target.file,
      }
    end,
    check = common.check_accept_any,
  },
  -- Rename resolution not implemented for git.
  resolve_rename = nil,
}
