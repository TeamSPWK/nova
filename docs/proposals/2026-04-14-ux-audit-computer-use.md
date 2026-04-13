# Evolution Proposal: UX Audit에 Computer Use 통합

> 날짜: 2026-04-14
> 수준: minor
> 출처: https://code.claude.com/docs/en/whats-new/2026-w14
> 자율 등급: Semi Auto (PR)

## 발견
Claude Code CLI에 Computer Use 기능이 추가됨 (2026 Week 14). Claude가 네이티브 앱을 열고, UI를 클릭하고, 변경사항을 테스트하고, 문제를 수정할 수 있음.

## Nova 적용 방안
`/nova:ux-audit`에 `--live` 옵션 추가:
- 현재: 코드 기반 정적 분석만 수행 (CSS/컴포넌트 구조 분석)
- 개선: `--live` 시 Computer Use로 실제 앱을 브라우저에서 열고 시각적 검증 수행
- 5인 평가자 중 "접근성 전문가"와 "성능 전문가"가 실제 렌더링 결과를 기반으로 평가

활용 예:
```
/nova:ux-audit --live http://localhost:3000
```

## 영향 범위
- `.claude/skills/ux-audit/SKILL.md` — `--live` 옵션 추가, Computer Use 통합 절차
- `.claude/commands/ux-audit.md` — 옵션 설명 추가

## 리스크
- Computer Use는 아직 Research Preview — API 안정성 미보장
- 로컬 개발 서버가 실행 중이어야 함 (사전 조건 추가 필요)
- 브라우저 자동화 의존성이 늘어남
