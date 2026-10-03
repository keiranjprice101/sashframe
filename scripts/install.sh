#!/usr/bin/env bash
set -e

# Change to repository root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=========================================="
echo " Setting up Sashframe Environment"
echo "=========================================="

# 1. Verify Python 3
if ! command -v python3 >/dev/null 2>&1; then
  echo "[Error] python3 is required but was not found on PATH." >&2
  exit 1
fi

# 2. Set up Python virtual environment
echo "[1/3] Setting up Python virtual environment (.venv)..."
if [ ! -d ".venv" ] || [ ! -f ".venv/bin/activate" ]; then
  # Try python3 -m venv first
  if python3 -m venv .venv 2>/dev/null; then
    echo "  Created virtual environment using python3 -m venv."
  else
    # Fallback to virtualenv if python3-venv is missing
    VENV_CMD=""
    if command -v virtualenv >/dev/null 2>&1; then
      VENV_CMD="virtualenv"
    elif [ -x "$HOME/.local/bin/virtualenv" ]; then
      VENV_CMD="$HOME/.local/bin/virtualenv"
    fi

    if [ -n "$VENV_CMD" ]; then
      echo "  Falling back to $VENV_CMD..."
      "$VENV_CMD" .venv
    else
      echo "  Attempting to install virtualenv in user space..."
      python3 -m pip install --user --break-system-packages virtualenv 2>/dev/null || true
      if [ -x "$HOME/.local/bin/virtualenv" ]; then
        "$HOME/.local/bin/virtualenv" .venv
      else
        echo "[Error] Failed to create .venv. Please install python3-venv or virtualenv." >&2
        exit 1
      fi
    fi
  fi
else
  echo "  Existing .venv found."
fi

# 3. Install Python requirements
echo "[2/3] Installing Python dependencies from requirements.txt..."
if [ -f ".venv/bin/pip" ]; then
  .venv/bin/pip install --quiet --upgrade pip 2>/dev/null || true
  .venv/bin/pip install -r requirements.txt
else
  echo "[Error] .venv/bin/pip not found." >&2
  exit 1
fi

# 4. Install Node dependencies
echo "[3/3] Installing Node dependencies via npm install..."
if ! command -v npm >/dev/null 2>&1; then
  echo "[Error] npm is required but was not found on PATH." >&2
  exit 1
fi
npm install

echo ""
echo "=========================================="
echo " Setup complete!"
echo ""
echo " To start development (Astro + Photo Watcher):"
echo "   npm run dev"
echo "=========================================="
