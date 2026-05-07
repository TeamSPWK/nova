# [Plan] UI/UX 인지 사이클 강화 (ui-ux-cycle-reinforcement)

> Nova Engineering — CPS Framework
> 작성일: 2026-04-18
> 작성자: jay-swk
> Design: docs/designs/ui-ux-cycle-reinforcement.md

---

## Context (배경)

### 현재 상태
- Nova의 UI/UX 자산은 `/nova:ux-audit`(5인 적대적 평가) **분석 전용**만 존재. 5인 평가자: Newcomer · Accessibility · Cognitive Load · Performance · Dark Pattern.
- UI 코드 변경은 일반 코드처럼 `/nova:run` / `/nova:auto`가 처리하며, **UI 특화 검증이 자동으로 트리거되지 않음** (사용자가 `/nova:ux-audit`을 명시적으로 호출해야 함).
- ux-audit 5인 중 **디자인 시스템 정합성**(토큰 우회, 의미별 시각 일관성)을 평가하는 관점이 없음.
- Claude Design (2026-04-17 출시), Figma MCP+Skills 등 외부 디자인 도구 생태계가 빠르게 정착 중이나, Nova는 특정 도구에 의존하지 않는 하네스 비의존성 원칙을 유지해야 함.

### 왜 필요한가
- **사용자 요구 (2026-04-18)**: "Nova에 UI/UX 특화 기술이 있는지? Claude Design 오픈으로 얼마나 서비스를 이해하고 구현하는지가 중요해진 시점."
- **5기둥 갭 분석**: UI/UX 영역에서 환경(입력 표면), 협업(자동 핸드오프), 진화(메트릭) 기둥에 갭. 품질 기둥은 ux-audit이 부분 커버하나 디자인 시스템 정합 영역 빈 칸.
- **AI 생성 UI의 흔한 위반**: 디자인 토큰 무시, 컴포넌트 일관성 붕괴 — Nova가 자동으로 잡지 않으면 사용자가 매번 수동으로 ux-audit 호출해야 함.

### 관련 자료
- 제안서 (재설계됨): `docs/proposals/2026-04-18-design-system-evaluator.md`
- **Nova는 범용 플러그인**: 특정 프로젝트(SWK 워크스페이스 등)에 종속되지 않음. fixture는 모두 기술 스택 기반 익명 이름 사용
- 폐기 제안서: `docs/proposals/2026-04-18-ui-build-command.md`, `2026-04-18-figma-skills-cooperation.md` (도구 종속 사유)
- X-Verification 결과 (합의율 85%, HUMAN REVIEW): `docs/verifications/2026-04-18-Nova-5기둥-AI-Agent-Ops-프레임워크-환경-맥락-품질-협업.md`
- Claude Design 출시: https://www.anthropic.com/news/claude-design-anthropic-labs
- 메모리: `feedback_nova_definition.md` (Nova = 5기둥, 품질만 아님)

---

## Problem (문제 정의)

### 핵심 문제
Nova는 UI 코드 변경 시 **(1) 디자인 시스템 정합성을 자동 검증하지 못하고**, **(2) UI 작업이라는 사실을 인식해 적절한 평가를 자동 트리거하지 못한다.** 두 갭 모두 신규 슬래시 커맨드/스킬 0개로 채워야 한다 (하네스 비의존성 + 추가 금지 원칙).

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | 품질 — 디자인 정합 검증 부재 | ux-audit 5인 평가자가 디자인 토큰 우회/의미별 시각 일관성을 검증하지 않음. AI 생성 UI에서 가장 흔한 위반 | 높음 |
| 2 | 환경 — UI 작업 인식 부재 | `/nova:auto`가 입력의 성격(UI/일반)을 구분하지 않아 적절한 검증을 자동 투입하지 못함 | 높음 |
| 3 | 협업 — 자동 핸드오프 부재 | UI 변경 시 ux-audit으로의 자동 핸드오프가 없어 사용자가 매번 수동 호출 | 중간 |
| 4 | 진화 — 메트릭 부재 | UI 감지 정확도/사용자 거부율을 측정하지 않아 자기교정 불가 | 중간 |
| 5 | 부담 — 추가 금지 원칙 충돌 위험 | 신규 커맨드/스킬을 만들면 사용자 인지 부하 ↑ | 높음 (제약) |

### 제약 조건
**기술적**:
- 신규 슬래시 커맨드/스킬 0개 (사용자 원칙)
- 특정 외부 도구(Claude Design, Figma 등) 비의존
- 기존 5인 평가자 구조 유지 (6번째 평가자 신설 금지 — 보고서 부담)
- session-start.sh additionalContext 1200자 이내 유지 (사용자 메모리)

**시간/리소스**:
- 2 Sprint로 분할 (보통 복잡도 4파일 + 6파일)
- 각 Sprint 독립 검증 가능해야 함

**비즈니스/원칙**:
- "좋은 기술이라고 무조건 추가하면 사용성 ↓ 혼란 ↑" (사용자 원칙)
- Nova = 5기둥 프레임워크 (품질로만 환원 금지)
- Generator-Evaluator 분리 유지

---

## Solution (해결 방안)

### 선택한 방안
**두 변경을 2 Sprint로 분할 진행 (Sprint A → Sprint B 순서)**:

- **Sprint A**: ux-audit Cognitive Load 평가자에 디자인 시스템 정합 항목 2개 흡수 (신규 평가자 추가 안 함)
- **Sprint B**: `/nova:auto`에 UI 변경 감지 분기 추가 (감지 시 ux-audit Lite 3인 자동 호출)

순서 근거: X-Verification에서 Claude+Gemini 2:1 합의 — "감사 품질이 먼저 탄탄해야 자동 호출이 가치 있음. 빈약한 감사가 자주 호출되면 신뢰 손상."

### 대안 비교

| 기준 | 방안 A (채택) | 방안 B | 방안 C |
|------|--------------|--------|--------|
| 핵심 | Cognitive Load 흡수 + auto UI 분기 | `/nova:ui-build` 신규 커맨드 + Claude Design handoff 어댑터 | 6번째 평가자(Design System Sentinel) 신설 |
| 신규 슬래시 커맨드 | 0개 | 1개 | 0개 |
| 도구 의존 | 0 | Claude Design / Figma 어댑터 | 0 |
| 평가자 수 변화 | 5인 유지 | - | 5인 → 6인 (보고서 부담) |
| 보고서 길이 | 변화 없음 | - | 1.2배 |
| 사용자 부담 | 거의 0 (자동 트리거) | 새 커맨드 학습 | 보고서 길이 ↑ |
| 5기둥 균형 | 환경+협업+품질+진화 4개 강화 | 환경 일부 | 품질만 |
| 선택 | **채택** | 기각 (도구 종속, 추가 원칙 위반) | 기각 (보고서 부담, 5인 → 6인 변경 부담) |

### 구현 범위

#### Sprint A — Cognitive Load 평가자 강화 (보통, 4파일)

**파일**:
- [ ] `skills/ux-audit/SKILL.md` — Cognitive Load 평가자 항목 추가 + Phase 1 환경 분석에 디자인 시스템 자동 감지
- [ ] `commands/ux-audit.md` — 동일 동기화
- [ ] `tests/test-scripts.sh` — 새 항목 검증 케이스
- [ ] `README.md`, `README.ko.md` — AUTO-GEN 테이블 갱신 (자동)

**구현 항목**:
- 항목 A: "같은 의미의 UI(에러/성공/경고)가 화면마다 다른 색·폰트로 표시되는가?" — 학습된 패턴 붕괴 → 인지 부하
- 항목 B (재정의): "디자인 토큰을 거치지 않은 하드코딩이 **인지 일관성을 깨는 경우**" — Claude 제안 채택, 단순 "토큰 우회" 표현 금지
- 디자인 시스템 자동 감지: `tailwind.config.{js,ts}`, `theme.{ts,js}`, `*.css :root`, `design-tokens/` 디렉토리
- 디자인 시스템 미정의 시 항목 B만 자동 비활성 + 보고서에 1줄 표기 ("디자인 시스템 정의 없음 — 토큰 검증 스킵")
- 평가자 출력 8건 제한 유지 + **디자인 항목 최대 3건 서브 제한** (항목이 보고서를 잠식하지 않도록)

#### Sprint B — `/nova:auto` UI 변경 감지 분기 (보통, 6파일)

**파일**:
- [ ] `commands/auto.md` — UI 감지 분기 추가, 사전 고지 메시지, 토글 옵션
- [ ] `hooks/session-start.sh` — `--no-ux-audit` 옵션 동기화 (해당 시)
- [ ] `tests/test-scripts.sh` — 휴리스틱/제외규칙/메트릭 검증
- [ ] `NOVA-STATE.md` — 갱신 형식 명시 (별도 파일이 아닌 인라인 통합)
- [ ] `docs/nova-rules.md` — 자동 적용 규칙에 UI 감지 1줄 추가 (해당 시)
- [ ] `README.md`, `README.ko.md` — AUTO-GEN 갱신

**구현 항목 — 휴리스틱 (강화 형태, X-Verification 반영)**:
- 기본 트리거: 변경 파일에 `*.tsx/*.jsx/*.vue/*.svelte` 또는 `styles/`·`theme/`·`design-tokens/` 경로 ≥ 1개
- **임계치**: 파일 수 ≥ 2 또는 UI 관련 변경 LoC ≥ 20 (1줄 수정 트리거 방지)
- **제외 규칙**: `*.test.*`, `*.spec.*`, `*.stories.*` 자동 제외
- **diff 키워드 정밀 체크**: `.tsx`라도 diff에 `className/style/styled/디자인 토큰명` 키워드 없으면 순수 로직으로 보고 스킵
- **monorepo 대응**: `packages/*/styles/`, `apps/*/components/` 와일드카드 매칭
- **CSS-in-JS 감지**: `.ts/.tsx`에 `styled-components`/`emotion` import 시 UI 작업 판정
- **재감사 skip**: `.nova/last-audit` 해시로 동일 변경 1회 캐싱

**구현 항목 — 동작**:
- 감지 시: auto 사이클 끝에 `ux-audit Lite (3인: Newcomer + Accessibility + Cognitive Load)` 자동 호출
- **사전 고지 (필수)**: auto 사이클 시작 시 "UI 변경 감지 → ux-audit Lite 병행 예정" 명시. 첫 트리거 시 1회 자세한 안내 + opt-out 유도, 이후는 한 줄
- **토글**:
  - `--no-ux-audit` (1회성)
  - `nova-config.json: { "auto.uiAudit": false }` (영구, 프로젝트별, .gitignore 안내 포함)

**구현 항목 — 진화 메트릭 (3 AI 합의로 추가)**:
- `.nova/metrics.jsonl`에 기록 (append-only)
  - `ui_audit_triggered_count`
  - `ui_audit_opt_out_count` (`--no-ux-audit` 사용 횟수)
  - `ui_audit_b_item_silenced_count` (디자인 시스템 미정의로 B 비활성화 횟수)
- 향후 `/nova:evolve --scan`에서 이 메트릭을 읽어 휴리스틱 자동 조정 후보로 활용 (이번 Plan에서는 기록만)

**NOVA-STATE.md 갱신 형식**:
```
## Last Activity
- /nova:auto → UI 감지 → ux-audit Lite PASS — Critical N / High N / Medium N / Low N | timestamp
```

### 검증 기준

#### Sprint A Done 조건 (Evaluator 검증 가능)
1. `bash tests/test-scripts.sh` 통과 (기존 + 신규 디자인 시스템 항목 케이스)
2. `/nova:review --fast` PASS (Critical 0)
3. SKILL.md와 commands/ux-audit.md 동기화 검증 (테스트로 자동 체크)
4. `tests/fixtures/react-component/`에서 1회 dry-run → Cognitive Load 평가자 출력에 디자인 항목 0~3건 포함 확인
5. 디자인 시스템 미정의 프로젝트(예: 백엔드 only)에서 항목 B 자동 비활성 + "스킵" 메시지 1줄 확인

#### Sprint B Done 조건
1. `bash tests/test-scripts.sh` 통과 (휴리스틱 + 제외 규칙 + 메트릭 케이스)
2. `/nova:review --fast` PASS (Critical 0)
3. **6종 익명 fixture dry-run** (`tests/fixtures/`, 외부 의존 0):
   - `react-component/` (단일 UI 변경 → 트리거 ✓)
   - `monorepo/` (packages/*/src 구조 → 트리거 ✓)
   - `css-in-js/` (.ts에 styled import → 트리거 ✓)
   - `backend-only/` (UI 0 → 트리거 ✗)
   - `logic-only/` (.tsx인데 useEffect만 → 트리거 ✗)
   - `critical-violation/` (Critical ≥1 → 커밋 차단 ✓)
   - dummy 백엔드 변경 (UI 0 → 트리거 ✗)
4. 사전 고지 메시지가 첫 트리거 시 1회 자세히, 이후 한 줄로 표시되는지 수동 확인
5. `--no-ux-audit` 옵션과 `nova-config.json` 영구 비활성 동작 확인
6. `.nova/metrics.jsonl`에 3가지 메트릭 기록 확인

#### 비목표 (Out of Scope)
- `/nova:ui-build` 신규 커맨드 (폐기 — 도구 종속)
- figma 협력 가이드 문서 (폐기 — 도구 종속)
- 6번째 평가자 신설 (폐기 — 보고서 부담)
- Claude Design API 어댑터 (폐기 — 하네스 비의존성)
- 디자이너 산출물(Figma export, 스크린샷) 입력 경로 (Known Gaps로 보류)
- 진화 메트릭 자동 분석 (이번에는 기록만, 분석은 차기 evolve에서)

---

## Sprints (스프린트 분할)

총 예상 파일: 10개 (4 + 6) → **8+ 기준 초과로 분할**.

| Sprint | 기능 단위 | 예상 파일 | 의존성 | Done 조건 |
|--------|----------|----------|--------|----------|
| **A** | Cognitive Load 평가자 디자인 항목 흡수 + 디자인 시스템 자동 감지 | 4 (skills/ux-audit/SKILL.md, commands/ux-audit.md, tests/test-scripts.sh, README*) | 없음 | tests PASS + review --fast PASS + `tests/fixtures/react-component/` dry-run + 디자인 시스템 미정의 시 B 비활성 검증 |
| **B** | /nova:auto UI 변경 감지 분기 + 휴리스틱/제외/사전고지/토글/메트릭 | 8 (skills/orchestrator/SKILL.md, scripts/detect-ui-change.sh 신규, scripts/detect-design-system.sh 신규, scripts/log-metric.sh 신규, tests/test-scripts.sh, tests/test-ui-audit-notice.sh 신규, tests/test-cache-hit.sh 신규, README*) — Design에서 정정됨 | Sprint A | tests PASS + review --fast PASS + 6종 익명 fixture dry-run + 사전 고지 동작 + 토글 동작 + .nova/metrics.jsonl 기록 |

**의존성 근거**: Sprint B가 호출하는 ux-audit Lite의 Cognitive Load 평가자는 Sprint A에서 강화된 버전을 사용해야 가치 발생. Sprint A 없이 Sprint B 먼저 하면 빈약한 감사가 자주 호출되어 신뢰 손상 (Claude+Gemini 합의).

---

## X-Verification (다관점 수집)

이미 완료됨 (`docs/verifications/2026-04-18-Nova-5기둥-...md`):

| AI | 의견 요약 | 합의 |
|----|----------|------|
| Claude | 방향 정합. **변경2(Sprint A) 먼저 + 임계치/제외규칙 + 진화 지표 3개 추가** 권장. B 항목은 "하드코딩이 인지 일관성을 깨는 경우"로 문구 재정의 시 정체성 유지 | O |
| GPT | 방향 좋음, 환경/품질 편향 있음. **변경1(Sprint B) 먼저** 권장 (자동 감지가 가치 회수 지점). B는 "Design Consistency rule"로 별도 태그 권장 | △ (우선순위·B 정체성 차이) |
| Gemini | 환경-품질-협업 정렬 우수. **변경2(Sprint A) 먼저** 권장. **diff 내 키워드 정밀 체크로 오탐 방지** 필수 | O |

**합의 수준**: Partial Consensus (합의율 85%, HUMAN REVIEW)

**해결된 갈림**:
- 우선순위: **Sprint A 먼저** 채택 (2:1)
- B 항목 정체성: **Cognitive Load 흡수 + Claude 문구 재정의** 채택 (2:1)

**Plan에 반영된 강한 합의 4개**:
1. 오탐 방지 필터 (임계치, 제외 규칙, diff 키워드, monorepo, 재감사 skip)
2. 사전 고지 (첫 1회 자세히, 이후 한 줄)
3. 항목 A 정체성 정합 확인
4. 진화 메트릭 3종 추가
