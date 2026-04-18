---
name: orchestrator
description: Nova Orchestrator — 자연어 요청을 CPS 설계→에이전트 편성→구현→검증→수정 전체 사이클로 자동 실행
user-invocable: false
---

# Nova Orchestrator

자연어 한 줄을 받아서 설계→구현→검증→수정 전체 파이프라인을 자동 실행한다.

## 핵심 원칙

- 설계가 구현보다 먼저다 (CPS)
- Generator ≠ Evaluator (역할 분리)
- 구조화된 프롬프트가 자연어보다 낫다
- 멀티 프로젝트 병렬 지원

## 오케스트레이션 추적 (MCP 도구)

각 Phase 진행 상황을 MCP 도구로 추적한다. 세션 중단 시에도 `.nova-orchestration.json`에 상태가 보존된다.

| 시점 | MCP 도구 호출 |
|------|--------------|
| 오케스트레이션 시작 | `orchestration_start` — task, complexity, phases 등록 |
| Phase 시작 | `orchestration_update` — status: "running" |
| Phase 완료/실패 | `orchestration_update` — status: "completed"/"failed" + result |
| 상태 확인 | `orchestration_status` — 현재 진행 상황 조회 |

예시 (보통 복잡도):
```
orchestration_start({
  task: "사용자 프로필 페이지 구현",
  complexity: "medium",
  phases: [
    { name: "설계", role: "Architect" },
    { name: "구현", role: "Generator" },
    { name: "검증", role: "Evaluator" }
  ]
})
→ orch-abc123

orchestration_update({ orchestration_id: "orch-abc123", phase_name: "설계", status: "running" })
orchestration_update({ orchestration_id: "orch-abc123", phase_name: "설계", status: "completed", result: "CPS 설계서 작성 완료" })
orchestration_update({ orchestration_id: "orch-abc123", phase_name: "구현", status: "running" })
...
```

> MCP 도구가 사용 불가능한 환경에서는 추적 없이 기존 방식대로 실행한다.

## Execution

### Phase 1: 요청 분석

사용자 요청에서 다음을 추출한다:

- **프로젝트 경로**: 절대 경로 또는 현재 디렉토리 기준 상대 경로
- **작업 목표**: 무엇을 만들거나 변경하는가
- **복잡도**: 파일 수, 모듈 범위, 프로젝트 수로 판단
- **멀티 프로젝트 여부**: 2개 이상 프로젝트에 걸친 요청인지 판단

NOVA-STATE.md가 있으면 현재 스프린트 컨텍스트와 Phase를 참고한다.

6. **UI 변경 사전 감지** (선택적):
   bash scripts/detect-ui-change.sh --planning 호출 → likely_ui 결과 표시.
   "UI 변경 가능성: {Yes/No}" 1줄 출력 (사용자 인지 목적, 분기 결정 X).

#### 복잡도 판단 기준

| 복잡도 | 기준 | 에이전트 편성 |
|--------|------|-------------|
| 간단 | 1~2 파일, 단일 프로젝트 | Dev 1 → QA 1 |
| 보통 | 3~7 파일, 단일 프로젝트 | Architect 1 → Dev 1 → QA 1 |
| 복잡 | 8+ 파일 또는 멀티 프로젝트 | Architect N → Dev N → QA N → Fix N |

인증/DB/결제/보안 관련 변경은 파일 수와 무관하게 한 단계 상향한다.

### Phase 2: 설계 (Architect)

**간단 복잡도는 이 단계를 건너뛴다.**

Architect 에이전트를 spawn하여 CPS 설계를 수행한다.

Architect 에이전트 지시 원칙:
1. 프로젝트 코드를 직접 읽고 현재 상태를 파악한다
2. CPS(Context→Problem→Solution) 구조로 설계서를 작성한다
3. 설계 산출물에 다음을 포함한다:
   - 페이지/컴포넌트 구조
   - 디자인 토큰 (색상, 폰트, 간격 — 해당 시)
   - 데이터 흐름 및 API 경계
   - 기술 스택 및 구현 제약
   - 구현 순서 및 우선순위
   - 빌드/검증 명령

멀티 프로젝트면 각 프로젝트별 Architect를 병렬 실행한다 (`run_in_background: true`).

Architect 서브에이전트에 반드시 포함할 컨텍스트:

```
작업 디렉토리: {프로젝트_경로}
작업 목표: {사용자 요청}
역할: 구현하지 않는다. 설계서만 작성한다.
산출물: CPS 설계서 (Context/Problem/Solution + 구현 체크리스트)
```

### --design-only 종료점

`--design-only` 플래그가 있으면 Phase 2 완료 후 설계 결과를 사용자에게 보여주고 종료한다.
Phase 3 이후는 실행하지 않는다.

### 멀티 에이전트 조율 원칙

복잡(8+파일) 이상에서 병렬 에이전트 투입 시 다음을 적용한다:

#### 태스크 의존성 DAG

스프린트 내 태스크 간 선후 관계를 명시하여 병렬 실행을 최적화한다:
```
[독립] A: DB 스키마  ─┐
[독립] B: API 타입    ─┤── [의존] C: API 구현 ── [의존] D: 프론트엔드
[독립] E: 테스트 셋업 ─┘
```
- 의존 관계가 없는 태스크는 병렬 에이전트로 동시 실행한다
- 의존 태스크는 선행 태스크 완료 후 순차 실행한다

#### 파일 잠금 힌트

병렬 에이전트에게 "이 파일은 다른 에이전트가 수정 중"이라는 컨텍스트를 제공한다:
```
주의: 다음 파일은 다른 에이전트가 수정 중입니다. 읽기만 하세요:
- src/types.ts (Agent A가 수정 중)
- src/db/schema.ts (Agent B가 수정 중)
```

#### 전문 에이전트 > 범용 에이전트

3개의 전문화된 에이전트가 1개의 범용 에이전트보다 일관되게 더 나은 결과를 낸다.
에이전트 편성 시 역할별 전문 에이전트(architect, senior-dev, qa-engineer)를 투입한다.

### 구조화된 핸드오프 프로토콜

에이전트 간 전달 시 구조화된 아티팩트를 사용하여 컨텍스트 손실을 방지한다. (Anthropic 3-Agent Harness 패턴 적용)

| 전달 구간 | 아티팩트 형식 | 내용 |
|-----------|-------------|------|
| Architect → Generator | CPS 설계서 + 구현 체크리스트 | 기존 방식 유지 |
| Generator → Evaluator | **구조화된 변경 요약** | 변경 파일, 의도, 주요 결정 |
| Evaluator → Generator (Fix) | **구조화된 이슈 목록** | 파일:라인, 심각도, 수정 방향 |

#### Generator → Evaluator 핸드오프 포맷

Generator 완료 시 다음 정보를 Evaluator에게 전달한다:

```
## 변경 요약
- 변경 파일: {파일 목록}
- 변경 의도: {한줄 요약}
- 주요 결정: {트레이드오프 선택 이유}
- 알려진 제한: {미구현/의도적 생략 항목}
- self_verify: (선택 — Sprint 1부터 권장)
  - confident: {확신 영역 + 한줄 근거(테스트/로직 단순성 등)}
  - uncertain: {불확실 영역 + 사유(경계값/에러 처리/동시성/외부 의존)}
  - not_tested: {실행 검증 미수행 영역 + 사유}
```

> Evaluator는 코드 diff뿐 아니라 이 핸드오프 아티팩트를 참조하여, Generator의 의도와 실제 구현의 정합성을 검증한다.

**self_verify 필드 원칙** (Sprint 1부터):
- 선택 필드 — 없어도 기존 검증 동작 (하위호환).
- confident에는 **"왜 확신하는지" 한 줄 근거**를 반드시 포함. 근거 없는 확신은 자기 과신으로 간주.
- uncertain/not_tested가 **0건**이면 오히려 의심 시그널 — Generator에게 경계값·에러 처리·외부 의존을 다시 점검하도록 지시한다.
- 근거: *LLM Evaluators Recognize and Favor Their Own Generations* (arXiv 2404.13076) — self-preference bias는 구조적으로 방어 필요.
- Sprint 1에서는 **신호 수집만**. Layer 배분 최적화는 Sprint 2, 충돌 학습은 Sprint 3, Jury 참여는 Sprint 4.

**Orchestrator 수신 시 관측 (Sprint 1 채택률 측정)**:
- Generator 핸드오프 수신 직후 `self_verify` 필드 유무를 한 줄로 로그한다:
  ```
  [Handoff] self_verify: present  — confident={N}/uncertain={N}/not_tested={N}
  [Handoff] self_verify: absent   — Generator에게 필드 포함 재요청 (Sprint 1은 재요청만, 차단 X)
  ```
- `absent`인 경우 Evaluator 전달 전 Generator에게 **한 번 재요청**한다 (루프 금지 — 2회차도 absent면 그대로 진행).
- 이 관측 로그는 Sprint 2의 Layer 배분 최적화 근거 데이터로 활용된다.

**Evaluator 전달 시 메타 필드 (absent 구분)**:
재요청 시도 후에도 `self_verify`가 없으면 Evaluator에게 아래 메타 필드를 명시적으로 포함시킨다. Evaluator는 "원래 누락"과 "재요청도 실패한 누락"을 구분해 Sprint 1 관측 데이터 품질을 유지한다.
```
## self_verify_meta (Orchestrator가 Evaluator에게 전달)
- status: {present | absent_initial | absent_after_retry}
- retries: {0 | 1}
```
- `present`: Generator가 1차에 포함 → Evaluator는 필드 내용을 그대로 사용
- `absent_initial`: 1차 누락 (재요청 전). 보통 Orchestrator가 재요청하여 이 상태로는 Evaluator에 도달하지 않음
- `absent_after_retry`: 재요청도 실패. 채택률 통계에서 "강한 미채택 시그널"로 집계

#### Evaluator → Generator (Fix) 핸드오프 포맷

FAIL 판정 시 수정 지시를 구조화하여 전달한다:

```
## 수정 지시
[1] {파일:라인} — {심각도} — {이슈} → {수정 방향}
[2] ...
수정 범위: 위 항목에만 한정. 다른 코드 수정 금지.
```

### Phase 3: 프롬프트 변환

Architect의 설계서를 Dev 에이전트 프롬프트로 변환한다.
이 단계가 품질의 핵심이다 — 설계서의 구체적 정보가 구현 지침으로 주입된다.

Dev 프롬프트에 반드시 포함할 항목:

| 항목 | 출처 |
|------|------|
| 프로젝트 경로 (절대 경로) | 요청 분석 |
| 기술 스택 | Architect 설계서 |
| 파일/컴포넌트 구조 | Architect 설계서 |
| 디자인 토큰 | Architect 설계서 |
| 데이터 흐름 | Architect 설계서 |
| 구현 순서 | Architect 설계서 |
| 빌드 검증 명령 | Architect 설계서 |
| "구현만 해, 검증은 별도" 명시 | 항상 포함 |

간단 복잡도는 Architect 없이 사용자 요청에서 직접 Dev 프롬프트를 생성한다.

### Phase 4: 구현 (Generator)

Dev 에이전트를 spawn한다 (`senior-dev` 타입).

- `run_in_background: true`로 비동기 실행
- 멀티 프로젝트면 프로젝트별 Dev를 병렬 실행 (각 프로젝트 독립)
- Dev에게 "구현만 하라, 검증은 별도 수행한다"를 명시

모든 Dev 에이전트 완료 대기 후 구현 결과를 수집한다.

#### Checkpoint: Generate 완료

구현 결과 요약을 사용자에게 보고한다:
- 변경된 파일 목록
- 주요 변경 내용 요약 (3줄 이내)

`--skip-qa` 플래그가 있으면 Phase 5~6을 건너뛰고 Phase 7로 이동한다.

### Phase 5: 검증 (Evaluator)

QA 에이전트를 spawn한다 (`qa-engineer` 타입).

QA 프롬프트에 반드시 포함할 항목:
- 검증 대상 파일 목록
- 설계서 기반 검증 기준 (있는 경우)
- 빌드/테스트 명령

`--strict` 플래그가 있으면 Full 검증(Layer 1~3)을 강제한다.
기본은 Standard 검증이다.

멀티 프로젝트면 프로젝트별 QA를 병렬 실행한다.

#### 검증 항목

| 항목 | 기본 | --strict |
|------|------|---------|
| 빌드 성공 | 필수 | 필수 |
| TypeScript 타입 에러 | 필수 | 필수 |
| 파일 구조 (설계서 대조) | 필수 | 필수 |
| 실제 동작 (curl/playwright) | 생략 | 필수 |
| 경계값 시나리오 | 생략 | 필수 |

### Phase 5.5: UI 변경 감지 + ux-audit Lite (자동)

Phase 5가 PASS면 다음을 수행한다:

1. `result = bash scripts/detect-ui-change.sh --post-impl`

2. `result.is_ui == false` → 즉시 Phase 7으로 (메트릭 기록 없음)

3. `result.cache_hit == true`:
   - "[Nova] 이전 감사와 동일한 변경 — ux-audit Lite 생략" 1줄 출력
   - `bash scripts/log-metric.sh --event ui_audit_triggered --cache_hit 1`
   - Phase 7으로

4. `--no-ux-audit` 플래그 OR (`nova-config.json` 존재 AND `.auto.uiAudit == false`):
   - `bash scripts/log-metric.sh --event ui_audit_opt_out --reason flag` (또는 `--reason config`)
   - Phase 7으로

5. 사전 고지:
   - `.nova/ui-state.json` 미존재 또는 `.first_ui_audit_shown == false`:
     다음 자세한 안내 출력 (첫 트리거 템플릿):
     ```
     [Nova] UI 변경이 감지되었습니다. ux-audit Lite(3인 평가자)를 자동 실행합니다.
     - 평가자: Newcomer · Accessibility · Cognitive Load
     - 대상 파일: {result.files}
     - 이 자동화를 끄려면: --no-ux-audit 플래그 또는 nova-config.json { "auto": { "uiAudit": false } }
     ```
     `.nova/ui-state.json` 갱신: `first_ui_audit_shown = true`
   - 그 외: "[Nova] UI 변경 감지 → ux-audit Lite 병행" 1줄 출력

6. **ux-audit Lite 실행** (Newcomer + Accessibility + Cognitive Load 3인, 5인 Full 아님):
   - `target = result.files`
   - ux-audit 스킬을 Lite 모드로 호출

7. 완료 후 메트릭 기록 및 캐시 갱신:
   ```
   bash scripts/log-metric.sh --event ui_audit_completed \
     --critical N --high N --medium N --low N
   ```
   `.nova/last-audit.json` 갱신: `hash, ts, result, files, stats`

8. `result.critical >= 1` AND (`nova-config.json` 미존재 OR `.auto.uiAuditBlockOnCritical != false`):
   - 커밋 차단 + 사용자에게 Critical 목록 보고
   - 옵션 제시: 재시도 / `--no-ux-audit` / 수동 fix
9. 그 외: Phase 7으로 (보고에 audit 결과 통합)

### Phase 6: 수정 (Auto-Fix)

QA 결과에서 FAIL/Critical/HIGH 이슈를 추출한다.

이슈가 없으면 이 단계를 건너뛴다.

Fix 에이전트를 spawn한다 (`senior-dev` 타입):
- 수정 범위를 QA가 지적한 항목에만 한정한다 — 다른 코드는 건드리지 않는다
- 새 서브에이전트를 spawn한다 (이전 Dev 컨텍스트 오염 방지)
- 수정 완료 후 빌드를 확인한다

Fix 완료 후 Phase 5(검증)를 재실행한다. 재시도는 최대 1회.
2번째 FAIL 시 즉시 중단하고 사용자에게 에스컬레이션한다.

Fix 에이전트에 반드시 포함할 컨텍스트:

```
작업 디렉토리: {프로젝트_경로}
수정 대상: QA가 지적한 {N}건
[1] {파일:라인} — {이슈 설명} → {수정 방향}
[2] ...
주의: 지적된 항목 외 다른 코드는 수정하지 않는다.
```

### Phase 7: 결과 보고

전체 프로세스 결과를 요약하여 보고한다.

```
━━━ Nova Orchestrator — 완료 ━━━━━━━━━━━━━━━━━
  요청: {원본 요청}
  투입 에이전트: Architect {N} / Dev {N} / QA {N} / Fix {N}

  ## 프로젝트별 결과
  | 프로젝트 | Dev | QA | 판정 |
  |----------|-----|-----|------|
  | {경로} | 완료 | PASS | ✓ |

  ## 수정 필요 항목
  (CONDITIONAL 또는 FAIL 시 목록)

  ## 다음 단계
  - {배포 가능 / 수동 확인 필요 항목}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**에이전트 상태 추적**: Claude Code의 `TeammateIdle`/`TaskCompleted` 훅 이벤트가 가용하면, 에이전트 완료를 자동 감지하여 다음 의존 태스크를 트리거한다. 가용하지 않으면 폴링으로 대기한다.

**CRITICAL: 결과 보고 직후, 반드시 NOVA-STATE.md를 갱신한다. 이 단계를 건너뛰지 마라.**

NOVA-STATE.md가 있으면 Last Activity를 갱신한다:
```
- /nova:auto → {PASS/FAIL} — {프로젝트명} | {ISO 8601 타임스탬프}
- /nova:auto → UI 감지 → ux-audit Lite PASS — Critical N / High N / Medium N / Low N | {ISO 8601 타임스탬프}
```

## 플래그

| 플래그 | 동작 |
|--------|------|
| (없음) | 전체 사이클 (설계→구현→검증→수정) |
| `--design-only` | 설계까지만 (구현 전 확인용) |
| `--skip-qa` | QA 생략 (빠른 프로토타이핑) |
| `--strict` | QA를 Full 검증으로 강제 |

## Input

$ARGUMENTS
