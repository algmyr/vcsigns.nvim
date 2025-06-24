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
  * Shows diffs compared to your current buffer, instant feedback.
* Easy switching of the target commit for the diff.
* Folding of non-diff areas.
* Navigating between hunks.
* Undoing the hunk under the cursor.
* Showing inline diffs (plus lines and minus lines) for hunks,
  with fine grained diffs within hunks.

### Not yet implemented

* Custom fold text.

## Example config
For a documented default config, have a look inside `init.lua`.

### Lazy
```
{
  'algmyr/vcsigns.nvim',
  dependencies = { 'algmyr/vclib.nvim' },
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
    map('n', '[c', function() require('vcsigns').actions.hunk_prev(0, vim.v.count1) end, 'Go to previous hunk')
    map('n', ']c', function() require('vcsigns').actions.hunk_next(0, vim.v.count1) end, 'Go to next hunk')
    map('n', '[C', function() require('vcsigns').actions.hunk_prev(0, 9999) end, 'Go to first hunk')
    map('n', ']C', function() require('vcsigns').actions.hunk_next(0, 9999) end, 'Go to last hunk')
    map('n', '<leader>su', function() require('vcsigns').actions.hunk_undo(0) end, 'Undo hunks in range')
    map('n', '<leader>sd', function() require('vcsigns').actions.toggle_hunk_diff(0) end, 'Show hunk diffs inline in the current buffer')
  end,
}
```

## Screenshots
Screenshots are with my own theme
[vim-wombat-lua](https://github.com/algmyr/vim-wombat-lua)\
which has highlight groups overridden.

### Gutter signs and lualine stats
![Gutter signs and lualine stats](https://github.com/user-attachments/assets/0182fb39-134c-46da-a794-30fb5cfb6ac8)

### Fold around diffs
![Fold around diffs](https://github.com/user-attachments/assets/92d37755-078e-4702-9177-7a00dc1fc755)

### Inline diff view
![Inline diff view](https://github.com/user-attachments/assets/1bcc093d-eed2-4be6-80b2-68c83f68805e)
