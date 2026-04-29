---
name: ux-audit 6번째 평가자 — Design System Compliance
description: ux-audit Adversarial Jury에 디자인 시스템 정합성 평가자 추가 (디자인 토큰 위반·하드코딩 색상·컴포넌트 재사용 누락 검출)
type: proposal
date: 2026-04-18
level: minor
status: pending
---

# Evolution Proposal: Design System Compliance 평가자 추가

> 날짜: 2026-04-18
> 수준: minor
> 출처:
> - https://www.figma.com/blog/design-systems-ai-mcp/
> - https://www.anthropic.com/news/claude-design-anthropic-labs
> 자율 등급: Semi Auto (PR 생성, 머지는 사용자)

## 발견

Claude Design과 Figma MCP가 모두 **디자인 시스템 자동 학습/정합**을 핵심 가치로 내세움. 핵심 메시지:

- "AI agents don't just help build products faster, but generate outputs aligned with the patterns and best practices designers and developers have crafted" (Figma 블로그)
- "automated design system rule generation, servers can scan codebases and output structured rules files outlining token definitions, component libraries, style hierarchies"
- Claude Design: "Claude builds a design system for your team by reading your codebase and design files, and every project after that uses your colors, typography, and components automatically"

## Nova의 갭

현재 ux-audit 5인 평가자는 디자인 시스템 정합성을 직접 평가하지 않는다:

- Newcomer — 온보딩/UX
- Accessibility — WCAG 2.2
- Cognitive Load — 인지 부하
- Performance — Core Web Vitals
- Dark Pattern — EU DSA

→ **하드코딩된 색상값**(`#FF0000` 같은 매직 넘버), **임의 폰트 크기**(`font-size: 13px` 디자인 토큰 미사용), **재사용 가능한 컴포넌트가 있는데 인라인으로 재구현**된 경우를 잡을 평가자가 없다.

이는 AI 에이전트가 UI를 생성할 때 **가장 흔히 저지르는 위반**이다 (디자인 시스템을 모르거나 무시).

## Nova 적용 방안

### 평가자 6: Design System Sentinel

```markdown
### 평가자 6: Design System Sentinel — 디자인 시스템 감시자

너는 팀의 디자인 시스템을 엄격하게 수호하는 디자인 엔지니어다.
디자인 토큰·컴포넌트 라이브러리·스타일 컨벤션의 일관성을 코드 레벨에서 검증한다.

평가 기준:

[디자인 토큰 준수]
1. 색상 하드코딩이 있는가? (`#FF0000`, `rgb(...)`, 임의 hex 값) — CSS 변수/토큰 미사용
2. 폰트 크기/굵기/family가 토큰을 거치지 않고 직접 지정되는가?
3. spacing/padding/margin이 디자인 시스템 스케일(예: 4/8/16/24)을 벗어나는 임의 값인가?
4. border-radius·shadow·transition이 토큰화되어 있지 않은가?
5. z-index가 명명된 레이어 시스템을 거치지 않는가?

[컴포넌트 재사용]
6. 기존 Button/Input/Card 컴포넌트가 있는데 인라인 div+style로 재구현했는가?
7. 디자인 시스템에 없는 패턴을 신규 도입할 때 합당한 근거가 있는가?
8. 컴포넌트 props가 디자인 시스템 variant 명세를 따르는가? (size: sm/md/lg, variant: primary/secondary)
9. 슬롯/composition 패턴이 일관되는가? (children vs render prop 혼용)

[스타일 일관성]
10. 같은 의미의 UI(예: 에러 상태)가 화면마다 다른 색/폰트로 표시되는가?
11. 다크 모드 토큰이 정의되어 있고 정합되는가? (`color-mix()`, prefers-color-scheme)
12. responsive breakpoint가 토큰화되어 있는가? (임의 값 px 미디어 쿼리)

분석 대상:
- 디자인 토큰 정의 파일 (tailwind.config, theme.ts, tokens.css, design-tokens/)
- CSS-in-JS / CSS 변수 사용 패턴
- 컴포넌트 라이브러리 (components/ui/, design-system/)
- 새로 추가된 UI 코드 vs 기존 컴포넌트 비교

출력: 문제 목록 (심각도 + 파일:라인 + 위반 토큰/컴포넌트 + 개선안). 최대 8건. 200단어 이내.
```

### 자동 디자인 시스템 추출

평가자 실행 전 환경 분석 단계에서 디자인 시스템 자동 스캔:

1. `tailwind.config.{js,ts}`, `theme.{ts,js}`, `*.css` `:root` 변수, `design-tokens/` 디렉토리 탐색
2. 발견한 토큰 → `[Nova UX Audit] 디자인 시스템: 토큰 N개, 컴포넌트 M개 발견` 표시
3. 평가자에게 토큰 카탈로그를 컨텍스트로 전달
4. 디자인 시스템이 없으면 평가자가 "디자인 시스템 정의 부재 — Critical" 1건 보고

## 영향 범위

**수정 파일**:
- `skills/ux-audit/SKILL.md` — 평가자 6 추가, Phase 1 환경 분석에 디자인 시스템 스캔 추가
- `commands/ux-audit.md` — 동일 동기화 (5인 → 6인)
- 종합 보고서 형식 — 평가자 표 행 추가
- `tests/test-scripts.sh` — ux-audit 6인 검증 케이스 추가
- `docs/nova-rules.md` — 해당 시 동기화

**호환성**:
- 기존 사용자 워크플로우 변경 없음 (평가자 추가만)
- Lite 모드(3인)에서는 디자인 시스템 평가자 제외 (성능 부담 없음)
- Full 모드(6인)에서 자동 활성화

## 리스크

| 리스크 | 완화 |
|--------|------|
| 디자인 시스템 정의 부재 프로젝트에서 false positive 폭발 | 디자인 시스템 미감지 시 1건 안내 보고 후 종료 (8건 폭주 차단) |
| 토큰 사용 강제가 prototype/POC에서 과도 | --skip-design-system 플래그 제공 |
| Tailwind/CSS-in-JS/CSS Modules 등 다양성 | 환경 분석에서 감지 후 평가자 컨텍스트에 스택 정보 주입 |

## 다음 단계

1. 사용자 승인 시 → `--apply` 모드로 구현
2. Gate 1: tests/test-scripts.sh
3. Gate 2: /nova:review --fast (Evaluator)
4. Gate 3: minor → PR 생성 (자동 머지 안 함)
5. `tests/fixtures/` 익명 fixture 6종으로 Field Test (Nova는 범용 플러그인이므로 외부 프로젝트 의존 0)
