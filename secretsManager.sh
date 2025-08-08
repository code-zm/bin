#!/bin/bash

# === Secrets Manager: Interactive GPG-encrypted secrets picker/exporter ===
#
# This script provides a secure way to manage encrypted API keys, passwords, and secrets
# stored in GPG-encrypted files. It supports both interactive and command-line modes.
#
# Features:
# - Interactive file selection from ~/.secrets/*.gpg files
# - Supports KEY=VALUE format files and pass.gpg JSON format
# - Copy secrets to clipboard or export as environment variables
# - Cross-platform clipboard support (pbcopy, xclip, wl-copy)
# - Secure GPG decryption with error handling
#
# Usage:
#   api                           # Interactive mode - select file and key
#   api -f FILE -c KEY            # Copy KEY to clipboard from FILE
#   api -f FILE -e KEY ENV_VAR    # Export KEY as ENV_VAR from FILE
#
# File Formats Supported:
#   1. KEY=VALUE format: Simple key-value pairs, one per line
#   2. pass.gpg JSON format: {alias:"name", username:"user", pass:"password"}
#
# To add to your .bashrc:
#   echo 'source /path/to/secretsManager.sh' >> ~/.bashrc
#
# Prerequisites:
#   - GPG installed and configured
#   - ~/.secrets/ directory with .gpg encrypted files
#   - Clipboard utility (pbcopy/xclip/wl-copy) for copy functionality
#
# Security Notes:
#   - Secrets are never written to disk unencrypted
#   - Environment variables are only set in current shell session
#   - GPG decryption errors are suppressed to avoid leaking information
api() {
  local secrets_dir="$HOME/.secrets"
  local secrets_file action key_name env_var val lines idx choice files
  local filename entries aliases entry username password

  # — helper: load KEY=VALUE lines (for non‐pass.gpg files) into lines[]
  _load_kv_lines() {
    if [[ ! -f "$secrets_file" ]]; then
      echo "⚠️  Secrets file not found: $secrets_file" >&2
      return 1
    fi
    mapfile -t lines < <(
      gpg --quiet --batch --decrypt "$secrets_file" 2>/dev/null |
        sed -E '/^\s*($|#)/d'
    )
    ((${#lines[@]})) || {
      echo "⚠️  No entries in $secrets_file" >&2
      return 1
    }
  }

  # — helper: load JSON entries (for pass.gpg) into entries[] and aliases[]
  _load_json_entries() {
    if [[ ! -f "$secrets_file" ]]; then
      echo "⚠️  Secrets file not found: $secrets_file" >&2
      return 1
    fi
    # Expect each line like: {alias:"alias", username:"username", pass:"password"}
    mapfile -t entries < <(
      gpg --quiet --batch --decrypt "$secrets_file" 2>/dev/null |
        sed -E '/^\s*($|#)/d'
    )
    ((${#entries[@]})) || {
      echo "⚠️  No entries in $secrets_file" >&2
      return 1
    }
    aliases=()
    for entry in "${entries[@]}"; do
      # extract alias:"…"
      aliases+=( "$(printf '%s' "$entry" | sed -n 's/.*alias:"\([^"]*\)".*/\1/p')" )
    done
  }

  # — helper: copy given string to clipboard
  _copy_to_clipboard() {
    local data="$1"
    if command -v pbcopy >/dev/null 2>&1; then
      printf '%s' "$data" | pbcopy
    elif command -v xclip >/dev/null 2>&1; then
      printf '%s' "$data" | xclip -selection clipboard
    elif command -v wl-copy >/dev/null 2>&1; then
      printf '%s' "$data" | wl-copy
    else
      echo "⚠️  No clipboard utility found (pbcopy, xclip, or wl-copy)" >&2
      return 1
    fi
  }

  # ---- interactive mode (no arguments) ----
  if [[ $# -eq 0 ]]; then
    # 1) list all .gpg files under ~/.secrets
    mapfile -t files < <(printf '%s\n' "$secrets_dir"/*.gpg 2>/dev/null)
    if ((${#files[@]} == 0)); then
      echo "⚠️  No .gpg files found in $secrets_dir" >&2
      return 1
    fi

    echo
    echo "Available .gpg files in $secrets_dir:"
    for i in "${!files[@]}"; do
      printf "  %2d) %s\n" $((i+1)) "$(basename "${files[i]}")"
    done

    echo
    read -rp "Select one file number: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx<1 || idx>${#files[@]} )); then
      echo "⚠️  Invalid selection." >&2
      return 1
    fi
    secrets_file="${files[$((idx-1))]}"
    filename="$(basename "$secrets_file")"

    echo

    if [[ "$filename" == "pass.gpg" ]]; then
      # 2a) pass.gpg: load JSON entries, list by alias
      _load_json_entries || return 1

      echo "Available passwords (aliases) in pass.gpg:"
      for i in "${!aliases[@]}"; do
        printf "  %2d) %s\n" $((i+1)) "${aliases[i]}"
      done

      echo
      read -rp "Select one alias number: " idx
      if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx<1 || idx>${#aliases[@]} )); then
        echo "⚠️  Invalid selection." >&2
        return 1
      fi
      entry="${entries[$((idx-1))]}"
      # extract username and password
      username=$(printf '%s' "$entry" | sed -n 's/.*username:"\([^"]*\)".*/\1/p')
      password=$(printf '%s' "$entry" | sed -n 's/.*pass:"\([^"]*\)".*/\1/p')
      val="$password"

      echo
      echo "Choose action for alias '${aliases[$((idx-1))]}':"
      echo "  1) Copy password to clipboard (default)"
      echo "  2) Export password as environment variable"
      echo
      read -rp "Enter 1 or 2: " choice
      if [[ "$choice" == "2" ]]; then
        action="export"
      else
        action="copy"
      fi

      case "$action" in
        copy)
          if _copy_to_clipboard "$val"; then
            echo "✅ Copied password for '${aliases[$((idx-1))]}' to clipboard"
          else
            return 1
          fi
          ;;
        export)
          read -rp "Export password as (default ${aliases[$((idx-1))]}): " env_var
          env_var="${env_var:-${aliases[$((idx-1))]}}"
          export "$env_var"="$val"
          echo "✅ Exported password for '${aliases[$((idx-1))]}' → \$$env_var"
          ;;
      esac

    else
      # 2b) KEY=VALUE style file: load lines, list keys
      _load_kv_lines || return 1

      echo "Available keys in $filename:"
      for i in "${!lines[@]}"; do
        printf "  %2d) %s\n" $((i+1)) "${lines[i]%%=*}"
      done

      echo
      read -rp "Select one key number: " idx
      if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx<1 || idx>${#lines[@]} )); then
        echo "⚠️  Invalid selection." >&2
        return 1
      fi

      key_name="${lines[$((idx-1))]%%=*}"
      val="${lines[$((idx-1))]#*=}"

      echo
      echo "Choose action for key '$key_name':"
      echo "  1) Copy value to clipboard (default)"
      echo "  2) Export as environment variable"
      echo
      read -rp "Enter 1 or 2: " choice
      if [[ "$choice" == "2" ]]; then
        action="export"
      else
        action="copy"
      fi

      case "$action" in
        copy)
          if _copy_to_clipboard "$val"; then
            echo "✅ Copied '$key_name' to clipboard"
          else
            return 1
          fi
          ;;
        export)
          read -rp "Export as (default $key_name): " env_var
          env_var="${env_var:-$key_name}"
          export "$env_var"="$val"
          echo "✅ Exported '$key_name' → \$$env_var"
          ;;
      esac
    fi

    echo
    return
  fi

  # ---- non‐interactive flags (optional) ----
  #   -f FILE   specify a GPG file
  #   -c KEY    copy KEY (or alias) to clipboard
  #   -e KEY ENV export KEY (or alias) as ENV var
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--file)
        secrets_file="$2"; shift 2;;
      -c|--copy)
        action="copy"; key_name="$2"; shift 2;;
      -e|--export)
        action="export"; key_name="$2"; env_var="$3"; shift 3;;
      *)
        echo "Usage (interactive): api" >&2
        echo "Usage (flags):" >&2
        echo "  api -f FILE -c KEY            # copy KEY (or alias) from FILE" >&2
        echo "  api -f FILE -e KEY ENV_VAR    # export KEY (or alias) as ENV_VAR" >&2
        return 1;;
    esac
  done

  # Validate for non‐interactive
  [[ -n "$secrets_file" ]] || {
    echo "⚠️  Missing -f|--file argument" >&2; return 1
  }
  [[ -n "$key_name" ]] || {
    echo "🔑 Missing KEY/ALIAS name" >&2; return 1
  }
  if [[ "$action" == "export" && -z "$env_var" ]]; then
    echo "📝 Missing ENV_VARIABLE_NAME" >&2; return 1
  fi

  filename="$(basename "$secrets_file")"

  if [[ "$filename" == "pass.gpg" ]]; then
    # lookup alias in JSON entries
    _load_json_entries || return 1
    idx=-1
    for i in "${!aliases[@]}"; do
      [[ "${aliases[i]}" == "$key_name" ]] && { idx="$i"; break; }
    done
    if (( idx<0 )); then
      echo "⚠️  Alias not found: $key_name" >&2; return 1
    fi
    entry="${entries[$idx]}"
    password=$(printf '%s' "$entry" | sed -n 's/.*pass:"\([^"]*\)".*/\1/p')
    val="$password"

    case "$action" in
      copy)
        if _copy_to_clipboard "$val"; then
          echo "✅ Copied password for '$key_name' to clipboard"
        else
          return 1
        fi
        ;;
      export)
        export "$env_var"="$val"
        echo "✅ Exported password for '$key_name' → \$$env_var"
        ;;
      *)
        echo "⚠️  Unknown action: $action" >&2; return 1
        ;;
    esac

  else
    # KEY=VALUE lookup
    _load_kv_lines || return 1
    val=""
    for l in "${lines[@]}"; do
      [[ "${l%%=*}" == "$key_name" ]] && { val="${l#*=}"; break; }
    done
    [[ -n "$val" ]] || {
      echo "⚠️  Key not found: $key_name" >&2; return 1
    }

    case "$action" in
      copy)
        if _copy_to_clipboard "$val"; then
          echo "✅ Copied '$key_name' to clipboard"
        else
          return 1
        fi
        ;;
      export)
        export "$env_var"="$val"
        echo "✅ Exported '$key_name' → \$$env_var"
        ;;
      *)
        echo "⚠️  Unknown action: $action" >&2; return 1
        ;;
    esac
  fi
}
# ======================
