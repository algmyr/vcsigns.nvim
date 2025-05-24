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

return M
