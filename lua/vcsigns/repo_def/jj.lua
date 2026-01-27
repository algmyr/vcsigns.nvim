local common = require "vcsigns.repo_def.common"
local util = require "vcsigns.util"

local function _jj_target(target)
  return string.format("roots(ancestors(@, %d))", target + 2)
end

local function _jj_exact_path(path)
  -- Most basic thing. Will fail if path contains a quote.
  -- If someone runs into this I will question their life choices.
  return 'file:"' .. path .. '"'
end

---@type VcsInterface
return {
  name = "Jujutsu",
  detect = {
    cmd = function()
      return { "jj", "--ignore-working-copy", "root" }
    end,
    check = common.check_and_extract_root,
  },
  show = function(target, root, lines_cb)
    local cmd = {
      "jj",
      "--ignore-working-copy",
      "file",
      "show",
      "-r",
      _jj_target(target.commit),
      "--",
      _jj_exact_path(target.file),
    }
    util.run_with_timeout(cmd, { cwd = root }, function(out)
      lines_cb(common.content_to_lines(out.stdout))
    end)
  end,
  resolve_rename = function(target, root, resolved_cb)
    local cmd = {
      "jj",
      "--ignore-working-copy",
      "diff",
      "-r",
      _jj_target(target.commit - 1) .. "::@",
      "-s",
      _jj_exact_path(target.file),
    }
    util.run_with_timeout(cmd, { cwd = root }, function(out)
      if out.code ~= 0 then
        resolved_cb(nil)
        return
      end
      if not out.stdout then
        resolved_cb(nil)
        return
      end
      local lines = vim.split(vim.trim(out.stdout), "\n")
      local move_spec = lines[#lines]:sub(3)
      local res, replacements = move_spec:gsub("{(.*) => (.*)}", "%1")
      if replacements == 0 then
        -- Not a rename.
        resolved_cb(nil)
        return
      end
      resolved_cb(res)
    end)
  end,
}
