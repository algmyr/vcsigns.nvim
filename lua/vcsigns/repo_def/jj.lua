local common = require "vcsigns.repo_def.common"

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
        _jj_exact_path(target.file),
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
        _jj_exact_path(target.file),
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
