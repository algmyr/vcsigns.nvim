local common = require "vcsigns.repo_def.common"

local function _jj_target(target)
  return string.format("roots(ancestors(@, %d))", target + 2)
end

---@type Vcs
return {
  name = "Jujutsu",
  detect = {
    cmd = function()
      return { "jj", "--ignore-working-copy", "root" }
    end,
    check = common.check_successful_command,
  },
  show = {
    cmd = function(target)
      return {
        "jj",
        "--ignore-working-copy",
        "file",
        "show",
        "-r",
        _jj_target(target.commit),
        "--",
        target.file,
      }
    end,
    check = common.check_accept_any,
  },
  resolve_rename = {
    cmd = function(target)
      return {
        "jj",
        "--ignore-working-copy",
        "diff",
        "-r",
        _jj_target(target.commit - 1) .. "::@",
        "-s",
        target.file,
      }
    end,
    extract = function(out, _)
      if out.code ~= 0 then
        return nil
      end
      if not out.stdout then
        return nil
      end
      local lines = vim.split(vim.trim(out.stdout), "\n")
      local move_spec = lines[#lines]:sub(3)
      local res, replacements = move_spec:gsub("{(.*) => (.*)}", "%1")
      if replacements == 0 then
        -- Not a rename.
        return nil
      end
      return res
    end,
  },
}
