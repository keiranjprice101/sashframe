#!/usr/bin/env bash
set -e

# Change to repository root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=========================================="
echo " Starting Sashframe Development Env"
echo " - Astro dev server"
echo "=========================================="

exec npx astro dev --ignore-lock "$@"
