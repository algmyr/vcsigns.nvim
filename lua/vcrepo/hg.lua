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
