local M = {}

local testing = require "vclib.testing"

function M.run()
  local test_modules = {
    "vcsigns_tests.functional.test_git",
    "vcsigns_tests.functional.test_jj",
    "vcsigns_tests.functional.test_hg",
    "vcsigns_tests.functional.test_integration",
  }
  testing.run_tests(test_modules)
end

return M
