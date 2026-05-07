# [Plan] Adaptive Quality Gate

> Nova Engineering — CPS Framework
> 작성일: 2026-04-13
> 작성자: Claude (Nova Evolve)
> Design:

---

## Context (배경)

### 현재 상태
- Nova 품질 게이트: `tsc/lint → Evaluator (Layer 1~3) → PASS/CONDITIONAL/FAIL`
- Evaluator는 코드 변경에 대해 정적 분석, LLM 의미론적 분석, 실행 검증 3단계를 수행
- **Coverage Gate 부재**: 테스트 존재 여부/커버리지 변화를 체계적으로 추적하지 않음. Evaluator 재량에 의존
- **Adaptive 측정 부재**: Nova 규칙이 프로젝트에 실제로 효과적인지 측정하는 메커니즘이 없음
- **Learned Rules 부재**: `/review`가 반복 지적하는 패턴을 규칙으로 축적하는 메커니즘이 없음

### 왜 필요한가
- **시장 데이터**: AI 커밋 기여율 42%, 병목이 코드 작성 → 코드 검증으로 이동 (AI Code Review Benchmark 2026)
- **CodeScene 연구**: Code Health 9.4+ 유지 시 AI 유발 버그가 현저히 감소. Two-Gate(Health+Coverage)가 단일 게이트보다 효과적
- **Cursor Bugbot 사례**: Learned Rules 도입 후 해결율 52% → 80%. 44,000+ 프로젝트별 커스텀 룰
- **Nova Adaptive 원칙(A)**: "규칙이 프로젝트와 함께 진화한다" — 현재는 선언만 있고 구체적 메커니즘이 없음

### 관련 자료
- [CodeScene: Agentic AI Quality Gates](https://codescene.com/blog/agentic-ai-coding-best-practice-patterns-for-speed-with-quality)
- [Cursor Bugbot Learned Rules](https://cursor.com/blog/bugbot-learning)
- [Anthropic: Harness Design](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- Evolve 제안서: `docs/proposals/2026-04-13-evolve-scan.md` (X1, X2)

---

## Problem (문제 정의)

### 핵심 문제
Nova의 품질 게이트가 프로젝트별 맥락을 학습하지 않아, 모든 프로젝트에 동일한 규칙을 적용하고 테스트 커버리지 변화를 체계적으로 추적하지 못한다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | **Coverage 사각지대** | Evaluator가 테스트 존재/커버리지 변화를 체계적으로 확인하지 않음. "빌드 통과 = 품질 OK" 오류 | 높음 |
| 2 | **규칙 경직성** | 모든 프로젝트에 동일한 Evaluation Criteria 적용. React 프로젝트와 CLI 도구에 같은 기준 | 높음 |
| 3 | **반복 지적 비효율** | 같은 패턴을 매번 리뷰에서 반복 지적. 규칙화하지 않으면 개선이 축적되지 않음 | 중간 |
| 4 | **효과 불투명** | 어떤 규칙이 실제로 버그를 잡았는지, 어떤 규칙이 노이즈인지 알 수 없음 | 중간 |

### 제약 조건
- **영구 런타임 없음**: Nova는 Claude Code 플러그인. DB나 서버가 없다. 모든 상태는 파일 기반
- **세션 간 상태**: `NOVA-STATE.md`와 `.claude/rules/`, `.claude/settings.json`만 세션 간 유지
- **프로젝트별 다양성**: 언어, 프레임워크, 테스트 도구가 프로젝트마다 다름
- **사용자 승인 필수**: AI가 독단적으로 규칙을 추가/변경하지 않음 (AXIS 원칙)
- **session-start.sh 경량화**: additionalContext 1200자 이내 유지

---

## Solution (해결 방안)

### 선택한 방안

**프롬프트 기반 Adaptive Quality Gate** — 새로운 런타임/DB 없이, Evaluator 프롬프트 강화 + `.claude/rules/` 활용 + NOVA-STATE.md 확장으로 구현.

### 대안 비교

| 기준 | A: 프롬프트 기반 (채택) | B: MCP 서버 확장 | C: 외부 서비스 연동 |
|------|----------------------|----------------|-------------------|
| 구현 복잡도 | 낮음 — 프롬프트/규칙 파일 수정 | 중간 — TypeScript 코딩 필요 | 높음 — 외부 의존성 |
| 영구 상태 | `.claude/rules/` + NOVA-STATE.md | MCP 서버 내 메모리/파일 | 외부 DB |
| 프로젝트 이식성 | 높음 — 파일만 복사 | 중간 — MCP 서버 설치 필요 | 낮음 — 서비스 가입 |
| 사용자 제어 | 높음 — rules/ 직접 편집 가능 | 중간 | 낮음 |
| 확장성 | 낮음 — 복잡한 통계 어려움 | 높음 | 높음 |
| **선택** | **채택** | 기각 (과도한 엔지니어링) | 기각 (외부 의존성) |

> **채택 근거**: Nova의 핵심 가치는 "플러그인 설치만으로 즉시 동작". MCP 서버 확장은 빌드 단계가 필요하고, 외부 서비스는 가입이 필요하다. 프롬프트 기반은 제한적이지만, Cursor Bugbot도 초기에는 단순한 규칙 매칭으로 시작하여 점진적으로 고도화했다. "시작은 단순하게, 효과가 입증되면 고도화"가 올바른 순서.

### 구현 범위

#### 1. Coverage Gate (X1)
- [ ] Evaluator Layer 3에 Coverage 체크 공식 추가
- [ ] `--strict` 모드에서 프로젝트별 커버리지 도구 자동 감지 + 실행
- [ ] Coverage 하락 시 Warning (기본) / FAIL (`--strict`)
- [ ] 테스트 미존재 프로젝트: "테스트 없음" Info 보고 (게이트 차단 아님)

#### 2. Learned Rules (X2-a)
- [ ] `/review` 판정 후 반복 패턴 감지 시 규칙 후보 제안
- [ ] 사용자 승인 → `.claude/rules/{slug}.md` 파일 자동 생성
- [ ] Evaluator가 `.claude/rules/` 참조하여 프로젝트별 기준 적용
- [ ] `/setup --upgrade`에서 learned rules 현황 보고

#### 3. Adaptive 측정 (X2-b)
- [ ] NOVA-STATE.md에 `## Quality Metrics` 섹션 추가
- [ ] `/review` 실행마다 판정 결과를 메트릭에 누적 (PASS/CONDITIONAL/FAIL 카운트)
- [ ] `/next`에서 Quality Metrics 기반 추천 (예: "최근 FAIL 빈도가 높습니다. 규칙 점검을 권장합니다")

### 검증 기준
1. **Coverage Gate**: `--strict` 모드에서 테스트가 있는 프로젝트의 커버리지를 실행하고 결과를 리뷰에 포함한다
2. **Learned Rules**: `/review` 후 반복 패턴이 감지되면 규칙 후보를 제안하고, 승인 시 `.claude/rules/`에 파일이 생성된다
3. **Adaptive 측정**: `/review` 실행 후 NOVA-STATE.md의 Quality Metrics가 갱신되고, `/next`에서 참조된다
4. **기존 테스트 통과**: `bash tests/test-scripts.sh` 190/190 PASS 유지
5. **session-start.sh 경량화**: additionalContext 1200자 이내 유지

---

## Sprints

예상 수정 파일: 10+ → 스프린트 분할

| Sprint | 기능 단위 | 예상 파일 | 의존성 | Done 조건 |
|--------|----------|----------|--------|----------|
| 1 | Coverage Gate | `skills/evaluator/SKILL.md`, `commands/review.md`, `commands/check.md`, `docs/eval-checklist.md` | 없음 | Evaluator에 Coverage 체크 항목 존재 + `--strict` 시 커버리지 실행 로직 명시 |
| 2 | Learned Rules | `commands/review.md`, `skills/evaluator/SKILL.md`, `commands/setup.md`, `docs/templates/learned-rule.md` (신규) | Sprint 1 | `/review` 후 규칙 후보 제안 로직 + `.claude/rules/` 생성 가이드 존재 |
| 3 | Adaptive 측정 + 동기화 | `docs/templates/nova-state.md`, `commands/next.md`, `hooks/session-start.sh`, `docs/nova-rules.md` | Sprint 2 | Quality Metrics 섹션 + `/next` 참조 + session-start 동기화 + 테스트 통과 |

---

## X-Verification (다관점 수집)

> 이 설계에서 가장 논쟁적인 판단은 **"Coverage 하락을 FAIL로 할 것인가 Warning으로 할 것인가"**이다.
> 필요 시 `/ask`로 Claude + GPT + Gemini 의견을 수렴할 수 있다.
>
> 현재 판단: **기본 Warning, `--strict`에서만 FAIL**
> 근거: 테스트가 아예 없는 프로젝트에서 FAIL이 기본이면 Nova 채택 장벽이 높아진다.
