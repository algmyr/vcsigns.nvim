Core VCS (Version Control System) abstraction layer for Neovim plugins.

# Components

- **vcrepo** (init.lua) - Public API with VcsHandle and VCS registry
- **vcrepo.common** - Core VCS interface types and utilities (internal)
- **vcrepo.git** - Git implementation (internal)
- **vcrepo.jj** - Jujutsu implementation (internal)  
- **vcrepo.hg** - Mercurial implementation (internal)
- **vcrepo.util** - Command execution utilities (internal)
- **vcrepo.testing** - Test utilities for VCS-agnostic testing

## Key Abstractions

### VcsHandle (Public API)

The public interface returned by `vcrepo.detect()`:

- `name` - Human-readable VCS name
- `root` - Repository root directory
- `show_file(target, opts)` - Retrieve file content with optional rename following
- `blame(file, template)` - Get blame annotations
- `needs_refresh()` - Check if VCS state changed compared to the last call

### VcsInterface (Internal)

Internal contract that VCS implementations must follow:

- `name` - Human-readable VCS name
- `detect` - Detection logic to find repositories
- `show` - Retrieve file content at a specific commit
- `blame` - Get blame annotations for a file (optional)
- `needs_refresh` - Check if refresh needed (optional)
- `resolve_rename` - Rename resolution support (optional)

### Target

Represents a file at a specific commit:

- `commit` - Commit offset (0 = HEAD, 1 = HEAD~1, etc.)
- `file` - Relative path from repo root
- `path` - Absolute file path
