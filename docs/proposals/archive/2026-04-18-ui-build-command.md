---
name: /nova:ui-build — Claude Design Handoff Receiver
description: Claude Design이 만든 handoff bundle 또는 Figma 명세를 받아 Nova 품질 게이트를 거쳐 구현하는 새 커맨드
type: proposal
date: 2026-04-18
level: major
status: pending
---

# Evolution Proposal: /nova:ui-build — Claude Design Handoff Receiver

> 날짜: 2026-04-18
> 수준: major
> 출처:
> - https://www.anthropic.com/news/claude-design-anthropic-labs
> - https://venturebeat.com/technology/anthropic-just-launched-claude-design-an-ai-tool-that-turns-prompts-into-prototypes-and-challenges-figma
> - https://uxplanet.org/figma-skills-for-claude-code-bb05a21984fd
> - https://www.figma.com/blog/design-systems-ai-mcp/
> 자율 등급: Manual (제안만 — 새 커맨드 추가는 사용자 결정)

## 발견

**Claude Design 출시 (2026-04-17)** — Anthropic Labs가 Opus 4.7 기반 디자인 도구를 research preview로 공개. 핵심은 두 가지:

1. **디자인 시스템 자동 추출** — 온보딩 시 코드베이스 + 디자인 파일을 읽어 팀의 색상·타이포·컴포넌트를 학습. 이후 모든 출력이 자동 정합.
2. **Handoff Bundle → Claude Code closed loop** — 디자인이 완성되면 모든 컨텍스트(컴포넌트, 토큰, 프로토타입 의도)를 번들로 패키징하여 Claude Code로 "단일 명령으로 전달"하여 프로덕션 코드로 전환. 향후 몇 주 내 통합 API 확장 예정.

**Figma 생태계 정착 (2026-03~04)** — Figma MCP + Claude Code 스킬 (`generate-design`, `generate-prototype`, `design-review`, `qa-signoff`)이 디자이너의 실전 워크플로우로 자리잡음. 이미 본 시스템에 `figma:figma-implement-design`, `figma:figma-generate-design`, `figma:figma-use` 스킬이 로드되어 있음.

## Nova의 갭

| 영역 | 상태 |
|------|------|
| UI/UX **분석(audit)** | ✅ `/nova:ux-audit` (5인 적대적 평가) — 강력 |
| UI/UX **구현(build)** | ❌ 없음 — Generator 측면 비어 있음 |
| 디자인 시스템 **추출(extract)** | ❌ 없음 — 코드/Figma에서 토큰 학습 부재 |
| 디자인 → 코드 **handoff 흡수** | ❌ 없음 — Claude Design 번들 수신 경로 없음 |

> 사용자 질문의 핵심: "얼마나 서비스를 이해하고 구현을 하는지" — Nova는 "이해(분석)"는 있으나 "구현"의 품질 게이트가 없다. UI 코드는 `/nova:run`이 일반 코드처럼 처리하므로, **디자인 정합성·접근성·디자인 시스템 위반**을 잡을 게이트가 부재.

## Nova 적용 방안

### 1. 새 커맨드 `/nova:ui-build`

```
/nova:ui-build [입력 소스] [옵션]

입력 소스 (택1):
  --handoff <path>       Claude Design handoff bundle (JSON/디렉토리)
  --figma <url>          Figma 파일 URL (Figma MCP 경유)
  --spec <path>          마크다운 디자인 명세
  --screenshot <path>    스크린샷 + 자연어 설명

옵션:
  --target <경로>        구현할 프로젝트 경로
  --design-system <path> 기존 디자인 시스템 정의 (없으면 자동 추출)
  --strict               --fast 검증 대신 풀 검증 + ux-audit Lite
```

**실행 플로우 (4 Phase)**:

```
Phase 1: Design Context Extraction
  - handoff/Figma/spec에서 컴포넌트·토큰·인터랙션 추출
  - 기존 코드베이스의 디자인 시스템과 대조 (figma:figma-implement-design 스킬 활용)
  - 출력: design-context.json (토큰·컴포넌트 매핑·인터랙션 명세)

Phase 2: Plan (CPS)
  - 복잡도 판단 (8+파일이면 스프린트 자동 분할)
  - 컴포넌트 단위 작업 분할 + 디자인 시스템 정합 체크포인트

Phase 3: Implementation (Generator)
  - figma 스킬 또는 senior-dev 에이전트로 구현
  - 디자인 토큰 하드코딩 금지 (CSS 변수/토큰 사용)
  - 접근성 속성(aria-*, role, tabIndex) 자동 포함

Phase 4: Quality Gate (Evaluator + ux-audit)
  - tsc/lint
  - ux-audit Lite (Newcomer + Accessibility + Design System Compliance 3인)
  - 설계 정합성 검증 (handoff 명세 vs 구현)
  - PASS 시 커밋 허용
```

### 2. ux-audit과의 짝 구조

```
/nova:ui-build → 구현
       ↓
/nova:ux-audit → 적대적 5인 평가 (감사)
       ↓
/nova:ui-build --fix → 회귀 수정
```

build와 audit이 짝을 이뤄 Generator-Evaluator 분리 철학 유지.

### 3. Claude Design Handoff Bundle 스키마 (추정 + 확장 가능 설계)

번들 정확 스키마는 미공개이나, 어댑터 패턴으로 설계:

```typescript
interface HandoffBundle {
  meta: { source: 'claude-design' | 'figma' | 'spec'; version: string };
  designSystem: { tokens: Record<string, any>; components: ComponentSpec[] };
  screens: ScreenSpec[];
  interactions: InteractionSpec[];
  assets?: { path: string; type: string }[];
}
```

Claude Design API가 정식 공개되면 어댑터만 교체.

## 영향 범위

**신규 파일**:
- `commands/ui-build.md` — 새 커맨드 정의
- `skills/ui-build/SKILL.md` — Generator 스킬 (figma 스킬과 협력)
- `docs/designs/ui-build-handoff-schema.md` — 번들 스키마 명세

**수정 파일**:
- `hooks/session-start.sh` — 커맨드 목록에 `/nova:ui-build` 추가
- `commands/next.md` — 워크플로우 추천 경로에 ui-build → ux-audit 짝 추가
- `commands/run.md` — UI 변경 감지 시 `/nova:ui-build` 권유 안내
- `tests/test-scripts.sh` — EXPECTED_COMMANDS 배열 + 동기화 테스트
- `README.md` / `README.ko.md` — AUTO-GEN 테이블 자동 갱신

**의존**:
- Figma MCP (선택, --figma 모드)
- 기존 figma:figma-* 스킬 (스킬 간 협력)
- senior-dev 에이전트 (Phase 3 fallback)

## 리스크

| 리스크 | 완화 |
|--------|------|
| Claude Design API 미공개 → handoff 번들 형식 불확실 | 어댑터 패턴 + `--spec` 모드로 우회 가능 (마크다운 명세) |
| Figma MCP 의존 | --figma 모드만 의존, 다른 모드는 독립 |
| 기존 figma 스킬과 역할 중복 | Nova는 **품질 게이트**에 집중, figma 스킬은 **구현 실행**에 집중. 명확한 책임 분리 |
| major 변경 → 사용자 결정 필요 | --auto에서도 자동 커밋 금지, 제안서 단계에서 정지 |
| UI 도구 도메인 진출 = 스코프 확장 | Nova의 "환경·맥락·품질·협업·진화" 5기둥 중 **품질** 강화로 정당화. UI 코드도 코드다 |

## 우선순위 근거

- 사용자(jay-swk)가 명시적으로 제기한 영역
- Claude Design은 어제 출시 → **선점 가치** 큼 (Nova가 가장 먼저 흡수하면 표준 워크플로우 가능)
- 기존 ux-audit와 자연스러운 짝 (Generator-Evaluator 분리)
- 사용자 메모리: "구조화 > 자연어" 원칙 (project_nova_orbit_kickoff.md, feedback_structured_over_natural_language.md) — UI 빌드도 CPS 기반 구조화가 더 일관된 결과를 낼 가능성 높음

## 다음 단계

1. 사용자 승인 시: `/nova:design ui-build` → CPS Design 문서 작성
2. Sprint 분할 (Phase 1~4 각각 1 sprint, 총 4 sprint 예상)
3. (폐기됨 — 진행하지 않음)
