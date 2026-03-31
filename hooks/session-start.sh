#!/usr/bin/env bash

# Nova Engineering — SessionStart Hook
# 매 세션 시작 시 핵심 규칙을 경량 주입. 상세는 커맨드 호출 시 로드.

cat << 'NOVA_EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "# Nova Engineering\n\n프로젝트에 NOVA-STATE.md가 있으면 세션 시작 시 반드시 읽는다.\n\n## 프로젝트 규칙 우선순위\n\n프로젝트에 .claude/rules/가 있으면 해당 규칙이 Nova 규칙보다 우선한다. Nova는 프로젝트 규칙을 보완하는 역할이다.\n\n## 자동 적용 규칙\n\n1. **복잡도 판단**: 간단(1~2파일)→바로 구현, 보통(3~7)→Plan→구현, 복잡(8+)→Plan→Design→스프린트 분할. 인증/DB/결제는 한 단계 상향. 독립적 반복 작업(린트, import 정리 등)은 파일 수와 무관하게 하향 가능. 작업 중 파일이 초기 예상을 넘으면 복잡도를 재판단한다.\n2. **검증 분리 (필수)**: 구현 후 검증은 반드시 독립 서브에이전트로 실행. 예외 없음. '빠르게 해줘'로 Plan/Design은 생략 가능하나, 검증(Evaluator)은 생략 불가.\n3. **검증 기준**: 기능 동작, 데이터 관통(입력→저장→로드→표시), 설계 정합성, 에러 핸들링/엣지 케이스.\n4. **실행 검증 우선**: '코드가 존재한다' ≠ '동작한다'. 가능하면 실제 테스트를 실행한다.\n5. **검증 경량화**: 기본은 Lite. --strict 요청 시에만 풀 검증.\n6. **스프린트 분할**: 8+파일 수정은 독립 검증 가능한 스프린트로 분할.\n7. **블로커 분류**: Auto-Resolve(되돌리기 가능)→자동, Soft-Block(런타임 위험)→기록 후 계속, Hard-Block(데이터 손실/보안)→즉시 중단. 불확실하면 Hard-Block.\n8. **NOVA-STATE.md 갱신 (CRITICAL)**: Nova 커맨드 실행 후 반드시 업데이트. 건너뛰지 마라.\n9. **긴급 모드 (--emergency)**: 프로덕션 장애 시 Plan/Design/복잡도 판단을 생략하고 즉시 수정. 검증은 비동기로 사후 실행. NOVA-STATE.md에 긴급 수정 기록 필수.\n\n## Nova 커맨드\n\n| 커맨드 | 설명 |\n|--------|------|\n| /nova:plan | CPS Plan 문서 |\n| /nova:design | CPS Design 문서 |\n| /nova:review | 적대적 코드 리뷰 (--fix로 자동 수정) |\n| /nova:verify | review + gap 통합 검증 |\n| /nova:gap | 설계↔구현 검증 |\n| /nova:xv | 멀티 AI 교차검증 |\n| /nova:auto | 구현→검증 자율 실행 |\n| /nova:init | 새 프로젝트 초기 설정 |\n| /nova:next | 다음 할 일 추천 |\n| /nova:propose | 규칙 제안 |\n| /nova:metrics | 도입 수준 측정 |"
  }
}
NOVA_EOF

exit 0
