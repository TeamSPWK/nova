---
name: figma 스킬과 Nova 품질 게이트 협력 가이드
description: 이미 로드된 figma:figma-* 스킬과 Nova(ux-audit/run)의 책임 분리 + 협력 워크플로우를 docs에 명시
type: proposal
date: 2026-04-18
level: patch
status: pending
---

# Evolution Proposal: figma 스킬과 Nova 협력 가이드 명시

> 날짜: 2026-04-18
> 수준: patch
> 출처:
> - https://uxplanet.org/figma-skills-for-claude-code-bb05a21984fd
> - https://www.figma.com/blog/the-figma-canvas-is-now-open-to-agents/
> - https://help.figma.com/hc/en-us/articles/39166810751895-Figma-skills-for-MCP
> 자율 등급: Full Auto (patch — 자동 커밋 가능)

## 발견

본 Claude Code 환경에 이미 다음 figma 스킬들이 로드되어 있음 (시스템 프롬프트의 available skills 섹션에서 확인):

- `figma:figma-generate-design` — 코드/명세 → Figma 화면 생성
- `figma:figma-implement-design` — Figma → 프로덕션 코드 1:1 구현
- `figma:figma-use` — Figma Plugin API 호출 (필수 prerequisite)
- `figma:figma-generate-library` — 코드베이스 → Figma 디자인 시스템 구축
- `figma:figma-create-design-system-rules` — 프로젝트 디자인 룰 생성
- `figma:figma-code-connect` — Figma 컴포넌트 ↔ 코드 매핑

이 스킬들은 **구현(implementation)**을 담당하지만, Nova의 **품질 게이트** 관점은 다루지 않는다 (figma 스킬은 figma의 관점, Nova는 5기둥의 관점).

## Nova의 갭

현재 Nova 문서에는 figma 스킬과의 협력 가이드가 없다. 사용자가 figma 스킬을 호출한 후 결과물을 Nova가 어떻게 검증하는지 명시되어 있지 않다.

이로 인해:
- figma 스킬로 구현한 UI에 대해 사용자가 ux-audit을 호출해야 함을 인지하지 못할 수 있음
- 두 스킬 생태계가 독립적으로 동작 → 품질 누락 가능

## Nova 적용 방안

### docs/integrations/figma-skills.md 신규 작성

내용:

```markdown
# figma 스킬과 Nova 품질 게이트 협력

## 책임 분리

| 영역 | figma 스킬 | Nova |
|------|-----------|------|
| Figma 캔버스 조작 | ✅ | ❌ |
| Figma → 코드 1:1 구현 | ✅ (figma-implement-design) | ❌ |
| 코드 → Figma 역방향 | ✅ (figma-generate-design) | ❌ |
| 디자인 시스템 추출 | ✅ (figma-generate-library) | ❌ |
| 구현된 코드의 적대적 검증 | ❌ | ✅ (/nova:ux-audit) |
| 접근성 WCAG 2.2 평가 | 부분 | ✅ (Accessibility Guardian) |
| Core Web Vitals 코드 진단 | ❌ | ✅ (Performance Critic) |
| 다크 패턴(EU DSA) 탐지 | ❌ | ✅ (Dark Pattern Detective) |
| 디자인 시스템 정합성 코드 검증 | 부분 | ✅ (Design System Sentinel — 추가 예정) |

## 권장 워크플로우

### 디자인 → 구현 → 검증

```
1. figma:figma-implement-design (또는 /nova:ui-build) → 초안 구현
2. /nova:run --strict → 빌드 + 테스트 + Evaluator
3. /nova:ux-audit --target src/components/NewFeature → 5인 적대적 평가
4. (Critical/High 발견 시) /nova:ux-audit --fix → 수정안 → 승인 → 적용
5. /nova:check → 커밋 직전 최종 정합성 점검
```

### 코드 → Figma (역방향 동기화)

```
1. /nova:check → 현재 코드 품질 확인
2. figma:figma-generate-design → 코드 → Figma 화면 생성
3. 디자이너 리뷰 (Figma)
4. 디자이너 피드백 → 다시 1로
```

## 자동 트리거 (제안)

`/nova:run` 또는 `/nova:check`가 다음 조건을 감지하면 ux-audit 권유:
- src/components/, app/, pages/ 하위 *.tsx/*.vue 변경
- styles/, theme/, design-tokens/ 변경
- figma 스킬이 직전에 호출된 흔적 (트랜스크립트 컨텍스트)

권유 메시지:
```
[Nova] UI 코드 변경 감지 — `/nova:ux-audit` 실행을 권장합니다.
       (figma 스킬 사용 직후라면 더욱 권장)
```
```

### commands/next.md 워크플로우 경로 추가

기존 워크플로우 추천에 UI 시나리오 분기 추가:

```
UI/UX 작업
  ├─ 신규 화면 구현
  │   ├─ Figma 있음 → figma:figma-implement-design → /nova:ux-audit
  │   ├─ Claude Design 있음 → /nova:ui-build (제안 중) → /nova:ux-audit
  │   └─ 명세만 있음 → /nova:plan → /nova:run → /nova:ux-audit
  └─ 기존 화면 개선 → /nova:ux-audit --fix
```

## 영향 범위

**신규 파일**:
- `docs/integrations/figma-skills.md` — 협력 가이드

**수정 파일**:
- `commands/next.md` — UI 시나리오 분기 추가
- `commands/run.md` — UI 변경 감지 시 ux-audit 권유 안내 1줄 추가
- `commands/check.md` — 동일
- `README.md` (선택) — Integrations 섹션 링크 추가

**호환성**: 100% — 문서 추가 및 안내 1줄 추가만, 동작 변경 없음.

## 리스크

| 리스크 | 완화 |
|--------|------|
| figma 스킬이 환경에 없을 수 있음 | 가이드는 "있을 때" 시나리오만 다룸. 강제하지 않음 |
| 권유 메시지가 사용자에게 잡음 | UI 파일 변경이 명백할 때만 (디렉토리/확장자 휴리스틱) |
| 미래 figma 스킬 변경 | 가이드는 책임 분리 원칙 중심으로 작성, 특정 스킬명에 강결합 안 함 |

## 다음 단계 (--apply 시)

1. `docs/integrations/figma-skills.md` 작성
2. `commands/next.md`에 UI 시나리오 분기 추가
3. `commands/run.md`, `commands/check.md`에 권유 1줄 추가
4. `bash tests/test-scripts.sh` 통과 확인
5. patch 자동 커밋 + 버전 범프 + 릴리스
