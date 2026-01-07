#!/usr/bin/env zsh
# spectre - Quick project switching for Claude Code
# Usage: spectre [project|add|list|remove|path]

_spectre_registry="${XDG_CONFIG_HOME:-$HOME/.config}/spectre/projects"

# Ensure registry directory exists
_spectre_ensure_registry() {
  local registry_dir="${_spectre_registry:h}"
  [[ -d "$registry_dir" ]] || mkdir -p "$registry_dir"
  [[ -f "$_spectre_registry" ]] || : > "$_spectre_registry"
}

# Get project path from registry
_spectre_get_path() {
  local name="$1"
  _spectre_ensure_registry
  grep "^${name}=" "$_spectre_registry" 2>/dev/null | cut -d= -f2-
}

# List all project names
_spectre_list_names() {
  _spectre_ensure_registry
  cut -d= -f1 "$_spectre_registry" 2>/dev/null
}

# Main spectre function
spectre() {
  local cmd="$1"

  case "$cmd" in
    "")
      # No args - launch claude in current directory
      ${SPECTRE_CMD:-claude}
      ;;

    add)
      # Add project to registry
      local name="$2"
      local path="${3:-$PWD}"

      if [[ -z "$name" ]]; then
        echo "Usage: spectre add <name> [path]" >&2
        return 1
      fi

      # Expand path to absolute
      path="${path:a}"

      if [[ ! -d "$path" ]]; then
        echo "Error: Directory does not exist: $path" >&2
        return 1
      fi

      _spectre_ensure_registry

      # Remove existing entry if present
      if grep -q "^${name}=" "$_spectre_registry" 2>/dev/null; then
        sed -i.bak "/^${name}=/d" "$_spectre_registry" && rm -f "${_spectre_registry}.bak"
      fi

      # Add new entry
      echo "${name}=${path}" >> "$_spectre_registry"
      echo "Added project: $name -> $path"
      ;;

    list)
      # List all projects
      _spectre_ensure_registry
      if [[ ! -s "$_spectre_registry" ]]; then
        echo "No projects registered. Use 'spectre add <name> [path]' to add one."
        return 0
      fi

      echo "Registered projects:"
      while IFS='=' read -r name path; do
        printf "  %-20s %s\n" "$name" "$path"
      done < "$_spectre_registry"
      ;;

    remove)
      # Remove project from registry
      local name="$2"

      if [[ -z "$name" ]]; then
        echo "Usage: spectre remove <name>" >&2
        return 1
      fi

      _spectre_ensure_registry

      if ! grep -q "^${name}=" "$_spectre_registry" 2>/dev/null; then
        echo "Error: Project not found: $name" >&2
        return 1
      fi

      sed -i.bak "/^${name}=/d" "$_spectre_registry" && rm -f "${_spectre_registry}.bak"
      echo "Removed project: $name"
      ;;

    path)
      # Print project path (for scripting)
      local name="$2"

      if [[ -z "$name" ]]; then
        echo "Usage: spectre path <name>" >&2
        return 1
      fi

      local path="$(_spectre_get_path "$name")"
      if [[ -z "$path" ]]; then
        echo "Error: Project not found: $name" >&2
        return 1
      fi

      echo "$path"
      ;;

    *)
      # Project name - cd and launch claude
      local name="$cmd"
      local path="$(_spectre_get_path "$name")"

      if [[ -z "$path" ]]; then
        echo "Error: Project not found: $name" >&2
        echo "Use 'spectre list' to see registered projects." >&2
        return 1
      fi

      if [[ ! -d "$path" ]]; then
        echo "Error: Project path no longer exists: $path" >&2
        echo "Consider removing with: spectre remove $name" >&2
        return 1
      fi

      cd "$path" && ${SPECTRE_CMD:-claude}
      ;;
  esac
}

# Zsh completion function
_spectre_completion() {
  local -a subcmds projects
  subcmds=(
    'add:Add a project to the registry'
    'list:List all registered projects'
    'remove:Remove a project from the registry'
    'path:Print project path'
  )

  if (( CURRENT == 2 )); then
    # First argument - offer subcommands and project names
    projects=("${(@f)$(_spectre_list_names)}")
    _describe 'command' subcmds
    _describe 'project' projects
  elif (( CURRENT == 3 )); then
    # Second argument context
    case "$words[2]" in
      remove|path)
        # Offer project names for remove/path
        projects=("${(@f)$(_spectre_list_names)}")
        _describe 'project' projects
        ;;
      add)
        # For add, first arg is the name (no completion)
        _message 'project name'
        ;;
    esac
  elif (( CURRENT == 4 )); then
    # Third argument context
    case "$words[2]" in
      add)
        # For add, second arg is path (directory completion)
        _directories
        ;;
    esac
  fi
}

# Register completion
compdef _spectre_completion spectre
