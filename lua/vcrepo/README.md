Core VCS (Version Control System) abstraction layer for Neovim plugins.

## Components

- **vcrepo.common** - Core VCS interface types and utilities
- **vcrepo.git** - Git implementation
- **vcrepo.jj** - Jujutsu implementation  
- **vcrepo.hg** - Mercurial implementation
- **vcrepo.util** - Command execution utilities
- **vcrepo.testing** - Test utilities for VCS-agnostic testing

## Key Abstractions

### VcsInterface

Defines the contract that all VCS implementations must follow:

- `name` - Human-readable VCS name
- `detect` - Detection logic to find repositories
- `show` - Retrieve file content at a specific commit
- `blame` - Get blame annotations for a file
- `needs_refresh` - Optional optimization to check if refresh needed
- `resolve_rename` - Optional rename resolution support

### Target

Represents a file at a specific commit:

- `commit` - Commit offset (0 = HEAD, 1 = HEAD~1, etc.)
- `file` - Relative path from repo root
- `path` - Absolute file path
