local M = {}

function M.lualine_module()
  return {
    "diff",
    source = function()
      return vim.b.vcsigns_stats
    end,
    on_click = function()
      local lines = {}
      lines[#lines + 1] = vim.b.vcsigns_vcs and vim.b.vcsigns_vcs.name
        or "No vcs detected"
      if vim.b.vcsigns_resolved_rename then
        lines[#lines + 1] = "File rename detected:"
        lines[#lines + 1] = string.format(
          "  %s -> %s",
          vim.b.vcsigns_resolved_rename.from,
          vim.b.vcsigns_resolved_rename.to
        )
      end
      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, {
        title = "VCSigns",
        timeout = 3000,
      })
    end,
  }
end

return M
