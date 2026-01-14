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

# Get project entry (path and optional identity)
_spectre_get_entry() {
  local name="$1"
  _spectre_ensure_registry
  grep "^${name}=" "$_spectre_registry" 2>/dev/null | cut -d= -f2-
}

# Get project path from registry (strip identity if present)
_spectre_get_path() {
  local name="$1"
  local entry=$(_spectre_get_entry "$name")
  echo "${entry%%:*}"  # everything before first :
}

# Get the identity (empty if not specified)
_spectre_get_identity() {
  local name="$1"
  local entry=$(_spectre_get_entry "$name")
  if [[ "$entry" == *:* ]]; then
    echo "${entry##*:}"  # everything after last :
  fi
}

# Check if name is a persona in claude-os registry
_spectre_is_persona() {
  local name="$1"
  local registry="$HOME/.claude-os/registry.json"
  [[ -f "$registry" ]] && jq -e ".apps | has(\"$name\")" "$registry" >/dev/null 2>&1
}

# Get default persona from config
_spectre_get_default_persona() {
  local config="$HOME/.claude-os/config.json"
  if [[ -f "$config" ]]; then
    jq -r '.defaultPersona // "normandy"' "$config" 2>/dev/null || echo "normandy"
  else
    echo "normandy"
  fi
}

# Get path for a persona from registry
_spectre_get_persona_path() {
  local name="$1"
  local registry="$HOME/.claude-os/registry.json"
  if [[ -f "$registry" ]]; then
    jq -r ".apps[\"$name\"].path // empty" "$registry" 2>/dev/null
  fi
}

# List all project names
_spectre_list_names() {
  _spectre_ensure_registry
  cut -d= -f1 "$_spectre_registry" 2>/dev/null
}

# Ensure PATH has required directories before launching claude
# Fixes race condition where PATH may be truncated in some shell contexts
_spectre_ensure_path() {
  # System paths
  [[ :$PATH: == *":/usr/bin:"* ]] || export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

  # Homebrew (Apple Silicon)
  [[ :$PATH: == *":/opt/homebrew/bin:"* ]] || export PATH="/opt/homebrew/bin:$PATH"

  # Node (n version manager)
  [[ :$PATH: == *":$HOME/n/bin:"* ]] || export PATH="$HOME/n/bin:$PATH"

  # Cargo/Rust
  [[ :$PATH: == *":$HOME/.cargo/bin:"* ]] || export PATH="$HOME/.cargo/bin:$PATH"
}

# Main spectre function
spectre() {
  local cmd="$1"

  case "$cmd" in
    "")
      # No args - launch claude in current directory
      _spectre_ensure_path
      ${=SPECTRE_CMD:-claude}
      ;;

    add)
      # Add project to registry
      # Usage: spectre add <name> [path] [identity]
      local name="$2"
      local project_path="${3:-$PWD}"
      local identity="$4"

      if [[ -z "$name" ]]; then
        echo "Usage: spectre add <name> [path] [identity]" >&2
        return 1
      fi

      # Expand path to absolute
      project_path="${~project_path:a}"

      if [[ ! -d "$project_path" ]]; then
        echo "Error: Directory does not exist: $project_path" >&2
        return 1
      fi

      _spectre_ensure_registry

      # Remove existing entry if present
      if grep -q "^${name}=" "$_spectre_registry" 2>/dev/null; then
        sed -i.bak "/^${name}=/d" "$_spectre_registry" && rm -f "${_spectre_registry}.bak"
      fi

      # Add new entry with optional identity
      if [[ -n "$identity" ]]; then
        echo "${name}=${project_path}:${identity}" >> "$_spectre_registry"
        echo "Added project: $name -> $project_path (identity: $identity)"
      else
        echo "${name}=${project_path}" >> "$_spectre_registry"
        echo "Added project: $name -> $project_path"
      fi
      ;;

    list)
      # List all projects
      _spectre_ensure_registry
      if [[ ! -s "$_spectre_registry" ]]; then
        echo "No projects registered. Use 'spectre add <name> [path] [identity]' to add one."
        return 0
      fi

      echo "Registered projects:"
      while IFS='=' read -r name entry; do
        local project_path="${entry%%:*}"
        if [[ "$entry" == *:* ]]; then
          local identity="${entry##*:}"
          printf "  %-20s %s (identity: %s)\n" "$name" "$project_path" "$identity"
        else
          printf "  %-20s %s\n" "$name" "$project_path"
        fi
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

      local project_path="$(_spectre_get_path "$name")"
      if [[ -z "$project_path" ]]; then
        echo "Error: Project not found: $name" >&2
        return 1
      fi

      echo "$project_path"
      ;;

    clean)
      # Clean registry of duplicates, malformed entries, and invalid paths
      _spectre_ensure_registry

      if [[ ! -s "$_spectre_registry" ]]; then
        echo "Registry is clean"
        return 0
      fi

      local temp_file="${_spectre_registry}.clean"
      local -a seen_names
      local cleaned_count=0

      > "$temp_file"

      while IFS='=' read -r name project_path; do
        # Skip empty lines
        [[ -z "$name" ]] && continue

        # Check for malformed entry (name contains /)
        if [[ "$name" == */* ]]; then
          echo "Removed malformed: $name (name contains /)"
          ((cleaned_count++))
          continue
        fi

        # Check for duplicate (keep first occurrence)
        if (( ${seen_names[(Ie)$name]} )); then
          echo "Removed duplicate: $name"
          ((cleaned_count++))
          continue
        fi

        # Check if path exists
        if [[ ! -d "$project_path" ]]; then
          echo "Removed invalid path: $name (path does not exist)"
          ((cleaned_count++))
          continue
        fi

        # Entry is valid - keep it
        echo "${name}=${project_path}" >> "$temp_file"
        seen_names+=("$name")
      done < "$_spectre_registry"

      # Replace registry with cleaned version
      < "$temp_file" > "$_spectre_registry"
      rm -f "$temp_file"

      if (( cleaned_count == 0 )); then
        echo "Registry is clean"
      else
        echo "Cleaned $cleaned_count entries"
      fi
      ;;

    -h|--help|help)
      cat << 'EOF'
spectre - Quick project launcher with identity support

Usage:
  spectre <project>              Launch project (activates identity if needed)
  spectre add <name> <path> [identity]   Add project to registry
  spectre remove <name>          Remove project from registry
  spectre list                   List all projects
  spectre path <name>            Show project path
  spectre clean                  Remove projects with invalid paths
  spectre -h|--help              Show this help

Examples:
  spectre client                 Launch client project
  spectre add myproj /path/to/proj normandy   Add with identity
  spectre add myproj /path/to/proj            Add without identity
EOF
      return 0
      ;;

    *)
      # Resolution order:
      # 1. Check spectre projects registry
      # 2. Check if arg is a persona in claude-os registry
      # 3. Check if arg is a valid directory path
      # 4. Error
      local name="$cmd"
      local project_path="$(_spectre_get_path "$name")"
      local identity="$(_spectre_get_identity "$name")"

      # Case 1: Found in spectre projects registry - use existing logic
      if [[ -n "$project_path" ]]; then
        if [[ ! -d "$project_path" ]]; then
          echo "Error: Project path no longer exists: $project_path" >&2
          echo "Consider removing with: spectre remove $name" >&2
          return 1
        fi

        _spectre_ensure_path

        # Check if we need identity activation
        if [[ -n "$identity" ]]; then
          local env_home="$HOME/.${identity}-env"

          # Check if already in correct isolated environment
          if [[ "$HOME" != "$env_home" ]]; then
            # Need to activate identity first
            echo "Activating $identity..."
            claude-os activate "$identity"

            # Now launch with isolated HOME (preserve REAL_HOME for registry access)
            cd "$project_path" && REAL_HOME="$HOME" HOME="$env_home" ${=SPECTRE_CMD:-claude}
            return $?
          fi

          # Already in correct env - just cd and launch
          cd "$project_path" && ${=SPECTRE_CMD:-claude}
          return 0
        else
          # No identity specified - use default persona
          local default_persona="$(_spectre_get_default_persona)"
          local env_home="$HOME/.${default_persona}-env"

          # Check if already in correct isolated environment
          if [[ "$HOME" != "$env_home" ]]; then
            # Need to activate default persona first
            echo "Activating $default_persona..."
            claude-os activate "$default_persona"

            # Now launch with isolated HOME (preserve REAL_HOME for registry access)
            cd "$project_path" && REAL_HOME="$HOME" HOME="$env_home" ${=SPECTRE_CMD:-claude}
            return $?
          fi

          # Already in correct env - just cd and launch
          cd "$project_path" && ${=SPECTRE_CMD:-claude}
          return 0
        fi
      fi

      # Case 2: Check if arg is a persona in claude-os registry
      if _spectre_is_persona "$name"; then
        echo "Activating $name..."
        claude-os activate "$name"

        local persona_path="$(_spectre_get_persona_path "$name")"
        if [[ -n "$persona_path" ]]; then
          local env_home="$HOME/.${name}-env"
          _spectre_ensure_path
          cd "$PWD" && REAL_HOME="$HOME" HOME="$env_home" ${=SPECTRE_CMD:-claude}
        else
          echo "Error: Failed to get path for persona: $name" >&2
          return 1
        fi
        return 0
      fi

      # Case 3: Check if arg is a valid directory path
      local expanded_path="${~name:a}"
      if [[ -d "$expanded_path" ]]; then
        local default_persona="$(_spectre_get_default_persona)"
        echo "Activating $default_persona..."
        claude-os activate "$default_persona"

        local env_home="$HOME/.${default_persona}-env"
        _spectre_ensure_path
        cd "$expanded_path" && REAL_HOME="$HOME" HOME="$env_home" ${=SPECTRE_CMD:-claude}
        return 0
      fi

      # Case 4: Error - not found in any resolution path
      echo "Error: Not found: $name" >&2
      echo "Not a registered project, persona, or valid directory path." >&2
      echo "Use 'spectre list' to see registered projects." >&2
      return 1
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
    'clean:Clean registry of duplicates and invalid entries'
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
  elif (( CURRENT == 5 )); then
    # Fourth argument context
    case "$words[2]" in
      add)
        # For add, third arg is identity (no completion)
        _message 'identity name'
        ;;
    esac
  fi
}

# Register completion
(( $+functions[compdef] )) && compdef _spectre_completion spectre
