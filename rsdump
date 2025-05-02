#!/usr/bin/env bash
#
# rustdump: dump a clean project tree + all .rs and Cargo.toml into a Markdown file

# Check for exactly one argument
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 OUTPUT.md" >&2
  exit 1
fi

OUTPUT="$1"

# Generate everything and write to the output file
{
  # Project tree
  echo "# Project Tree"
  echo '```'
  echo "├── Cargo.toml"
  echo "└── src"
  tree src -L 2 | tail -n +2 | sed 's/^/    /'
  echo '```'
  echo

  # Cargo.toml
  echo "# Cargo.toml"
  echo '```toml'
  cat Cargo.toml
  echo '```'
  echo

  # All .rs files
  find src -type f -name '*.rs' | sort | while read -r file; do
    echo "## File: $file"
    echo '```rust'
    cat "$file"
    echo '```'
    echo
  done
} >"$OUTPUT"
