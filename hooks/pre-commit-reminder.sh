#!/usr/bin/env bash

# Nova Engineering — PreToolUse Hook (Bash) — v5.18.3
# git commit 감지 시 Evaluator Hard Gate 적용 + NOVA-STATE.md 갱신 리마인더
#
# Claude Code hooks 공식 스펙: stdin으로 JSON 전달. v5.18.2가 공식 스펙 확정.
# v5.18.2 이전 버전은 환경변수 가정이 no-op 버그였음 (v5.18.3 hotfix로 수정).
#
# 상태 머신 7가지:
#   PASS / MISSING / CONFLICT / EMPTY / NO_PASS / TIMESTAMP_BROKEN / STALE
#
# 우회 스위치:
#   NOVA_DISABLE_EVENTS=1 — 훅 최상위 우회 (테스트용)
#   NOVA_EMERGENCY=1 또는 커밋 메시지에 --emergency — EMERGENCY 우회
#     (단, CONFLICT 상태에서는 우회 불가 — repo 손상 유발)

# ── 최상위 우회 스위치 ──
if [ "${NOVA_DISABLE_EVENTS:-0}" = "1" ]; then
  exit 0
fi

# ── stdin JSON 파싱 (fail-closed 정책) ──
# tty 수동 실행(Claude Code 외부)은 차단 안 함. 빈/깨진 stdin은 fail-closed.
COMMAND=""
if [ ! -t 0 ]; then
  INPUT_JSON=$(cat 2>/dev/null || true)
  if [ -z "$INPUT_JSON" ]; then
    exit 2
  fi
  COMMAND=$(echo "$INPUT_JSON" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 2
else
  exit 0
fi

# ── git commit 패턴 필터 ──
# `git commit`, `git -c foo=bar commit`, `git commit --amend` 등 매칭
if ! echo "$COMMAND" | grep -qE '^\s*git\s+(.*\s+)?commit(\s|$)'; then
  exit 0
fi

# ── EMERGENCY 플래그 감지 (CONFLICT 상태에서는 무시) ──
EMERGENCY=0
if echo "$COMMAND" | grep -q -- "--emergency" || [ "${NOVA_EMERGENCY:-0}" = "1" ]; then
  EMERGENCY=1
fi

# ── Evaluator Hard Gate 7상태 판정 ──
# 판정 순서 고정: MISSING → CONFLICT → EMPTY → NO_PASS → TIMESTAMP_BROKEN → STALE → PASS
check_evaluator_pass() {
  if [ ! -f "NOVA-STATE.md" ]; then
    echo "MISSING"
    return
  fi

  # merge conflict 마커 감지 (N1: MISSING 직후, awk 파서 보호)
  if grep -q '^<<<<<<<' NOVA-STATE.md; then
    echo "CONFLICT"
    return
  fi

  # v2 STATE (schema_version: 2) 분기 — ## 📊 Recent Activity 표 첫 row 검사
  # Spec: docs/specs/nova-state-schema-v2.md §4
  if head -10 NOVA-STATE.md | grep -q "^schema_version: *2"; then
    FIRST_ROW=$(awk '
      /^## 📊 Recent Activity/{flag=1; next}
      flag && /^\| *[0-9]/{print; exit}
    ' NOVA-STATE.md)
    if [ -z "$FIRST_ROW" ]; then
      echo "EMPTY"; return
    fi
    # 결과 컬럼 ✅ / PASS / CONDITIONAL 인정
    if ! echo "$FIRST_ROW" | grep -qE '✅|PASS|CONDITIONAL'; then
      echo "NO_PASS"; return
    fi
    # 시각 컬럼: YYYY-MM-DD 또는 MM-DD (CJK 친화 표기 허용)
    TS=$(echo "$FIRST_ROW" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{2}-[0-9]{2}' | head -1)
    if [ -z "$TS" ]; then
      echo "TIMESTAMP_BROKEN"; return
    fi
    # MM-DD면 올해 추가
    case "$TS" in
      [0-9][0-9][0-9][0-9]-*) ;;
      *) TS="$(date +%Y)-$TS" ;;
    esac
    TODAY=$(date +%Y-%m-%d)
    if [ "$TS" = "$TODAY" ]; then
      echo "PASS"
    else
      echo "STALE"
    fi
    return
  fi

  # v1 legacy fallback — ## Last Activity 섹션 첫 "- " 라인 추출
  LAST_LINE=$(awk '/^## Last Activity/{flag=1; next} flag && /^- /{print; exit}' NOVA-STATE.md)

  if [ -z "$LAST_LINE" ]; then
    echo "EMPTY"
    return
  fi

  # PASS/CONDITIONAL 마커 확인 (화살표 이후만 인정, 서술형 오탐 방지)
  if ! echo "$LAST_LINE" | grep -qE '→\s*(PASS|CONDITIONAL)'; then
    echo "NO_PASS"
    return
  fi

  # 타임스탬프 추출: "YYYY-MM-DD" 패턴
  TS=$(echo "$LAST_LINE" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  if [ -z "$TS" ]; then
    echo "TIMESTAMP_BROKEN"
    return
  fi

  # 오늘 날짜와 비교
  TODAY=$(date +%Y-%m-%d)
  if [ "$TS" = "$TODAY" ]; then
    echo "PASS"
  else
    echo "STALE"
  fi
}

STATE=$(check_evaluator_pass)

# ── 이벤트 기록 헬퍼 (safe-default: 실패해도 Hard Gate 집행 영향 없음) ──
record_gate_event() {
  local event_type="$1"
  local extra_json="$2"
  local plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
  if [ -x "$plugin_root/hooks/record-event.sh" ]; then
    bash "$plugin_root/hooks/record-event.sh" "$event_type" "$extra_json" 2>/dev/null || true
  fi
}

# ── CONFLICT: EMERGENCY 초월 fail-closed (N3) ──
if [ "$STATE" = "CONFLICT" ]; then
  cat >&2 << 'EOF'
[Nova Hard Gate] COMMIT BLOCKED — CONFLICT 상태

NOVA-STATE.md에 merge conflict 마커(<<<<<<<)가 있습니다.
NOVA_EMERGENCY 우회 불가 — merge conflict를 먼저 해결한 뒤 커밋하세요.

해결:
  1. NOVA-STATE.md를 열어 <<<<<<<, =======, >>>>>>> 마커 제거
  2. git add NOVA-STATE.md
  3. git commit
EOF
  record_gate_event commit_blocked "$(printf '{"state":"CONFLICT","emergency":false}')"
  exit 2
fi

# ── 다른 차단 상태 (EMERGENCY 우회 가능) ──
if [ "$STATE" != "PASS" ]; then
  if [ "$EMERGENCY" = "1" ]; then
    echo "[Nova Hard Gate] --emergency 우회 감지 — 상태: ${STATE}" >&2
    record_gate_event commit_emergency "$(printf '{"state":"%s"}' "$STATE")"
    # fall-through → 아래 리마인더 컨텍스트 주입
  else
    cat >&2 << EOF
[Nova Hard Gate] COMMIT BLOCKED
이유: Evaluator PASS 미확인 (상태: ${STATE})

상태별 조치:
  MISSING           -> NOVA-STATE.md 없음. /nova:check 실행 후 커밋.
  EMPTY             -> Last Activity 섹션 비어있음. 검증 기록 추가 필요.
  NO_PASS           -> 최근 활동에 PASS 없음. /nova:review 또는 /nova:check 실행.
  STALE             -> 마지막 PASS가 오늘 날짜가 아님. 재검증 필요.
  TIMESTAMP_BROKEN  -> 타임스탬프 파싱 실패. NOVA-STATE.md 포맷 확인.

긴급 우회:
  git commit -m "메시지 --emergency"
  또는 NOVA_EMERGENCY=1 git commit ...

  ※ CONFLICT 상태는 우회 불가 (merge 해결 선결)
EOF
    record_gate_event commit_blocked "$(printf '{"state":"%s","emergency":false}' "$STATE")"
    exit 2
  fi
fi

# ── 정상 경로 — NOVA-STATE.md / nova-meta.json 갱신 리마인더 ──

# NOVA-STATE.md가 이번 커밋에 포함되었는지
STATE_STALE=""
if [ -f "NOVA-STATE.md" ]; then
  if ! git diff --cached --name-only 2>/dev/null | grep -q "NOVA-STATE.md"; then
    STATE_STALE="⚠️ NOVA-STATE.md가 이번 커밋에 포함되지 않았습니다. 갱신이 필요한지 확인하세요."
  fi
fi

# nova-meta.json 최신 여부
META_STALE=""
if [ -f "docs/nova-meta.json" ] && [ -f "scripts/generate-meta.sh" ]; then
  META_VER=$(python3 -c "import json; print(json.load(open('docs/nova-meta.json'))['stats']['commands'])" 2>/dev/null || echo "0")
  ACTUAL_CMD=$(ls -1 .claude/commands/*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$META_VER" != "$ACTUAL_CMD" ]; then
    META_STALE="⚠️ nova-meta.json이 최신이 아닙니다 (meta: ${META_VER}개, 실제: ${ACTUAL_CMD}개). bash scripts/release.sh를 사용하세요."
  fi
fi

# STATE 드리프트 NUDGE (S2 — reconcile-state.sh 호출, graceful)
# 제약: 차단 경로(Hard Gate FAIL)는 이 지점에 도달 안 함. 실패가 커밋을 막으면 안 됨.
DRIFT_NUDGE=""
_plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_reconcile_bin="$_plugin_root/scripts/reconcile-state.sh"
if [ -x "$_reconcile_bin" ]; then
  # timeout 3초 — 폴백 체인: timeout → gtimeout → perl alarm → 무제한(최후)
  # macOS 기본 환경엔 timeout/gtimeout 둘 다 없음 → perl alarm이 3초 상한 보장
  if command -v timeout >/dev/null 2>&1; then
    _recon_out=$(timeout 3 bash "$_reconcile_bin" --jsonl 2>/dev/null) || true
  elif command -v gtimeout >/dev/null 2>&1; then
    _recon_out=$(gtimeout 3 bash "$_reconcile_bin" --jsonl 2>/dev/null) || true
  elif command -v perl >/dev/null 2>&1; then
    _recon_out=$(perl -e 'alarm 3; exec @ARGV' bash "$_reconcile_bin" --jsonl 2>/dev/null) || true
  else
    _recon_out=$(bash "$_reconcile_bin" --jsonl 2>/dev/null) || true
  fi
  if [ -n "$_recon_out" ] && echo "$_recon_out" | jq -e . >/dev/null 2>&1; then
    _suspect=$(echo "$_recon_out" | jq '(.counts.suspect_explicit // 0) + (.counts.suspect_fuzzy // 0)' 2>/dev/null || echo "0")
    _untracked=$(echo "$_recon_out" | jq '(.counts.untracked // 0)' 2>/dev/null || echo "0")
    _total=$(( _suspect + _untracked ))
    if [ "$_total" -ge 1 ]; then
      _explicit=$(echo "$_recon_out" | jq '(.counts.suspect_explicit // 0)' 2>/dev/null || echo "0")
      _fuzzy=$(echo "$_recon_out" | jq '(.counts.suspect_fuzzy // 0)' 2>/dev/null || echo "0")
      DRIFT_NUDGE="⚠️ STATE 드리프트: 완료의심 ${_suspect}(explicit:${_explicit}/fuzzy:${_fuzzy}) · 추적불가 ${_untracked} — \`bash scripts/reconcile-state.sh\`로 확인"
      if [ "$_explicit" -ge 1 ]; then
        DRIFT_NUDGE="${DRIFT_NUDGE}\n커밋 후: bash scripts/registry-write.sh transition <wi> done --evidence-commit=\$(git rev-parse HEAD)"
      fi
      # state_reconciled 이벤트 기록 (safe-default: 실패해도 커밋·훅 영향 0)
      _state_class=$(echo "$_recon_out" | jq -r '.state_class // "unknown"' 2>/dev/null || echo "unknown")
      _counts_json=$(echo "$_recon_out" | jq -c '.counts // {}' 2>/dev/null || echo "{}")
      record_gate_event state_reconciled "$(printf '{"state_class":"%s","counts":%s,"trigger":"pre-commit"}' "$_state_class" "$_counts_json")"
    fi
  fi
fi

# 변경 파일 수
CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

if [ "$CHANGED_FILES" -ge 3 ]; then
  cat << NOVA_EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "[Nova Quality Gate] git commit 감지 — 변경 파일 ${CHANGED_FILES}개.\n\n${STATE_STALE}\n${META_STALE}\n${DRIFT_NUDGE}\n\n3파일 이상 변경입니다. Nova Always-On 규칙에 따라:\n1. NOVA-STATE.md를 갱신했는가? (필수)\n2. /nova:review --fast 를 실행했는가? (필수)\n3. 검증 결과가 PASS인가?\n\n💡 릴리스 시 bash scripts/release.sh <patch|minor|major> \"메시지\" 를 사용하면 전체 절차가 자동 실행됩니다."
  }
}
NOVA_EOF
else
  cat << NOVA_EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "[Nova Quality Gate] git commit 감지 — 변경 파일 ${CHANGED_FILES}개.\n\n${STATE_STALE}\n${META_STALE}\n${DRIFT_NUDGE}\n\n소규모 변경입니다. 로직 변경이 포함되어 있다면 /nova:review --fast를 권장합니다.\n💡 릴리스 시 bash scripts/release.sh <patch|minor|major> \"메시지\" 를 사용하세요."
  }
}
NOVA_EOF
fi

exit 0
