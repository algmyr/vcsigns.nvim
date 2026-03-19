local common = require "vcrepo.common"
local util = require "vcrepo.util"
local run = require "vclib.run"

---@type VcsInterface
return {
  name = "Git",
  detect = function(dir)
    -- Check if git executable exists.
    if vim.fn.executable "git" == 0 then
      return nil
    end

    local cmd = { "git", "rev-parse", "--show-toplevel" }
    local out = run.run_with_timeout(cmd, { cwd = dir }):wait()
    if out.code ~= 0 or not out.stdout then
      return nil
    end
    return vim.trim(out.stdout)
  end,
  ---@async
  show = function(self, target)
    local cmd = {
      "git",
      "show",
      string.format("HEAD~%d", target.commit) .. ":./" .. target.file,
    }
    local out = util.run_async(cmd, { cwd = self.root })
    return common.content_to_lines(out.stdout)
  end,
  ---@async
  blame = function(self, file, template)
    -- Git does not support custom templates. Template must be nil.
    assert(template == nil, "Git blame does not support custom templates")

    -- Use line-porcelain format to get commit SHA and metadata.
    local cmd = { "git", "blame", "--line-porcelain", "--", file }

    local out = util.run_async(cmd, { cwd = self.root })
    if out.code ~= 0 or not out.stdout or out.stdout == "" then
      return nil
    end

    local raw_lines = vim.split(out.stdout, "\n", { plain = true })
    if raw_lines[#raw_lines] == "" then
      raw_lines[#raw_lines] = nil
    end

    local annotations = {}
    local i = 1
    while i <= #raw_lines do
      local commit_id, final_line_str = raw_lines[i]:match "^(%x+) %d+ (%d+)"
      assert(commit_id, "Failed to parse commit ID from git blame output")
      assert(
        final_line_str,
        "Failed to parse final line number from git blame output"
      )
      local final_line_num = tonumber(final_line_str)
      i = i + 1

      -- Metadata.
      local metadata = {}
      while i <= #raw_lines and not raw_lines[i]:match "^\t" do
        local header = raw_lines[i]
        local space_pos = header:find " "
        if space_pos then
          local key = header:sub(1, space_pos - 1)
          local value = header:sub(space_pos + 1)
          metadata[key] = value
        else
          metadata[header] = ""
        end
        i = i + 1
      end

      -- Content.
      assert(
        i <= #raw_lines and raw_lines[i]:match "^\t",
        "Expected content line in git blame output"
      )
      local content = raw_lines[i]:sub(2)
      i = i + 1

      -- Default: short SHA.
      local annotation = commit_id:sub(1, 8)
      table.insert(annotations, {
        line_num = final_line_num,
        annotation = annotation,
        content = content,
      })
    end

    return annotations
  end,
  ---@async
  needs_refresh = function(self)
    return true
  end,
  -- Rename resolution not implemented for git.
  resolve_rename = nil,
}
