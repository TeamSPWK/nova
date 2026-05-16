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

# v5.35.2 — $NOVA_PLUGIN_ROOT 자동 export (CLAUDE_PLUGIN_ROOT 미주입 환경 폴백)
# 후속 Bash 도구 호출에서 "$NOVA_PLUGIN_ROOT/bin/nova-status" 같은 절대경로 참조 가능.
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -w "$(dirname "$CLAUDE_ENV_FILE")" 2>/dev/null ]; then
  _NOVA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd 2>/dev/null)"
  if [ -n "$_NOVA_ROOT" ] && [ -d "$_NOVA_ROOT/bin" ]; then
    echo "export NOVA_PLUGIN_ROOT=\"$_NOVA_ROOT\"" >> "$CLAUDE_ENV_FILE"
  fi
fi

# NOVA_ROOT 조기 정의 (Goal 추출 및 자동 마이그레이션에서 사용)
NOVA_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# NOVA-STATE.md에서 Goal 읽기 (v2 frontmatter 우선, v1 감지 시 자동 마이그레이션)
# Spec: docs/specs/nova-state-schema-v2.md §9 (자동 트리거)
SESSION_TITLE="Nova"
MIGRATE_NOTICE=""
if [ -f "NOVA-STATE.md" ] && command -v python3 >/dev/null 2>&1; then
  _STATE_INFO=$(python3 - <<'PYEOF' 2>/dev/null
import re, sys
try:
    import yaml
except ImportError:
    yaml = None

def _truncate_goal(g):
    """sessionTitle 시각 품질 — 강조 제거 + 자연 자르기 + 80자 cap (CJK 친화)"""
    if not g:
        return ''
    g = re.sub(r'\*\*(.+?)\*\*', r'\1', g)
    g = re.sub(r'__(.+?)__', r'\1', g)
    for sep in ('. ', ' — ', ' (', ', '):
        idx = g.find(sep)
        if 10 < idx < 80:
            g = g[:idx].rstrip().rstrip('.,—(')
            break
    if len(g) > 80:
        g = g[:80].rstrip() + '…'
    return g

try:
    text = open('NOVA-STATE.md', encoding='utf-8').read()
    # v2: YAML frontmatter
    m = re.match(r'^---\n(.*?)\n---', text, re.DOTALL)
    if m and yaml:
        fm = yaml.safe_load(m.group(1)) or {}
        if isinstance(fm, dict) and fm.get('schema_version') == 2:
            print(f"V2|{_truncate_goal(fm.get('goal', '') or '')}")
            sys.exit(0)
    # v1 fallback: - **Goal**: xxx (강조 제거 + truncate 적용)
    m2 = re.search(r'^- \*\*Goal\*\*:\s*(.+)$', text, re.MULTILINE)
    if m2:
        print(f"V1|{_truncate_goal(m2.group(1).strip())}")
        sys.exit(0)
except Exception:
    pass
print("NONE|")
PYEOF
)
  _STATE_VER="${_STATE_INFO%%|*}"
  GOAL="${_STATE_INFO#*|}"

  # v2 STATE 정상 — 이전 자동화 잔재 정리 (v5.40.x에서 생성된 파일들 cleanup)
  if [ "$_STATE_VER" = "V2" ]; then
    [ -f "NOVA-MIGRATE-PENDING.md" ] && rm -f NOVA-MIGRATE-PENDING.md 2>/dev/null || true
    [ -f ".nova/migrate-preview.md" ] && rm -f .nova/migrate-preview.md 2>/dev/null || true
    # v5.43.1+: v3 marker 부재 + .nova/work-items/ 부재 → v3 권고 (single-line hint)
    if [ "${NOVA_DISABLE_AUTO_MIGRATE:-0}" != "1" ] && \
       ! grep -qF "<!-- nova:registry-rendered:start -->" NOVA-STATE.md 2>/dev/null && \
       [ ! -f .nova/work-items/index.json ]; then
      MIGRATE_NOTICE="\n\n💡 NOVA-STATE.md v2 schema 감지, v3 work-item registry 미적용 — \`/nova:migrate-state\` 한 줄로 v3 변환 가능 (자동 마이그레이션 + drift-check)."
    fi
  fi

  # v1 STATE 감지 → 1줄 hint만 (자동 액션 X)
  # v5.41.0+: 자동 dry-run/preview 파일/sessionTitle prefix 모두 제거 — 사용자 보고 "자동화가 오히려 사용성 최악".
  # 변환은 사용자 명시 호출(/nova:migrate-state 커맨드 또는 직접 bash)로만.
  # NOVA_DISABLE_AUTO_MIGRATE=1 이면 hint도 스킵.
  if [ "$_STATE_VER" = "V1" ] && [ "${NOVA_DISABLE_AUTO_MIGRATE:-0}" != "1" ]; then
    MIGRATE_NOTICE="\n\n💡 NOVA-STATE.md v1 schema 감지 — \`/nova:migrate-state\` 한 줄로 v3 work-item registry 변환 가능 (v1→v3 직행, multi-hop 불필요). 자동 변환 안 함 (정보 손실 보호)."
  fi

  if [ -n "$GOAL" ]; then
    SESSION_TITLE="Nova: $GOAL"
  fi
elif [ -f "NOVA-STATE.md" ]; then
  # python3 미설치 환경 fallback (v1 패턴만)
  GOAL=$(grep -m1 '^\- \*\*Goal\*\*:' NOVA-STATE.md 2>/dev/null | sed 's/.*\*\*Goal\*\*: *//')
  [ -n "$GOAL" ] && SESSION_TITLE="Nova: $GOAL"
fi

# JSON 특수문자 이스케이프
SESSION_TITLE=$(echo "$SESSION_TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')

# Sprint 1: session_id 동기 선발급 + session_start 이벤트 기록 + start_epoch 저장 (safe-default)
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
  ADDITIONAL_CONTEXT="# Nova Engineering (lean)\n\nNova lean 모드 — 핵심 규칙만 적용. antipatterns 체크 스킵. pre-edit CPS 경고 스킵.\n\n## 규칙 (lean 핵심)\n\n1. **복잡도**: 간단(1~2)→바로. 보통(3~7)→Plan. 복잡(8+)→Plan→Design→스프린트. 자가 완화 금지.\n2. **검증 + 하드 게이트**: 검증은 독립 서브에이전트. 커밋 전 Evaluator PASS 필수. PASS 없이 커밋 시 exit 2 차단.\n3. **실행 검증**: 코드 존재 ≠ 동작. 빌드+테스트+curl.\n\n## Nova 커맨드\n\n/nova:plan · /nova:deepplan · /nova:design · /nova:review · /nova:check · /nova:audit-self · /nova:ask · /nova:run · /nova:setup · /nova:next · /nova:status · /nova:scan · /nova:auto · /nova:ux-audit · /nova:worktree-setup · /nova:claude-md · /nova:migrate-state\n\n## Always-On (MUST)\n\n1. 커밋 전 /nova:review --fast.\n2. NOVA-STATE.md 읽기/정리(50줄, Recently Done 3개, Last Activity 1줄. 초과 시 트림).\n3. UI 변경 시 G1+G3 시각 게이트 발화 (lean도 적용 — §14)."

# strict: standard + antipatterns 요약 추가
elif [ "$NOVA_PROFILE" = "strict" ]; then
  ADDITIONAL_CONTEXT="# Nova Engineering (strict)\n\nNova 자동 적용 규칙 — 품질 실행 계약. 상세는 docs/nova-rules.md 및 관련 커맨드가 on-demand 로드.\n\n## 규칙 (핵심)\n\n1. **복잡도**: 간단(1~2)→바로. 보통(3~7)→Plan. 복잡(8+)→Plan→Design→스프린트. 자가 완화 금지. 파일 수 초과 시 즉시 Plan 승격. duration heuristic(옵션): 1~2파일도 30분+ 예상이면 Plan 권고.\n2. **검증 + 하드 게이트**: 검증은 **독립 서브에이전트**. 커밋 전 Evaluator PASS 필수. exit 2 차단(--emergency 예외).\n3. **실행 검증**: 코드 존재 ≠ 동작. 빌드+테스트+curl. 환경 변경 3단계.\n4. **블로커**: Auto/Soft/Hard. 불확실=Hard.\n5. **환경 안전**: 설정 파일 직접 수정 금지.\n\n## Antipatterns — docs/nova-antipatterns.md\n\n§A1 복잡도 자가 완화 · §A3 Evaluator 후순위 · §B1 Evaluator 건너뛰고 커밋 · §B2 CPS 없이 구현 · §B3 세션 상태 갱신 생략 (전체 12개)\n\n## Nova 커맨드\n\n/nova:plan · /nova:deepplan · /nova:design · /nova:review · /nova:check · /nova:audit-self · /nova:ask · /nova:run · /nova:setup · /nova:next · /nova:status · /nova:scan · /nova:auto · /nova:ux-audit · /nova:worktree-setup · /nova:claude-md · /nova:migrate-state\n\n## Always-On\n\n1. 3파일+ 변경 시 Plan. 2. Evaluator 독립 서브에이전트. 3. 커밋 전 /nova:review --fast. 4. NOVA-STATE.md 읽기/정리(50줄, Recently Done 3개, Last Activity 1줄. 초과 시 트림). 5. UI 변경 시 G1+G3 시각 게이트 발화. 6. §15 Memory 라우팅: 프로젝트 규칙은 개인 memory 금지 → CLAUDE.md/AGENTS.md/\`.claude/rules/\`."

# standard (기본): 현재와 동일
else
  ADDITIONAL_CONTEXT="# Nova Engineering\n\nNova 자동 적용 규칙 — 품질 실행 계약. 상세는 docs/nova-rules.md 및 관련 커맨드가 on-demand 로드. 프로젝트 \`.claude/rules/\`가 있으면 Nova보다 우선.\n\n## 규칙 (핵심)\n\n1. **복잡도**: 간단(1~2)→바로. 보통(3~7)→Plan. 복잡(8+)→Plan→Design→스프린트. 인증/DB/결제 +1. 자가 완화 금지. 파일 수 초과 시 즉시 Plan 승격. duration heuristic(옵션): 1~2파일도 30분+ 예상이면 Plan 권고.\n2. **검증 + 하드 게이트**: 검증은 **독립 서브에이전트**(별도 spawn=창 분리). 메인 재확인은 독립 아님. 커밋 전 tsc/lint→Evaluator→PASS→커밋. PASS 없이 커밋 시 exit 2 차단(--emergency 예외). tmux pane: TeamCreate→Agent(name+team_name+run_in_background:true).\n3. **실행 검증**: 코드 존재 ≠ 동작. 빌드+테스트+curl. 환경 변경 3단계(현재→변경→반영).\n4. **블로커**: Auto/Soft/Hard. 불확실=Hard. 2회 실패 시 강제 분류.\n5. **환경 안전**: 설정 파일 직접 수정 금지. 환경변수/CLI 플래그.\n\n## Nova 커맨드\n\n/nova:plan · /nova:deepplan · /nova:design · /nova:review · /nova:check · /nova:audit-self · /nova:ask · /nova:run · /nova:setup · /nova:next · /nova:status · /nova:scan · /nova:auto · /nova:ux-audit · /nova:worktree-setup · /nova:claude-md · /nova:migrate-state\n\n## Always-On (MUST)\n\n1. 모든 코드 변경에 자동 규칙. 2. 3파일+ 변경 시 Plan. 3. 구현 완료 시 Evaluator 독립 서브에이전트. 4. 커밋 전 /nova:review --fast. 5. NOVA-STATE.md 읽기/정리(50줄, 초과 시 트림). 6. 블로커 즉시 알림. 7. UI 변경 시 G1+G3 시각 게이트. 8. §15 Memory 라우팅: 프로젝트 규칙은 개인 memory 금지 → CLAUDE.md/AGENTS.md/\`.claude/rules/\`."
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

  # ── §16 impl-tracker 미해소 advisory (v5.32.0+) ──
  # 코드 파일 임계 도달 + 1시간 이내 + Evaluator/review 흔적 0 시 1줄 노출.
  # 평소(임계 미도달, 1시간 만료, 마커 없음)에는 미노출.
  if [[ -f .nova/impl-tracker.json ]] && command -v jq >/dev/null 2>&1; then
    _IMPL_HIT=$(jq -r '.threshold_hit // false' .nova/impl-tracker.json 2>/dev/null)
    _IMPL_COUNT=$(jq -r '.count // 0' .nova/impl-tracker.json 2>/dev/null)
    _IMPL_LAST=$(jq -r '.last_set_epoch // 0' .nova/impl-tracker.json 2>/dev/null)
    _IMPL_AGE_MIN=$(( ($(date +%s) - _IMPL_LAST) / 60 ))
    if [[ "$_IMPL_HIT" = "true" ]] && (( _IMPL_AGE_MIN < 60 )); then
      ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}\n\n⚠️ impl-tracker: 코드 ${_IMPL_COUNT}파일 변경 후 review/evaluator 미실행 (§16). /nova:review --fast 또는 Agent(evaluator) 권장."
    fi
  fi
fi

# v1→v2 자동 마이그레이션 알림 append (있을 때만)
if [ -n "$MIGRATE_NOTICE" ]; then
  ADDITIONAL_CONTEXT="${ADDITIONAL_CONTEXT}${MIGRATE_NOTICE}"
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
