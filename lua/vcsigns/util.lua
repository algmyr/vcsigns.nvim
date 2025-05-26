local M = {}

function M.verbose(msg, label)
  if vim.o.verbose ~= 0 then
    local l = label and ":" .. label or ""
    if type(msg) == "table" then
      print("[vcsigns" .. l .. "] " .. vim.inspect(msg))
    else
      print("[vcsigns" .. l .. "] " .. msg)
    end
  end
end

function M.run_with_timeout(cmd, opts, callback)
  vim.print(cmd)
  require("vcsigns").util.verbose(
    "Running command: " .. table.concat(cmd, " "),
    "run_with_timeout"
  )
  local merged_opts = vim.tbl_deep_extend("force", { timeout = 2000 }, opts)
  if callback == nil then
    return vim.system(cmd, merged_opts)
  end

  return vim.system(cmd, merged_opts, function(out)
    if out.code == 124 then
      M.util.verbose("Command timed out: " .. table.concat(cmd, " "), "run")
      return
    end
    vim.schedule(function()
      callback(out)
    end)
  end)
end

function M.file_dir(bufnr)
  return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p:h")
end

return M
