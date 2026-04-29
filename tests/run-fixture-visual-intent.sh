#!/usr/bin/env bash
# Nova — fixture 기반 capture-visual-intent 실행 헬퍼
# Usage: bash tests/run-fixture-visual-intent.sh <fixture-name>
#   예: bash tests/run-fixture-visual-intent.sh side-case
# 출력: tests/.cache/<fixture-name>-intent.json

set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &> /dev/null && pwd)"
FIXTURE="${1:-}"

if [ -z "$FIXTURE" ]; then
  echo "Usage: bash tests/run-fixture-visual-intent.sh <fixture-name>" >&2
  echo "Available: side-case, new-screen, non-ui" >&2
  exit 1
fi

FIXTURE_DIR="$ROOT_DIR/tests/fixtures/visual-intent-${FIXTURE}"
PROMPT_FILE="$FIXTURE_DIR/prompt.txt"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: prompt.txt not found at $PROMPT_FILE" >&2
  exit 1
fi

PROMPT=$(cat "$PROMPT_FILE")
mkdir -p "$ROOT_DIR/tests/.cache"
OUTPUT="$ROOT_DIR/tests/.cache/${FIXTURE}-intent.json"

bash "$ROOT_DIR/scripts/capture-visual-intent.sh" \
  --slug "$FIXTURE" \
  --non-interactive \
  --from-prompt "$PROMPT" \
  --output "$OUTPUT" \
  --catalog "$ROOT_DIR/docs/catalogs/design-vocabulary.json" 2>&1

echo "$OUTPUT"
