# VCSigns.nvim

> [!WARNING]
> This is very much a WIP and bugs are likely.
> It's at a state where I use it for my personal use and at work,
> but notably that only involves linux systems, so behavior on other
> systems could have issues. Fixes for such issues are welcome!

VCS agnostic vcs signs for your sign gutter, heavily inspired by vim-signify.

This plugin only relies on being able to ask for file contents at a specific
commit to be able to construct a diff, this means that adding new vcs
definitions should be straightforward.

Currently definitions for jujutsu, git and mercurial are included.
The jujutsu one is the most well tested, but since very little logic of the vcs
is depended on the core machinery should be robust across all of them.

## Features

* Showing diff signs in your sign gutter.
* Easy switching of the target commit for the diff.
* Folding of non-diff areas.
* Navigating between hunks.
* Undoing the hunk under the cursor.
* Showing the diff (plus lines and minus lines) for the hunk under the cursor.

### Not yet implemented

* Hunk text objects.
* Expose diff stats (add/removed/modified) for use in status line or similar.
* Custom fold text.
* Documentation.

## Flashy screenshots or recordings?
TBD, maybe.

## Example config
For a documented default config, have a look inside `init.lua`.

### Lazy
```
{
  'algmyr/vcsigns.nvim',
  config = function()
    require('vcsigns').setup {
      target_commit = 1,  -- Nice default for jj with new+squash flow.
    }

    local function map(mode, lhs, rhs, desc, opts)
      local options = { noremap = true, silent = true, desc = desc }
      if opts then options = vim.tbl_extend('force', options, opts) end
      vim.keymap.set(mode, lhs, rhs, options)
    end

    map('n', '[r', function() require('vcsigns').actions.target_older_commit(0, vim.v.count1) end, 'Move diff target back')
    map('n', ']r', function() require('vcsigns').actions.target_newer_commit(0, vim.v.count1) end, 'Move diff target forward')
    map('n', '[c', function() require('vcsigns').actions.prev_hunk(0, vim.v.count1) end, 'Go to previous hunk')
    map('n', ']c', function() require('vcsigns').actions.next_hunk(0, vim.v.count1) end, 'Go to next hunk')
    map('n', '[C', function() require('vcsigns').actions.prev_hunk(0, 9999) end, 'Go to first hunk')
    map('n', ']C', function() require('vcsigns').actions.next_hunk(0, 9999) end, 'Go to last hunk')
    map('n', '<leader>su', function() require('vcsigns').actions.hunk_undo(0) end, 'Undo the hunk under the cursor')
    map('n', '<leader>sd', function() require('vcsigns').actions.show_diff(0) end, 'Show diff of hunk under the cursor')
  end,
}
```
