local M = {}

local state = require "vcsigns.state"

--- Create a lualine module for VCSigns statistics.
---@return table A lualine module configuration table.
function M.lualine_module()
  return {
    "diff",
    source = function()
      return vim.b.vcsigns_stats
    end,
    on_click = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local lines = {}
      local vcs = state.get(bufnr).vcs.vcs
      lines[#lines + 1] = vcs and vcs.name or "No vcs detected"
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
