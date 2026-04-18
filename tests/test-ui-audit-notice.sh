#!/usr/bin/env bash
# Nova Sprint B — 사전 고지 첫 트리거 vs 이후 트리거 상태 변화 검증
# orchestrator 자체(LLM)를 호출하지 않고, ui-state.json 상태 관리 로직만 단독 검증

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

assert() {
  local desc="$1"
  local cond="$2"
  if eval "$cond" > /dev/null 2>&1; then
    echo -e "  ${GREEN}OK${NC}  $desc"
    ((PASS++)) || true
  else
    echo -e "  ${RED}FAIL${NC} $desc"
    ((FAIL++)) || true
  fi
}

# ui-state.json 관리 함수 (orchestrator Phase 5.5 로직 추출)
check_and_update_ui_state() {
  local nova_dir="$1"
  local state_file="$nova_dir/ui-state.json"
  local output_type=""

  mkdir -p "$nova_dir"

  if [ ! -f "$state_file" ]; then
    # 첫 트리거: 파일 없음 → 자세한 안내
    output_type="detailed"
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S+09:00' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')
    echo "{\"first_ui_audit_shown\":true,\"first_shown_ts\":\"$ts\",\"total_triggered\":1}" > "$state_file"
  else
    local shown=""
    shown=$(jq -r '.first_ui_audit_shown // false' "$state_file" 2>/dev/null) || shown="false"
    if [ "$shown" = "false" ]; then
      output_type="detailed"
      # first_ui_audit_shown을 true로 갱신
      local updated=""
      updated=$(jq '.first_ui_audit_shown = true | .total_triggered = ((.total_triggered // 0) + 1)' "$state_file" 2>/dev/null) || true
      echo "$updated" > "$state_file"
    else
      output_type="brief"
      # total_triggered 증가
      local updated=""
      updated=$(jq '.total_triggered = ((.total_triggered // 0) + 1)' "$state_file" 2>/dev/null) || true
      echo "$updated" > "$state_file"
    fi
  fi

  echo "$output_type"
}

echo "━━━ test-ui-audit-notice.sh ━━━━━━━━━━━━━━━━━━━━"

# Test 1: 첫 트리거 — ui-state.json 없음 → detailed 안내 + 파일 생성
TMPDIR=$(mktemp -d)
RESULT=$(check_and_update_ui_state "$TMPDIR/.nova")
assert "첫 트리거: 'detailed' 안내 반환" "[ '$RESULT' = 'detailed' ]"
assert "첫 트리거: ui-state.json 생성됨" "[ -f '$TMPDIR/.nova/ui-state.json' ]"
assert "첫 트리거 후: first_ui_audit_shown = true" \
  "jq -e '.first_ui_audit_shown == true' '$TMPDIR/.nova/ui-state.json' > /dev/null 2>&1"
assert "첫 트리거 후: total_triggered = 1" \
  "jq -e '.total_triggered == 1' '$TMPDIR/.nova/ui-state.json' > /dev/null 2>&1"

# Test 2: 두 번째 트리거 — 이미 shown=true → brief 안내
RESULT2=$(check_and_update_ui_state "$TMPDIR/.nova")
assert "두 번째 트리거: 'brief' 안내 반환" "[ '$RESULT2' = 'brief' ]"
assert "두 번째 트리거 후: total_triggered = 2" \
  "jq -e '.total_triggered == 2' '$TMPDIR/.nova/ui-state.json' > /dev/null 2>&1"

# Test 3: first_ui_audit_shown = false인 파일이 있을 때 → detailed + true로 갱신
TMPDIR2=$(mktemp -d)
mkdir -p "$TMPDIR2/.nova"
echo '{"first_ui_audit_shown":false,"first_shown_ts":"","total_triggered":0}' > "$TMPDIR2/.nova/ui-state.json"
RESULT3=$(check_and_update_ui_state "$TMPDIR2/.nova")
assert "shown=false 상태에서 첫 호출: 'detailed' 반환" "[ '$RESULT3' = 'detailed' ]"
assert "shown=false → true로 갱신됨" \
  "jq -e '.first_ui_audit_shown == true' '$TMPDIR2/.nova/ui-state.json' > /dev/null 2>&1"

# 정리
rm -rf "$TMPDIR" "$TMPDIR2"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}ALL PASS${NC}: ${PASS}/${TOTAL}"
  exit 0
else
  echo -e "  ${RED}FAIL${NC}: ${PASS}/${TOTAL} 통과, ${FAIL}개 실패"
  exit 1
fi
