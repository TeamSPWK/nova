#!/usr/bin/env bash
# Nova /nova:audit-self 회귀 가드 (Sprint 2.1, v5.22.0+)
#
# 검증 항목:
#   T1: 룰 스키마 7 필드 모두 존재 (id/category/severity/condition/normal_example/risk_example/mitigation)
#   T2: 5 카테고리(plugin/hooks/agents/skills/commands) 누락 감지
#   T3: 룰 ID 중복 감지
#   T4: 룰 ≥30개
#   T5: 헤더 version + nova_compat 필드
#   T6: commands/audit-self.md exclusion_list에 security-engineer.md (메타-루프 가드)
#   T7: scan_targets H2 헤더
#   T8: --category 옵션 정의
#   T9: 결과 해석 가이드 섹션
#
# Safe-default: 모든 실패 → exit 1 + 명시 메시지

set -eu

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
RULES="$ROOT_DIR/.claude/docs/security-rules.md"
CMD="$ROOT_DIR/.claude/commands/audit-self.md"

# Plugin 루트 fallback (테스트 외부 호출)
[[ -f "$RULES" ]] || RULES="$ROOT_DIR/docs/security-rules.md"
[[ -f "$CMD" ]] || CMD="$ROOT_DIR/commands/audit-self.md"

PASS_COUNT=0
FAIL_COUNT=0
FAILS=()

check() {
  local name="$1"
  local cmd="$2"
  # eval 제거 — bash -c로 격리 실행 (R-HOOKS-001 정합)
  if bash -c "$cmd" >/dev/null 2>&1; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  ✓ $name"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILS+=("$name")
    echo "  ✗ $name"
  fi
}

echo "[test-audit-self] 룰셋: $RULES"
echo "[test-audit-self] 커맨드: $CMD"
echo ""

# ── T1: 룰 스키마 7 필드 ──
echo "[T1] 룰 스키마 7 필드 검증"
RULE_IDS=$(grep "^### Rule " "$RULES" | sed 's/^### Rule //' | awk '{print $1}')
T1_FAILS=0
for rule_id in $RULE_IDS; do
  # flag 기반 awk — range 자기 매칭 이슈 회피
  BLOCK=$(awk -v id="$rule_id" '
    $0 ~ "^### Rule " id "$" {f=1; next}
    /^### Rule |^## / {if(f) exit}
    f {print}
  ' "$RULES" 2>/dev/null)
  for field in id category severity condition normal_example risk_example mitigation; do
    if ! echo "$BLOCK" | grep -q "^- \*\*$field\*\*:"; then
      T1_FAILS=$((T1_FAILS + 1))
      echo "    ✗ $rule_id 누락 필드: $field"
    fi
  done
done
if [[ $T1_FAILS -eq 0 ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  ✓ T1: 모든 룰이 7 필드 충족 ($(echo "$RULE_IDS" | wc -w | tr -d ' ') 룰)"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILS+=("T1: 룰 스키마 ($T1_FAILS 누락)")
fi

# ── T2: 5 카테고리 누락 감지 ──
echo "[T2] 5 카테고리 존재 검증"
for cat in plugin hooks agents skills commands; do
  check "T2.$cat: '## Category: $cat' 헤더" "grep -q '^## Category: $cat\$' '$RULES'"
done

# ── T3: 룰 ID 중복 감지 ──
echo "[T3] 룰 ID 중복 감지"
DUPLICATES=$(grep "^### Rule " "$RULES" | sort | uniq -d)
if [[ -z "$DUPLICATES" ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  ✓ T3: 룰 ID 중복 없음"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILS+=("T3: 중복 ID — $DUPLICATES")
  echo "  ✗ T3: 중복 ID — $DUPLICATES"
fi

# ── T4: 룰 ≥30 ──
echo "[T4] 룰 카운트 ≥30"
COUNT=$(grep -c "^### Rule " "$RULES")
if [[ $COUNT -ge 30 ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  ✓ T4: $COUNT 룰 (≥30)"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILS+=("T4: 룰 카운트 $COUNT < 30")
  echo "  ✗ T4: $COUNT 룰 < 30"
fi

# ── T5: 헤더 version + nova_compat ──
echo "[T5] 헤더 frontmatter 검증"
check "T5.version: '^version:' 필드" "grep -q '^version:' '$RULES'"
check "T5.nova_compat: '^nova_compat:' 필드" "grep -q '^nova_compat:' '$RULES'"

# ── T6: 메타-루프 가드 ──
echo "[T6] exclusion_list 메타-루프 가드"
check "T6: exclusion_list에 agents/security-engineer.md" \
  "awk '/^## exclusion_list/,/^---\$/' '$CMD' | grep -q 'agents/security-engineer.md'"

# ── T7: scan_targets H2 헤더 ──
echo "[T7] scan_targets H2 헤더"
check "T7: '^## scan_targets\$' 헤더" "grep -q '^## scan_targets\$' '$CMD'"

# ── T8: --category 옵션 ──
echo "[T8] --category 옵션 정의"
check "T8: '--category' 키워드" "grep -q -- '--category' '$CMD'"

# ── T9: 결과 해석 가이드 ──
echo "[T9] 결과 해석 가이드 섹션"
check "T9: '결과 해석 가이드' 또는 'Critical 발견 시'" \
  "grep -q '결과 해석 가이드\|Critical 발견 시' '$CMD'"

# ── 추가: Known Gap 섹션 ──
check "T10: docs/security-rules.md Known Gap 섹션" \
  "grep -q 'Known Gap\|공급망' '$RULES'"

# ── 결과 요약 ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "  PASS: $PASS_COUNT/$((PASS_COUNT + FAIL_COUNT)) (test-audit-self)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
else
  echo "  FAIL: $FAIL_COUNT 실패 / $((PASS_COUNT + FAIL_COUNT))"
  for fail in "${FAILS[@]}"; do
    echo "    - $fail"
  done
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi
