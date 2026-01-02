local common = require "vcsigns.repo_def.common"

---@type VcsInterface
return {
  name = "Git",
  detect = {
    cmd = function()
      return { "git", "rev-parse", "--show-toplevel" }
    end,
    check = common.check_and_extract_root,
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
