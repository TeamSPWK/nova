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
# 판정 순서 고정: events.jsonl 4h 윈도 → MISSING → CONFLICT → EMPTY → NO_PASS → TIMESTAMP_BROKEN → STALE → PASS
# v5.48.1+: events.jsonl의 review_pass 이벤트가 4시간(NOVA_PASS_WINDOW_SEC 환경변수로 오버라이드 가능) 이내면 우선 PASS.
#          fallback은 기존 NOVA-STATE.md Recent Activity 첫 row 로직(하위 호환).
# ── v5.53.0+: review_pass 파일 바인딩 헬퍼 (self-attest 우회 차단) ──
# 게이트 4h 윈도 PASS를 "review_pass가 현재 staged 파일을 커버"할 때만 인정한다.
# files 없는(무바인딩) review_pass 한 줄(`record-event.sh review_pass '{}'`)로 게이트를
# 통과시키던 우회를 닫는다 — 측정 채널(events.jsonl)과 통과 채널을 분리.
# sha 소스는 staged blob(`git show :<path>`) — 리뷰 시점·커밋 시점이 동일 소스라야 일치.

# staged 파일들의 content sha256(개행 분리) 출력. git/shasum/staged 없으면 빈 출력(보수적).
_staged_content_shas() {
  command -v git >/dev/null 2>&1 || return 0
  command -v shasum >/dev/null 2>&1 || return 0
  local f sha
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sha=$(git show ":$f" 2>/dev/null | shasum -a 256 2>/dev/null | awk '{print $1}')
    [ -n "$sha" ] && printf '%s\n' "$sha"
  done < <(git -c core.quotepath=false diff --cached --name-only 2>/dev/null)
}

# in-window review_pass 중 staged_shas를 모두 커버(부분집합)하는 게 있으면 exit 0.
# 인자: <events_file> <cutoff_epoch> <now_epoch> <staged_shas(개행분리)>
_window_review_pass_covers() {
  local events_file="$1" cutoff="$2" now="$3" staged_shas="$4"
  local line ts ledger_shas ledger_oneline
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ts=$(printf '%s' "$line" | jq -r '.timestamp_epoch // 0' 2>/dev/null || echo 0)
    case "$ts" in ''|*[!0-9]*) continue ;; esac
    # 윈도 범위 + 미래(NTP 역행/시계 오설정) 방어
    [ "$ts" -ge "$cutoff" ] || continue
    [ "$ts" -le "$now" ] || continue
    ledger_shas=$(printf '%s' "$line" | jq -r '.extra.files[].content_sha256 // empty' 2>/dev/null)
    [ -n "$ledger_shas" ] || continue
    # awk -v 는 개행 포함 값을 거부(BSD/macOS awk: "newline in string") → sha(공백 없는 hex)를 공백 조인.
    ledger_oneline=$(printf '%s' "$ledger_shas" | tr '\n' ' ')
    # staged_shas ⊆ ledger_shas ?
    if printf '%s\n' "$staged_shas" | awk -v ledger="$ledger_oneline" '
        BEGIN { n=split(ledger, L, " "); for(i=1;i<=n;i++) if(L[i]!="") H[L[i]]=1 }
        NF { if (!($1 in H)) { bad=1; exit } }
        END { exit (bad?1:0) }
      '; then
      return 0
    fi
  done < <(grep '"event_type":"review_pass"' "$events_file" 2>/dev/null)
  return 1
}

check_evaluator_pass() {
  # ── v5.48.1+: events.jsonl review_pass 시간 윈도 조회 (단일 진실원 정합) ──
  local events_file="${NOVA_EVENTS_PATH:-.nova/events.jsonl}"
  local window_sec="${NOVA_PASS_WINDOW_SEC:-14400}"  # 기본 4시간
  # 비숫자 값 정규화: 잘못된 NOVA_PASS_WINDOW_SEC가 아래 `-gt` 정수 비교에서 에러를 내며
  # 윈도 로직을 침묵 우회하는 것을 방지 (기본값으로 강제 fallback)
  case "$window_sec" in ''|*[!0-9]*) window_sec=14400 ;; esac
  # NOVA_PASS_WINDOW_SEC=0이면 윈도 비활성화 (fallback만 사용 — 디버그/엄격 모드)
  # 상한 클램핑: 86400(1일) 초과 설정은 정책 무력화 방지를 위해 1일로 강제 제한
  if [ "$window_sec" -gt 86400 ]; then
    window_sec=86400
  fi
  if [ "$window_sec" -gt 0 ] && [ -f "$events_file" ] && command -v jq >/dev/null 2>&1; then
    # v5.53.0+: 파일 바인딩 — staged 파일을 커버하는 in-window review_pass만 PASS 인정.
    # (구버전은 최신 review_pass의 timestamp만 봐서 `review_pass '{}'` 한 줄로 우회 가능했음.)
    local now_epoch cutoff_epoch staged_shas
    now_epoch=$(date +%s)
    cutoff_epoch=$((now_epoch - window_sec))
    staged_shas=$(_staged_content_shas)
    # staged 코드 파일이 없으면(doc-only/삭제) 윈도 바인딩 평가 불가 → fallback/SCOPE_SKIP가 처리.
    if [ -n "$staged_shas" ] \
       && _window_review_pass_covers "$events_file" "$cutoff_epoch" "$now_epoch" "$staged_shas"; then
      echo "PASS"
      return
    fi
  fi

  # ── fallback: NOVA-STATE.md 본문 검사 (events.jsonl 없거나 윈도 초과) ──
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

# ── v5.48.1+: scope 필터 (doc-only 커밋 Hard Gate skip) ──
# 보수적 화이트리스트 — 모든 staged 파일이 매치하면 STATE 무관하게 통과(CONFLICT 제외).
# 매치 제외: docs/specs/, docs/plans/, docs/designs/, docs/proposals/, docs/nova-rules.md,
#           docs/eval-checklist.md, docs/nova-antipatterns.md — 이들은 코드와 동등 무게.
#
# rename(R) 보안: --name-only는 새 경로만 반환 → `git mv scripts/foo.sh docs/guides/foo.md`
# 같은 코드→docs 이동이 우회 가능. --name-status 기반으로 old+new 경로 모두 검사.
SCOPE_SKIP=0
CHANGED_FILES_LIST=$(git diff --cached --name-status 2>/dev/null | awk '{for(i=2;i<=NF;i++) print $i}' || true)
if [ -n "$CHANGED_FILES_LIST" ]; then
  # 화이트리스트에 매치되지 않는 파일이 하나라도 있으면 NON_DOC에 포함
  NON_DOC=$(echo "$CHANGED_FILES_LIST" | grep -vE '^(README|CHANGELOG|LICENSE)([._-].*)?$|^\.gitignore$|^docs/guides/|^dev/docs/|^\.nova/|^docs/nova-meta\.json$' || true)
  if [ -z "$NON_DOC" ]; then
    SCOPE_SKIP=1
  fi
fi

# ── 다른 차단 상태 (EMERGENCY 우회 가능 + scope 필터 우회 가능) ──
if [ "$STATE" != "PASS" ]; then
  if [ "$SCOPE_SKIP" = "1" ]; then
    echo "[Nova Hard Gate] scope 필터 통과 — doc-only 커밋 (상태: ${STATE})" >&2
    record_gate_event commit_scope_skip "$(printf '{"state":"%s","files":%s}' "$STATE" "$(echo "$CHANGED_FILES_LIST" | jq -R . | jq -sc .)")"
    # fall-through → 아래 리마인더 컨텍스트 주입
  elif [ "$EMERGENCY" = "1" ]; then
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
  STALE             -> 최근 PASS 없음(review_pass 4h+ 이전, staged 파일 미커버, 또는 NOVA-STATE.md 첫 row가 오늘 아님). /nova:review 재실행.
  TIMESTAMP_BROKEN  -> 타임스탬프 파싱 실패. NOVA-STATE.md 포맷 확인.

자동 우회 (v5.48.1+):
  scope 필터    — README/CHANGELOG/LICENSE/docs/guides/dev/docs 등 doc-only 커밋은 자동 통과
  4시간 윈도     — review_pass가 4시간 이내 + staged 파일 sha 커버 시 자동 통과 (v5.53.0+ 바인딩)
                  (NOVA_PASS_WINDOW_SEC 환경변수로 윈도 조정 가능)

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
