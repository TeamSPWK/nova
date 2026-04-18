#!/usr/bin/env bash
# Nova — fixture 독립 git 레포에서 detect-ui-change.sh 실행 헬퍼
# Usage: bash tests/run-fixture-detect.sh <fixture_name> [--post-impl|--planning]
# Nova 레포 내부에 fixture가 있어 git init만으로는 독립 레포가 안 되므로
# 임시 디렉토리에 복사 후 독립 git 레포로 실행

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

FIXTURE="${1:-react-component}"
MODE="${2:---post-impl}"

TMPDIR=$(mktemp -d)
trap 'cd / 2>/dev/null; rm -rf "$TMPDIR"' EXIT INT TERM
cp -r "$ROOT_DIR/tests/fixtures/$FIXTURE/." "$TMPDIR/"
cd "$TMPDIR"
git init -q
git config user.email 't@t'
git config user.name 'T'
git add -A > /dev/null 2>&1
git commit -q -m init > /dev/null 2>&1
bash "$ROOT_DIR/scripts/detect-ui-change.sh" "$MODE" 2>/dev/null
STATUS=$?
exit $STATUS
