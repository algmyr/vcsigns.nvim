local M = {}

if not table.unpack then
  table.unpack = unpack
end

local diff = require "vcsigns_tests.diff"

function M.run()
  for suite_name, test_suite in pairs(diff) do
    local suite_failed = 0
    local suite_total = 0
    local test_cases = test_suite.test_cases
    local test_function = test_suite.test
    for case_name, case in pairs(test_cases) do
      local full_test_name = string.format("%s__%s", suite_name, case_name)

      local status, err = pcall(function()
        test_function(case)
      end)
      suite_total = suite_total + 1
      if not status then
        suite_failed = suite_failed + 1
        print(string.format("Test %s failed: %s", full_test_name, err))
      end
    end

    if suite_failed == 0 then
      print(
        string.format(
          "All tests in %s passed (%d tests)",
          suite_name,
          suite_total
        )
      )
    else
      print(
        string.format(
          "%d/%d tests failed in %s",
          suite_failed,
          suite_total,
          suite_name
        )
      )
    end
  end
end

return M
