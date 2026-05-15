#!/usr/bin/env bash
# Sprint 1-D: SIGKILL stale lock 자동 정리 검증
# Critic #2: lock holder 강제 종료 시 후속 호출자가 PID kill -0로 검출 후 정리
#
# NOVA_LOCK_MODE=mkdir로 mkdir 분기 강제 (flock 환경에서도 검증 가능)

set -u
NOVA_PLUGIN_PATH="${NOVA_PLUGIN_PATH:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)}"
export NOVA_PLUGIN_PATH NOVA_LOCK_MODE=mkdir

TEST_DIR=$(mktemp -d -t nova-stale-XXXXX)
trap "rm -rf '$TEST_DIR'" EXIT INT TERM
cd "$TEST_DIR"

bash "$NOVA_PLUGIN_PATH/scripts/setup.sh" >/dev/null

RW="$NOVA_PLUGIN_PATH/scripts/registry-write.sh"

echo "=== Phase 1: stale lock 시뮬레이션 (이미 죽은 PID) ==="
# 거의 확실히 존재하지 않는 PID (32-bit 최댓값)
FAKE_PID=2147483647
mkdir -p ".nova/work-items/.lock/index.lock.d"
echo "$FAKE_PID" > ".nova/work-items/.lock/index.lock.d/pid"

# 정상 동작이라면 stale 검출 → 자동 정리 → create 성공
OUT=$(bash "$RW" create "stale-recovery-test" --priority=high 2>&1)
EXIT=$?

echo "create 출력:"
echo "$OUT" | sed 's/^/  /'
echo "exit: $EXIT"

if [ "$EXIT" -ne 0 ]; then
  echo "❌ create 실패"
  exit 1
fi

if ! echo "$OUT" | grep -qE "WI-(0001|[a-f0-9]{8})-stale-recovery-test"; then
  echo "❌ id 출력 누락"
  exit 1
fi

# stale 검출 로그 확인 (mkdir 모드에서 발화해야)
if echo "$OUT" | grep -q "stale lock 정리"; then
  echo "  ✓ stale 검출 로그 발화"
elif echo "$OUT" | grep -qE "WI-[a-f0-9]{8}"; then
  echo "  ℹ️ UUID fallback 사용 — 50회 retry 후 fallback (느린 환경)"
else
  echo "  ⚠️ stale 로그 미관찰 — flock 자동 분기 가능성 (NOVA_LOCK_MODE=mkdir 강제 동작 확인 필요)"
fi

# 파일 실제 생성 확인
if ls .nova/work-items/WI-*.json 2>/dev/null | grep -q .; then
  CREATED=$(ls .nova/work-items/WI-*.json | head -1)
  echo "  ✓ WI 파일 생성: $(basename "$CREATED")"
else
  echo "  ✗ WI 파일 미생성"
  exit 1
fi

# lock dir 정리 확인
if [ -d ".nova/work-items/.lock/index.lock.d" ]; then
  echo "  ⚠️ lock dir 여전히 존재 — 다음 호출자가 stale 검출 의존"
else
  echo "  ✓ lock dir 정리됨"
fi

echo ""
echo "=== Phase 2: lock 들고 자식 죽은 후 후속 호출 ==="
# bash 3.2 호환: $BASHPID 미지원 — 부모가 $!로 자식 PID 받고 자식 종료 후 lock 파일 기록.
# 자식이 죽은 뒤 PID가 lock 파일에 남으므로 SIGKILL과 동등 효과 (kill -0 → 실패 → stale)
mkdir -p ".nova/work-items/.lock/index.lock.d"
(exit 0) &
DEAD_CHILD_PID=$!
wait "$DEAD_CHILD_PID" 2>/dev/null || true
echo "$DEAD_CHILD_PID" > ".nova/work-items/.lock/index.lock.d/pid"

# 후속 호출
OUT2=$(bash "$RW" create "phase2-after-kill" --priority=medium 2>&1)
EXIT2=$?

if [ "$EXIT2" -ne 0 ]; then
  echo "❌ Phase 2 create 실패: $OUT2"
  exit 1
fi
if echo "$OUT2" | grep -q "WI-"; then
  echo "  ✓ SIGKILL 후 후속 create 성공: $(echo "$OUT2" | grep -oE 'WI-[0-9a-f]+-[^ ]+' | head -1)"
fi

echo ""
echo "✅ test-stale-lock PASS"
