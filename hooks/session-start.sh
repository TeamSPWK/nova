#!/usr/bin/env bash

# Nova Engineering — SessionStart Hook
# 매 세션 시작 시 핵심 규칙을 경량 주입. 상세는 커맨드 호출 시 로드.

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

cat << NOVA_EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "sessionTitle": "${SESSION_TITLE}",
    "additionalContext": "# Nova Engineering\n\nNova는 **AI Agent Ops 프레임워크**다. 5기둥(환경·맥락·품질·협업·진화)으로 에이전트가 안정적으로 일하도록 만든다. 아래 규칙은 가장 강한 기둥인 **품질**의 실행 계약이다.\n\nNOVA-STATE.md가 있으면 세션 시작 시 반드시 읽는다. 없으면 자동 생성된다.\n\n## 프로젝트 규칙 우선순위\n\n프로젝트 .claude/rules/가 있으면 Nova보다 우선.\n\n## 자동 적용 규칙\n\n1. **복잡도 판단**: 간단(1~2파일)→바로 구현, 보통(3~7)→Plan→구현, 복잡(8+)→Plan→Design→스프린트. 인증/DB/결제는 한 단계 상향.\n2. **검증 분리 + 하드 게이트**: 검증은 반드시 독립 서브에이전트(= 별도 spawn으로 컨텍스트 창 분리). 메인 에이전트가 직접 재확인하는 것은 독립 검증이 아님. 자가 점검: \"나는 구현한 에이전트와 동일 컨텍스트 창인가?\" — 그렇다면 Evaluator가 아님. **커밋 전 하드 게이트**: 구현 완료 → tsc/lint 통과 → Evaluator 실행 → PASS → 커밋 허용. Evaluator PASS 없이 커밋 시 exit 2 차단(예외: --emergency). **tmux pane**: 반드시 TeamCreate → Agent(name+team_name+run_in_background:true) 패턴 필수.\n3. **검증 기준**: 기능 동작, 데이터 관통(입력→저장→로드→표시), 설계 정합성, 에러 핸들링, 경계값(0/음수/빈값/최대값).\n4. **실행 검증 우선**: 코드 존재 ≠ 동작. 빌드+테스트+curl 확인. 환경 변경은 3단계(현재값→변경→반영 확인).\n5. **검증 경량화**: 기본 Lite. --strict 시 풀 검증.\n6. **스프린트 분할**: 8+파일은 스프린트로 분할. 스프린트 완료 = Evaluator 필수.\n7. **블로커 분류**: Auto-Resolve/Soft-Block/Hard-Block. 불확실하면 Hard-Block. 같은 실패 2회 시 강제 분류.\n8. **NOVA-STATE.md 갱신**: 즉시 트리거는 블로커 발생/해소·검증 FAIL만. 나머지는 커밋 전 일괄 갱신.\n9. **긴급 모드**: --emergency 시 즉시 수정, 검증 사후.\n10. **환경 안전**: 설정 파일 직접 수정 금지. 환경변수/CLI 플래그 사용.\n\n## Nova 커맨드\n\n/nova:plan, /nova:design, /nova:review, /nova:check, /nova:ask, /nova:run, /nova:setup, /nova:next, /nova:scan, /nova:auto, /nova:ux-audit, /nova:worktree-setup\nMCP 서버: mcp-server/ (빌드: cd mcp-server && pnpm build)\n\n## Always-On 행동 (MUST — 사용자가 Nova를 언급하지 않아도 적용)\n\n1. 모든 코드 변경 작업에 위 자동 적용 규칙을 적용한다.\n2. 3파일 이상 변경 시 반드시 Plan을 먼저 제시한다.\n3. 구현 완료 시 Evaluator를 독립 서브에이전트로 자동 실행한다.\n4. 커밋 전 /nova:review --fast를 자동 실행한다.\n5. 세션 시작 시 NOVA-STATE.md를 읽어 현재 상태를 파악한다.\n6. 블로커 발생 시 즉시 사용자에게 알린다.\n\n이 행동은 사용자가 Nova 커맨드를 직접 호출하지 않아도 항상 적용된다. Nova는 배경에서 자동으로 품질을 관리한다."
  }
}
NOVA_EOF

exit 0
