local M = {}

local vcs_adapter = require "vcsigns_tests.functional.vcs_adapter"

local adapter = vcs_adapter.new "hg"
if not adapter.available then
  return M
end

return M
