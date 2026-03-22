local M = {}

local vcs_adapter = require "vcrepo.testing.vcs_adapter"

local adapter = vcs_adapter.new "git"
if not adapter.available then
  return M
end

return M
