local common = require "vcrepo.common"
local run = require "vclib.run"

---@type VcsInterface
return {
  name = "Git",
  detect = function(dir)
    -- Check if git executable exists.
    if vim.fn.executable "git" == 0 then
      return nil
    end

    local cmd = { "git", "rev-parse", "--show-toplevel" }
    local out = run.run_with_timeout(cmd, { cwd = dir }):wait()
    if out.code ~= 0 or not out.stdout then
      return nil
    end
    return vim.trim(out.stdout)
  end,
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
