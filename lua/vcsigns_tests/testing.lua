local M = {}

function M.assert_list_eq(actual, expected)
  assert(
    #actual == #expected,
    string.format("Lists have different lengths: %d vs %d", #actual, #expected)
  )
  local diff = ""
  for i = 1, #expected do
    if actual[i] ~= expected[i] then
      diff = diff
        .. string.format("\n[%d]: %s ~= %s", i, actual[i], expected[i])
    end
  end
  if diff ~= "" then
    error("Lists differ:" .. diff)
  end
end

return M
