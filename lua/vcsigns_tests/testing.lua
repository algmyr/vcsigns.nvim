local M = {}

function M.assert_list_eq(a, b)
  assert(
    #a == #b,
    string.format("Lists have different lengths: %d vs %d", #a, #b)
  )
  local diff = ""
  for i = 1, #a do
    if a[i] ~= b[i] then
      diff = diff .. string.format("\n[%d]: %s ~= %s", i, a[i], b[i])
    end
  end
  if diff ~= "" then
    error("Lists differ:" .. diff)
  end
end

return M
