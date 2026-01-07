# spectre

Quick project switching for Claude Code.

## What it does

`spectre` lets you jump to registered projects and launch Claude Code with a single command. Save your frequently-used project paths and switch instantly.

## Installation

```bash
git clone https://github.com/gabaum10/spectre.git
cd spectre
./install.sh
```

Then restart your shell or run:
```bash
source ~/.zshrc  # or ~/.bashrc for bash
```

## Usage

```bash
# Launch Claude in current directory
spectre

# Switch to a registered project and launch Claude
spectre normandy

# Add a project to the registry
spectre add normandy ~/work/normandy

# Add current directory as a project
spectre add my-project

# List all registered projects
spectre list

# Remove a project
spectre remove normandy

# Print project path (for scripting)
spectre path normandy
```

## Adding projects

There are two ways to add a project:

**1. Specify the path:**
```bash
spectre add normandy ~/work/normandy
```

**2. Add current directory:**
```bash
cd ~/work/normandy
spectre add normandy
```

Projects are stored in `~/.config/spectre/projects` as simple `name=path` pairs.

## Configuration

### Custom launch command

By default, `spectre` runs `claude` to launch Claude Code. You can customize this with the `SPECTRE_CMD` environment variable.

**Example: Skip permissions prompts**
```bash
export SPECTRE_CMD="claude --dangerously-skip-permissions"
```

Add this to your `~/.zshrc` or `~/.bashrc` before the line that sources `spectre.zsh`.

## Tab completion

Tab completion works for both subcommands and project names:

```bash
spectre <TAB>           # Shows: add, list, remove, path, and all projects
spectre remove <TAB>    # Shows: all registered projects
spectre add <TAB>       # Completes directory paths
```

## Requirements

- zsh or bash
- [Claude Code](https://github.com/anthropics/claude-code) installed and in PATH
- macOS or Linux

## How it works

`spectre` is a shell function (not a script) so `cd` changes your actual shell's directory. The project registry is machine-local and not tracked in git, so you can clone the repo on multiple machines and maintain separate project lists.
