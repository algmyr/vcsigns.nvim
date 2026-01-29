local M = {}

local testing = require "vclib.testing"

function M.run()
  local test_modules = {
    "vcsigns_tests.hunkops",
    "vcsigns_tests.sign",
  }
  testing.run_tests(test_modules)
end

function M.run_functional()
  require("vcsigns_tests.functional").run()
end

function M.run_all()
  print "Running unit tests..."
  M.run()
  print "\nRunning functional tests..."
  M.run_functional()
end

return M
