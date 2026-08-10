#!/usr/bin/env bash
#
# Everything that can be checked without building a Drupal site.
#
# `tests/check.sh` needs a disposable site and a destructive install, so it is
# not something you run before every commit. This is: it reads the shipped
# YAML and the shipped binaries and nothing else, and it takes about a second.
#
# Usage:
#   tests/lint.sh
#
# Requires python3 with PyYAML and Pillow:
#   python3 -m pip install -r tests/lib/requirements.txt

set -euo pipefail

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 "$RECIPE_DIR/tests/lib/validate-snapshot.py" "$RECIPE_DIR" \
  --allow "$RECIPE_DIR/tests/lib/known-problems.txt"
