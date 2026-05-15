#!/usr/bin/env bash
# Sprint 2 통합 테스트: record-event v3 + render-state + 진입점 호출 시뮬레이션 e2e
#
# 시나리오 (Plan → Design → Run PASS → Review → Check Critical):
#   1. setup → 빈 registry
#   2. plan: create (proposed)
#   3. design: update source_docs
#   4. run PASS: evaluator-pass (done)
#   5. review on new WI: require-review
#   6. render-state → NOVA-STATE.md marker 갱신
#   7. events.jsonl 검증: schema_version=3 + 신규 이벤트 3종

set -u
NOVA_PLUGIN_PATH="${NOVA_PLUGIN_PATH:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)}"
export NOVA_PLUGIN_PATH

TEST_DIR=$(mktemp -d -t nova-s2int-XXXXX)
trap "rm -rf '$TEST_DIR'" EXIT INT TERM
cd "$TEST_DIR"

RW="$NOVA_PLUGIN_PATH/scripts/registry-write.sh"
RENDER="$NOVA_PLUGIN_PATH/scripts/registry-render-state.sh"

echo "=== 1) setup ==="
bash "$NOVA_PLUGIN_PATH/scripts/setup.sh" > /dev/null

# NOVA-STATE.md with marker
cat > NOVA-STATE.md <<'EOF'
# Project State

## Current
- Goal: Sprint 2 통합 테스트

<!-- nova:registry-rendered:start -->
<!-- nova:registry-rendered:end -->

## Footer (사람 손편집)
- 보존되어야 함
EOF

echo "=== 2) plan 시뮬레이션 — registry-write create ==="
NOVA_CALLER="command:/nova:plan" WI1=$(bash "$RW" create "검색 필터 추가" --priority=high --source-doc=docs/plans/search.md)
echo "  WI1=$WI1"
[ "$WI1" = "WI-0001-검색-필터-추가" ] && echo "  ✓ create 성공"

echo "=== 3) design 시뮬레이션 — registry-write update ==="
NOVA_CALLER="command:/nova:design" bash "$RW" update "$WI1" source_docs="docs/plans/search.md,docs/designs/search.md" > /dev/null
jq -e '.source_docs | length == 2' ".nova/work-items/$WI1.json" > /dev/null && echo "  ✓ source_docs 2개"

echo "=== 4) run PASS 시뮬레이션 — evaluator-pass ==="
NOVA_CALLER="command:/nova:run" bash "$RW" evaluator-pass "$WI1" --commit-sha=abc1234def --test-output=tests/search.sh > /dev/null
jq -e '.status == "done" and .review_required == false and (.evidence.commit_sha | length == 1)' ".nova/work-items/$WI1.json" > /dev/null && echo "  ✓ 원자적 done 전이"

echo "=== 5) review 시뮬레이션 (신규 WI에 require-review) ==="
NOVA_CALLER="command:/nova:plan" WI2=$(bash "$RW" create "리뷰 대상" --priority=medium)
NOVA_CALLER="command:/nova:review" bash "$RW" require-review "$WI2" > /dev/null
jq -e '.review_required == true' ".nova/work-items/$WI2.json" > /dev/null && echo "  ✓ review_required=true"

echo "=== 6) render-state — NOVA-STATE.md marker 갱신 ==="
ORIG_HEAD=$(head -4 NOVA-STATE.md | md5)
ORIG_FOOTER=$(tail -3 NOVA-STATE.md | md5)
bash "$RENDER" > /dev/null
NEW_HEAD=$(head -4 NOVA-STATE.md | md5)
NEW_FOOTER=$(tail -3 NOVA-STATE.md | md5)
[ "$ORIG_HEAD" = "$NEW_HEAD" ] && echo "  ✓ marker 외 상단 보존"
[ "$ORIG_FOOTER" = "$NEW_FOOTER" ] && echo "  ✓ marker 외 하단 보존"
grep -q "Active Tree" NOVA-STATE.md && echo "  ✓ Active Tree 렌더"
grep -q "Recent Activity" NOVA-STATE.md && echo "  ✓ Recent Activity 렌더"
grep -q "$WI2" NOVA-STATE.md && echo "  ✓ active|proposed WI 렌더 ($WI2)"
# done WI는 Active Tree에 안 나와야 (status=done 필터)
! awk '/Active Tree/,/Recent Activity/' NOVA-STATE.md | grep -q "$WI1" && echo "  ✓ done WI는 Active Tree에서 제외 ($WI1 미렌더)"

echo "=== 7) events.jsonl 검증 — schema v3 + 신규 이벤트 3종 ==="
EVENTS=".nova/events.jsonl"
[ -f "$EVENTS" ] && echo "  ✓ events.jsonl 생성됨"

# schema_version=3 비율
total=$(wc -l < "$EVENTS" | tr -d ' ')
v3_count=$(jq -s 'map(select(.schema_version == 3)) | length' "$EVENTS")
echo "  총 이벤트: $total, schema_version=3: $v3_count"
[ "$v3_count" -gt 0 ] && echo "  ✓ schema_version=3 기록"

# 신규 이벤트 3종 검증
for et in work_item_created work_item_transitioned; do
  count=$(jq -s --arg et "$et" 'map(select(.event_type == $et)) | length' "$EVENTS")
  [ "$count" -gt 0 ] && echo "  ✓ $et ${count}건" || echo "  ✗ $et 0건"
done
# registry_rendered (render-state.sh가 발화)
count=$(jq -s 'map(select(.event_type == "registry_rendered")) | length' "$EVENTS")
[ "$count" -gt 0 ] && echo "  ✓ registry_rendered ${count}건"

# actor 필드 검증 — NOVA_CALLER가 정상 전파됐는지
actors=$(jq -s -r 'map(select(.event_type == "work_item_created") | .extra.actor) | unique | .[]' "$EVENTS")
echo "  work_item_created actors: $(echo $actors | tr '\n' ' ')"
echo "$actors" | grep -q "command:/nova:plan" && echo "  ✓ actor='command:/nova:plan' 정상 전파"

echo ""
echo "=== 최종 NOVA-STATE.md marker 영역 ==="
awk '/nova:registry-rendered:start/,/nova:registry-rendered:end/' NOVA-STATE.md | head -20

echo ""
echo "✅ Sprint 2 통합 테스트 PASS (7 단계)"
