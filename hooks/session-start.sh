#!/usr/bin/env bash

# Nova Engineering — SessionStart Hook
# 핵심 5개 규칙만 경량 주입. 상세(§3/§5/§6/§8/§9)는 관련 커맨드·스킬이 on-demand 로드.
# Tier 2: NOVA_PROFILE=lean|standard|strict 런타임 분기. --emergency = lean 별칭.
# Tier 3: NOVA_SUBAGENT=1 감지 시 최소 메시지로 축약 (토큰 절감).

# ── NOVA_SUBAGENT bootstrap 격리 (Tier 3, §13) ──
# 서브에이전트는 메인 컨텍스트에서 이미 규칙을 받으므로 전체 주입 불필요.
# NOVA_SUBAGENT=1 또는 CLAUDE_CODE_SUBAGENT=1 감지 시 최소 메시지 반환.
if [[ "${NOVA_SUBAGENT:-}" = "1" ]] || [[ "${CLAUDE_CODE_SUBAGENT:-}" = "1" ]]; then
  cat << SUBAGENT_EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Nova subagent bootstrap skipped — 상세 규칙은 메인 컨텍스트 참조."
  }
}
SUBAGENT_EOF
  exit 0
fi

# --emergency 플래그 → lean 프로파일 별칭 (호환성 유지)
for arg in "$@"; do
  if [ "$arg" = "--emergency" ]; then
    NOVA_PROFILE="lean"
    break
  fi
done

NOVA_PROFILE="${NOVA_PROFILE:-standard}"

# NOVA-STATE.md에서 Goal을 읽어 세션 타이틀 생성
SESSION_TITLE="Nova"
if [ -f "NOVA-STATE.md" ]; then
  GOAL=$(grep -m1 '^\- \*\*Goal\*\*:' NOVA-STATE.md 2>/dev/null | sed 's/.*\*\*Goal\*\*: *//')
  if [ -n "$GOAL" ]; then
    SESSION_TITLE="Nova: $GOAL"
  fi
fi

# JSON 특수문자 이스케이프
SESSION_TITLE=$(echo "$SESSION_TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')

# Sprint 1: session_id 동기 선발급 + session_start 이벤트 기록 + start_epoch 저장 (safe-default)
NOVA_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if [[ -f "${NOVA_ROOT}/hooks/record-event.sh" ]] && [[ -z "${NOVA_DISABLE_EVENTS:-}" ]]; then
  mkdir -p .nova 2>/dev/null || true
  # Race-safe session.id 선발급 (이후 child spawn들이 이 id를 공유)
  if [[ ! -f .nova/session.id ]]; then
    _RAND=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | head -c 16)
    _SID=$(printf '%s%s%s' "$PWD" "$$" "$_RAND" | shasum -a 256 2>/dev/null | head -c 12)
    [[ -n "$_SID" ]] && ( set -C; echo "$_SID" > .nova/session.id ) 2>/dev/null || true
  fi
  date -u +%s > .nova/session.start_epoch 2>/dev/null || true
  # Debounce: 5초 이내 재호출 시 session_start 기록 스킵 (노이즈 억제)
  _DEBOUNCE_FILE=".nova/session.debounce"
  _SKIP_RECORD=0
  if [[ -f "$_DEBOUNCE_FILE" ]]; then
    _LAST=$(date -r "$_DEBOUNCE_FILE" +%s 2>/dev/null || \
            python3 -c "import os; print(int(os.path.getmtime('$_DEBOUNCE_FILE')))" 2>/dev/null || echo 0)
    _NOW=$(date -u +%s)
    if (( _NOW - _LAST < 5 )); then
      _SKIP_RECORD=1
    fi
  fi
  if [[ $_SKIP_RECORD -eq 0 ]]; then
    touch "$_DEBOUNCE_FILE" 2>/dev/null || true
    _TRIGGER="${CLAUDE_HOOK_TRIGGER:-unknown}"
    bash "${NOVA_ROOT}/hooks/record-event.sh" session_start "{\"trigger\":\"${_TRIGGER}\"}" 2>/dev/null &
  fi
fi

# ── 프로파일별 additionalContext 생성 ──

# lean: §1~§3만, antipatterns 생략, pre-edit CPS 경고 스킵
if [ "$NOVA_PROFILE" = "lean" ]; then
  ADDITIONAL_CONTEXT="# Nova Engineering (lean)\n\nNova lean 모드 — 핵심 규칙만 적용. antipatterns 체크 스킵. pre-edit CPS 경고 스킵.\n\n## 규칙 (lean 핵심)\n\n1. **복잡도**: 간단(1~2)→바로. 보통(3~7)→Plan. 복잡(8+)→Plan→Design→스프린트. 자가 완화 금지.\n2. **검증 + 하드 게이트**: 검증은 독립 서브에이전트. 커밋 전 Evaluator PASS 필수. PASS 없이 커밋 시 exit 2 차단.\n3. **실행 검증**: 코드 존재 ≠ 동작. 빌드+테스트+curl.\n\n## Nova 커맨드\n\n/nova:plan · /nova:deepplan · /nova:design · /nova:review · /nova:check · /nova:audit-self · /nova:ask · /nova:run · /nova:setup · /nova:next · /nova:scan · /nova:auto · /nova:ux-audit · /nova:worktree-setup\n\n## Always-On (MUST)\n\n1. 커밋 전 /nova:review --fast.\n2. NOVA-STATE.md 읽기/정리(50줄, Recently Done 3개, Last Activity 1줄. 초과 시 트림)."

# strict: standard + antipatterns 요약 추가
elif [ "$NOVA_PROFILE" = "strict" ]; then
  ADDITIONAL_CONTEXT="# Nova Engineering (strict)\n\nNova 자동 적용 규칙 — 품질 실행 계약. 상세는 docs/nova-rules.md 및 관련 커맨드가 on-demand 로드.\n\n## 규칙 (핵심)\n\n1. **복잡도**: 간단(1~2)→바로. 보통(3~7)→Plan. 복잡(8+)→Plan→Design→스프린트. 자가 완화 금지. 파일 수 초과 시 즉시 Plan 승격.\n2. **검증 + 하드 게이트**: 검증은 **독립 서브에이전트**. 커밋 전 Evaluator PASS 필수. exit 2 차단(--emergency 예외).\n3. **실행 검증**: 코드 존재 ≠ 동작. 빌드+테스트+curl. 환경 변경 3단계.\n4. **블로커**: Auto/Soft/Hard. 불확실=Hard.\n5. **환경 안전**: 설정 파일 직접 수정 금지.\n\n## Antipatterns — docs/nova-antipatterns.md\n\n§A1 복잡도 자가 완화 · §A3 Evaluator 후순위 · §B1 Evaluator 건너뛰고 커밋 · §B2 CPS 없이 구현 · §B3 세션 상태 갱신 생략 (전체 12개)\n\n## Nova 커맨드\n\n/nova:plan · /nova:deepplan · /nova:design · /nova:review · /nova:check · /nova:audit-self · /nova:ask · /nova:run · /nova:setup · /nova:next · /nova:scan · /nova:auto · /nova:ux-audit · /nova:worktree-setup\n\n## Always-On\n\n1. 3파일+ 변경 시 Plan. 2. Evaluator 독립 서브에이전트. 3. 커밋 전 /nova:review --fast. 4. NOVA-STATE.md 읽기/정리(50줄, Recently Done 3개, Last Activity 1줄. 초과 시 트림)."

# standard (기본): 현재와 동일
else
  ADDITIONAL_CONTEXT="# Nova Engineering\n\nNova 자동 적용 규칙 — 품질 실행 계약. 상세는 docs/nova-rules.md 및 관련 커맨드가 on-demand 로드. 프로젝트 \`.claude/rules/\`가 있으면 Nova보다 우선.\n\n## 규칙 (핵심)\n\n1. **복잡도**: 간단(1~2)→바로. 보통(3~7)→Plan. 복잡(8+)→Plan→Design→스프린트. 인증/DB/결제 +1. 자가 완화 금지. 파일 수 초과 시 즉시 Plan 승격.\n2. **검증 + 하드 게이트**: 검증은 **독립 서브에이전트**(별도 spawn=창 분리). 메인 재확인은 독립 아님. 커밋 전 tsc/lint→Evaluator→PASS→커밋. PASS 없이 커밋 시 exit 2 차단(--emergency 예외). tmux pane: TeamCreate→Agent(name+team_name+run_in_background:true).\n3. **실행 검증**: 코드 존재 ≠ 동작. 빌드+테스트+curl. 환경 변경 3단계(현재→변경→반영).\n4. **블로커**: Auto/Soft/Hard. 불확실=Hard. 2회 실패 시 강제 분류.\n5. **환경 안전**: 설정 파일 직접 수정 금지. 환경변수/CLI 플래그.\n\n## Nova 커맨드\n\n/nova:plan · /nova:deepplan · /nova:design · /nova:review · /nova:check · /nova:audit-self · /nova:ask · /nova:run · /nova:setup · /nova:next · /nova:scan · /nova:auto · /nova:ux-audit · /nova:worktree-setup\n\n## Always-On (MUST)\n\n1. 모든 코드 변경에 자동 규칙.\n2. 3파일+ 변경 시 Plan.\n3. 구현 완료 시 Evaluator를 독립 서브에이전트로 실행.\n4. 커밋 전 /nova:review --fast.\n5. NOVA-STATE.md 읽기/정리(50줄, Recently Done 3개, Last Activity 1줄. 초과 시 트림).\n6. 블로커 발생 시 즉시 알림."
fi

# ── §10 MCP 부하 카운트 (P1-2, v5.22.1+) ──
# 임계 초과(>10) 시만 경고 출력. ≤10 정상 카운트는 미표시.
# 캐시 1시간 + 캐시 미스 시 백그라운드 갱신 → 본 세션 응답 시간 영향 없음.
# lean 프로파일은 ≤1200자 보호로 스킵.
if [ "$NOVA_PROFILE" != "lean" ]; then
  _MCP_COUNT=""
  _MCP_CACHE=".nova/mcp-count.cache"
  if [[ -f "$_MCP_CACHE" ]]; then
    _CAGE=$(($(date +%s) - $(date -r "$_MCP_CACHE" +%s 2>/dev/null || echo 0)))
    if (( _CAGE < 3600 )); then
      _MCP_COUNT=$(cat "$_MCP_CACHE" 2>/dev/null)
    fi
  fi
  if [[ -z "$_MCP_COUNT" ]] && command -v claude >/dev/null 2>&1; then
    (
      mkdir -p .nova 2>/dev/null
      _NEW=$(timeout 5 claude mcp list 2>/dev/null | grep -cE '^[^[:space:]].+ - [✓✗!]' 2>/dev/null)
      [[ -n "$_NEW" && "$_NEW" -gt 0 ]] && echo "$_NEW" > "$_MCP_CACHE" 2>/dev/null
    ) &
  fi
  if [[ -n "$_MCP_COUNT" && "$_MCP_COUNT" =~ ^[0-9]+$ && "$_MCP_COUNT" -gt 10 ]]; then
    ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}\n\n⚠️ MCP ${_MCP_COUNT}개 활성 — ECC 권장 ≤10 초과. 컨텍스트 압박 (§10)."
  fi

  # ── measurement Phase 1 4주 미갱신 리마인더 (Sprint 3, measurement-spec.md §4 알고리즘 4) ──
  # 조건부 1줄 — baselines 파일 존재 + 가장 최신 mtime 28일+ 만 출력
  # 첫 주(파일 0건)는 미출력 (신규 사용자 보호)
  if [[ -d docs/baselines ]]; then
    _LATEST_BASELINE=$(ls -1 docs/baselines/*.json 2>/dev/null | sort | tail -1)
    if [[ -n "$_LATEST_BASELINE" ]]; then
      _BASE_MTIME=$(stat -f%m "$_LATEST_BASELINE" 2>/dev/null || stat -c%Y "$_LATEST_BASELINE" 2>/dev/null || echo 0)
      _AGE_DAYS=$(( ($(date +%s) - _BASE_MTIME) / 86400 ))
      if (( _AGE_DAYS > 28 )); then
        ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}\n\n⚠️ baselines ${_AGE_DAYS}일 미갱신 — bash scripts/publish-metrics.sh 권장."
      fi
    fi
  fi
fi

cat << NOVA_EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "sessionTitle": "${SESSION_TITLE}",
    "additionalContext": "${ADDITIONAL_CONTEXT}"
  }
}
NOVA_EOF

exit 0
