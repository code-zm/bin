#!/usr/bin/env bash
#
# pythondump: dump a clean project tree + Python files into a Markdown file

# Check for exactly one argument
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 OUTPUT.md" >&2
  exit 1
fi

OUTPUT="$1"

{
  #
  # 1) Project tree (2 levels)
  #
  echo "# Project Tree"
  echo '```'
  tree -I 'venv|.venv|build|dist|__pycache__|*.pyc|.pytest_cache|.mypy_cache' -L 2
  echo '```'
  echo

  #
  # 2) requirements.txt
  #
  if [ -f requirements.txt ]; then
    echo "# requirements.txt"
    echo '```'
    cat requirements.txt
    echo '```'
    echo
  fi

  #
  # 3) setup.py
  #
  if [ -f setup.py ]; then
    echo "# setup.py"
    echo '```python'
    cat setup.py
    echo '```'
    echo
  fi

  #
  # 4) pyproject.toml
  #
  if [ -f pyproject.toml ]; then
    echo "# pyproject.toml"
    echo '```toml'
    cat pyproject.toml
    echo '```'
    echo
  fi

  #
  # 5) All .py files
  #
  find . \
    -type f -name '*.py' \
    -not -path './venv/*' \
    -not -path './.venv/*' \
    -not -path './__pycache__/*' \
    | sort \
    | while read -r file; do
      echo "## File: $file"
      echo '```python'
      cat "$file"
      echo '```'
      echo
    done
} > "$OUTPUT"

