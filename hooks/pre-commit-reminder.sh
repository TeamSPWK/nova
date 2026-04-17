#!/usr/bin/env bash

# Nova Engineering — PreToolUse Hook (Bash)
# git commit 명령 감지 시 NOVA-STATE.md 갱신 확인 + verify 리마인더를 주입.

# $TOOL_INPUT 환경변수에 Bash 도구의 command가 전달됨
INPUT="${TOOL_INPUT:-}"

# git commit 패턴 감지 (git commit, git -c ... commit 등)
if echo "$INPUT" | grep -qE '^\s*git\s+(.*\s+)?commit(\s|$)'; then

  # ------ Evaluator Hard Gate (Sprint 1) ------
  check_evaluator_pass() {
    # 출력: PASS | MISSING | EMPTY | NO_PASS | STALE | TIMESTAMP_BROKEN

    [ ! -f "NOVA-STATE.md" ] && echo "MISSING" && return

    # ## Last Activity 섹션 첫 줄 추출 (헤더 다음 첫 번째 "- " 라인)
    LAST_LINE=$(awk '/^## Last Activity/{flag=1; next} flag && /^- /{print; exit}' NOVA-STATE.md)

    [ -z "$LAST_LINE" ] && echo "EMPTY" && return

    # PASS 포함 여부 — 화살표 이후 PASS/CONDITIONAL만 인정 (서술형 오탐 방지)
    echo "$LAST_LINE" | grep -qE '→\s*(PASS|CONDITIONAL)' || { echo "NO_PASS"; return; }

    # 타임스탬프 추출: "| YYYY-MM-DD" 패턴
    TS=$(echo "$LAST_LINE" | grep -oE '\| [0-9]{4}-[0-9]{2}-[0-9]{2}' | sed 's/| //')
    [ -z "$TS" ] && echo "TIMESTAMP_BROKEN" && return

    # 오늘 날짜와 비교 (Sprint 1은 당일 기준)
    TODAY=$(date +%Y-%m-%d)
    [ "$TS" = "$TODAY" ] && echo "PASS" || echo "STALE"
  }

  # --emergency 감지 (플래그 또는 환경변수)
  EMERGENCY=0
  if echo "$INPUT" | grep -q -- "--emergency" || [ "${NOVA_EMERGENCY:-0}" = "1" ]; then
    EMERGENCY=1
  fi

  if [ "$EMERGENCY" = "1" ]; then
    echo "[Nova Hard Gate] --emergency 우회 감지 — Evaluator 검증 없이 커밋 진행" >&2
  else
    EVAL_STATUS=$(check_evaluator_pass)
    if [ "$EVAL_STATUS" != "PASS" ]; then
      cat >&2 << EOF
[Nova Hard Gate] COMMIT BLOCKED
이유: Evaluator PASS 미확인 (상태: ${EVAL_STATUS})

상태별 조치:
  MISSING           -> NOVA-STATE.md 없음. /nova:check 실행 후 커밋.
  EMPTY             -> Last Activity 섹션 비어있음. 검증 기록 추가 필요.
  NO_PASS           -> 최근 활동에 PASS 없음. /nova:review 또는 /nova:check 실행.
  STALE             -> 마지막 PASS가 오늘 날짜가 아님. 재검증 필요.
  TIMESTAMP_BROKEN  -> 타임스탬프 파싱 실패. NOVA-STATE.md 포맷 확인.

긴급 우회:
  git commit -m "메시지 --emergency"
  또는 NOVA_EMERGENCY=1 git commit ...
EOF
      exit 2
    fi
  fi
  # ------ End Evaluator Hard Gate ------

  # NOVA-STATE.md 갱신 여부 확인
  STATE_STALE=""
  if [ -f "NOVA-STATE.md" ]; then
    # staged 파일에 NOVA-STATE.md가 포함되어 있는지 확인
    if ! git diff --cached --name-only 2>/dev/null | grep -q "NOVA-STATE.md"; then
      STATE_STALE="⚠️ NOVA-STATE.md가 이번 커밋에 포함되지 않았습니다. 갱신이 필요한지 확인하세요."
    fi
  fi

  # nova-meta.json 최신 여부 확인
  META_STALE=""
  if [ -f "docs/nova-meta.json" ] && [ -f "scripts/generate-meta.sh" ]; then
    META_VER=$(python3 -c "import json; print(json.load(open('docs/nova-meta.json'))['stats']['commands'])" 2>/dev/null || echo "0")
    ACTUAL_CMD=$(ls -1 .claude/commands/*.md 2>/dev/null | wc -l | tr -d ' ')
    if [ "$META_VER" != "$ACTUAL_CMD" ]; then
      META_STALE="⚠️ nova-meta.json이 최신이 아닙니다 (meta: ${META_VER}개, 실제: ${ACTUAL_CMD}개). bash scripts/release.sh를 사용하세요."
    fi
  fi

  # 변경 파일 수 감지
  CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

  if [ "$CHANGED_FILES" -ge 3 ]; then
    cat << NOVA_EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "[Nova Quality Gate] git commit 감지 — 변경 파일 ${CHANGED_FILES}개.\n\n${STATE_STALE}\n${META_STALE}\n\n3파일 이상 변경입니다. Nova Always-On 규칙에 따라:\n1. NOVA-STATE.md를 갱신했는가? (필수)\n2. /nova:review --fast 를 실행했는가? (필수)\n3. 검증 결과가 PASS인가?\n\n💡 릴리스 시 bash scripts/release.sh <patch|minor|major> \"메시지\" 를 사용하면 전체 절차가 자동 실행됩니다."
  }
}
NOVA_EOF
  else
    cat << NOVA_EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "[Nova Quality Gate] git commit 감지 — 변경 파일 ${CHANGED_FILES}개.\n\n${STATE_STALE}\n${META_STALE}\n\n소규모 변경입니다. 로직 변경이 포함되어 있다면 /nova:review --fast를 권장합니다.\n💡 릴리스 시 bash scripts/release.sh <patch|minor|major> \"메시지\" 를 사용하세요."
  }
}
NOVA_EOF
  fi
fi

exit 0
