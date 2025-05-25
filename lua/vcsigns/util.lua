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

function M.run_with_timeout(cmd, callback)
  if callback == nil then
    return vim.system(cmd, { timeout = 2000 })
  end

  return vim.system(cmd, { timeout = 2000 }, function(out)
    if out.code == 124 then
      M.util.verbose("Command timed out: " .. table.concat(cmd, " "), "run")
      return
    end
    vim.schedule(function()
      callback(out)
    end)
  end)
end

return M
