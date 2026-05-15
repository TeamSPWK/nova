#!/usr/bin/env bash
# Sprint 1-D: 동시 create N건 → ID 유일성 + next_seq 정합성
# Verification Hook #5 (Critic #2 race): N개 동시 호출에서 next_seq atomic 보장
#
# 사용:
#   bash tests/test-channel-race.sh          # 기본 N=20
#   N=50 bash tests/test-channel-race.sh     # N 조정
#
# 임계: 정규 id + UUID fallback id 합계 == N, 유일 ID == N

set -u
N=${N:-20}
NOVA_PLUGIN_PATH="${NOVA_PLUGIN_PATH:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)}"
export NOVA_PLUGIN_PATH

TEST_DIR=$(mktemp -d -t nova-race-XXXXX)
trap "rm -rf '$TEST_DIR'" EXIT INT TERM
cd "$TEST_DIR"

bash "$NOVA_PLUGIN_PATH/scripts/setup.sh" >/dev/null

RW="$NOVA_PLUGIN_PATH/scripts/registry-write.sh"
LOG_DIR="$TEST_DIR/_race_logs"
mkdir -p "$LOG_DIR"

echo "[race] N=$N 동시 create (PID $$)"
PIDS=()
for i in $(seq 1 "$N"); do
  bash "$RW" create "race-$i" --priority=medium >"$LOG_DIR/out.$i" 2>"$LOG_DIR/err.$i" &
  PIDS+=($!)
done
echo "[race] 백그라운드 ${#PIDS[@]}개 시작, wait..."
wait
echo "[race] 모든 호출 완료"

TOTAL=$(ls .nova/work-items/WI-*.json 2>/dev/null | wc -l | tr -d ' ')
# grep -c는 매치 0건일 때도 stdout "0"을 출력 + exit 1. || echo 0 사용 금지 (출력 중복).
NORMAL=$(ls .nova/work-items/ 2>/dev/null | grep -cE '^WI-[0-9]{4}-' | head -1)
UUID_FB=$(ls .nova/work-items/ 2>/dev/null | grep -cE '^WI-[a-f0-9]{8}-' | head -1)
UNIQUE_IDS=$(ls .nova/work-items/WI-*.json 2>/dev/null | sed 's/.*\///; s/\.json$//' | sort -u | wc -l | tr -d ' ')
NEXT_SEQ=$(jq -r '.next_seq' .nova/work-items/index.json)

echo ""
echo "[race] 결과:"
echo "  총 WI 파일: $TOTAL"
echo "  정규 id:    $NORMAL"
echo "  UUID fb:    $UUID_FB"
echo "  유일 ID:    $UNIQUE_IDS"
echo "  next_seq:   $NEXT_SEQ"

FAIL=0
if [ "$TOTAL" -ne "$N" ]; then
  echo "  ✗ 파일 개수 불일치 (예상 $N, 실제 $TOTAL)"
  FAIL=1
fi
if [ "$UNIQUE_IDS" -ne "$N" ]; then
  echo "  ✗ ID 중복 (유일 $UNIQUE_IDS, 예상 $N)"
  FAIL=1
fi
if [ "$NEXT_SEQ" -ne "$((NORMAL + 1))" ]; then
  echo "  ✗ next_seq 정합성 위반 (next_seq=$NEXT_SEQ, NORMAL=$NORMAL, 예상=$((NORMAL + 1)))"
  FAIL=1
fi
if [ "$UUID_FB" -gt 0 ]; then
  echo "  ℹ️  UUID fallback ${UUID_FB}개 발생 (lock contention 정상 처리)"
fi

# index.json work_items 개수 = 파일 개수
IDX_COUNT=$(jq '.work_items | length' .nova/work-items/index.json)
if [ "$IDX_COUNT" -ne "$N" ]; then
  echo "  ✗ index.json work_items count 불일치 ($IDX_COUNT, 예상 $N)"
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo ""
  echo "✅ test-channel-race PASS (N=$N, UUID fallback=$UUID_FB)"
  exit 0
else
  echo ""
  echo "❌ test-channel-race FAIL"
  echo "stderr 샘플 (마지막 3):"
  ls "$LOG_DIR"/err.* | tail -3 | xargs cat
  exit 1
fi
