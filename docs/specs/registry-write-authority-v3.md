# [Spec] Registry-Write 권한 경계 (v3)

> Sprint 0 gating spec — Sprint 1 schema 동결 전 필수
> 작성일: 2026-05-15
> 출처: Plan Critic Unknown #2, Design Critic 종합평가 §사용자 커뮤니케이션
> 관련: `work-item-scope-v3.md`, `state-call-graph-v3.md`

---

## 1. 결정 (요약 매트릭스)

**누가 `registry-write.sh`를 호출할 권한을 가지는가?**

| 주체 | registry-write 권한 | 호출 가능 명령 | 비고 |
|------|-------------------|---------------|------|
| **사용자 (메인 세션)** | O | 모두 | 직접 호출은 일반적이지 않음 — 9 진입점 경유 권장 |
| **9 진입점 (commands/*.md)** | O | 진입점별 제한 (§ 3 매트릭스) | 단일 쓰기 경로 — 핵심 |
| **orchestrator skill** | O (단, sub-agent 경유 명령만) | `create`·`require-review`·`transition`(active→blocked) | `evaluator-pass`·`transition done` 직접 호출 금지 |
| **Generator sub-agent** (senior-dev 등) | X (read만) | — | propose만, 직접 쓰기 금지 |
| **Evaluator sub-agent** (qa-engineer·evaluator skill) | **X** (Sprint 0 조사 결과 일관성 수정) | — | PASS/FAIL 판정 + `review_required` 권고를 *출력*만. `record-event.sh evaluator_verdict` 호출은 OK (이벤트는 sub-agent도 기록 가능). require-review 실제 호출은 메인/호출처 (`/review`·`/check`·`/ux-audit`) 책임 |
| **Refiner sub-agent** | X | — | 코드 변경 제안만, registry 쓰기 X |
| **Codex 위임 (codex skill)** | X | — | propose JSON 출력만. 메인이 받아 registry-write 호출 |
| **Architect sub-agent** | X | — | 설계 분석만 |
| **/nova:auto orchestrator (auto-mode)** | O (제한적) | `create`·`require-review`·`transition`(블로커) | `evaluator-pass`는 별도 evaluator subagent 결과 받아 *메인*이 호출 |

---

## 2. 핵심 원칙

### 원칙 1: 단일 쓰기 경로 절대 우선

모든 `registry-write.sh` 호출은 **9 진입점 또는 orchestrator skill을 거쳐야 한다**. Sub-agent가 직접 호출하면 다음 위험:

- Sub-agent 컨텍스트는 메인과 분리 — 갱신 사실을 메인이 모름 → STATE 렌더 동기화 실패
- 다중 sub-agent 동시 호출 → 채번 race 비정상 빈도
- Evaluator가 자기 평가 결과를 직접 done 처리 = Generator ≠ Evaluator 원칙 위반

### 원칙 2: Evaluator는 *판정 출력*만 (sub-agent STATE 갱신 절대 금지)

Sprint 0 조사 결과 (`docs/specs/state-call-graph-v3.md`)에 따르면 현재 Nova 패턴은 **sub-agent가 STATE 직접 갱신 X**. v3에서도 일관 유지:

- Evaluator skill (또는 `nova:qa-engineer` sub-agent)은 plan/design/code 검증 후 **PASS/FAIL + `review_required` 권고를 stdout으로만** 출력
- `record-event.sh evaluator_verdict` 이벤트 기록은 OK (이벤트는 sub-agent도 기록 가능 — Nova 현재 패턴)
- `registry-write.sh` 호출은 절대 X — 메인 또는 호출처 (`/review`·`/check`·`/ux-audit`) 가 결과 받아 `require-review` 호출

이유: Generator ≠ Evaluator 원칙 + 단일 쓰기 경로 절대 우선. Evaluator가 직접 갱신하면 메인이 모르는 변경이 생김.

### 원칙 3: Codex 위임은 propose-only

Codex (`codex` skill via `codex:codex-rescue` subagent)가 작업을 위임 받았을 때 work-item 갱신 권한 X. Codex 결과(JSON 출력)를 받은 **메인**이 적절히 `registry-write.sh` 호출.

이유: Codex는 외부 runtime — 메인 세션의 lock·state 컨텍스트를 모름.

### 원칙 4: Auto-mode orchestrator는 *조정자*, *전이자* 분리

`/nova:auto` orchestrator는 다음 흐름:
1. Generator subagent spawn → 작업 수행
2. Evaluator subagent spawn → PASS/FAIL 판정 출력
3. **메인 orchestrator가 판정 받아** `registry-write.sh evaluator-pass` 호출 (Evaluator subagent가 직접 호출 X)

이렇게 하면 Generator ≠ Evaluator 원칙 + 단일 쓰기 경로 둘 다 만족.

---

## 3. 명령별 권한 매트릭스

| 명령 | 사용자 | 9 진입점 | orchestrator | Generator | Evaluator | Codex | Auto-mode |
|------|--------|---------|-------------|-----------|-----------|-------|-----------|
| `create` | O | O | O | X | X | X | O (메인) |
| `transition active` | O | `/plan`·`/design`·`/run` | O | X | X | X | O |
| `transition blocked` | O | `/run`(블로커 발견)·`/check`·`/review` | O | X | X | X | O |
| `transition done` | O | `/run` 후 사용자 확인 | X (메인 경유) | X | X | X | O (메인) |
| `transition superseded` | O | `/plan`·`/design` | O | X | X | X | O |
| `update` | O | 진입점별 (특정 필드만) | O | X | X | X | O |
| `evaluator-pass` | O | **`/run`·`/auto` only** | X (메인 경유) | X | X | X | O (메인) |
| `require-review` | O | `/review`·`/check`·`/ux-audit` | O | X | **X** (sub-agent는 권고만) | X | O |

**진입점별 제한 사유**:
- `evaluator-pass`는 PASS 판정 결과를 evidence와 함께 기록 — Evaluator 결과를 직접 받는 진입점만 (즉 /run·/auto)
- `transition blocked`는 작업 도중 블로커 발견을 기록 — /run·/check·/review가 자연스러움
- `require-review`는 검증 요청 — review/check/ux-audit가 자연스러움

---

## 4. 위반 시 처리

### 사용자가 직접 `.nova/work-items/WI-XXXX.json` 편집

- drift W8 (신규 Warn): "사용자 손편집 감지 — registry-write 경유 권고"
- 단, schema 위반이면 H1 (Hard) 발화 — 편집 자체는 차단 안 하지만 invalid state → /nova:check 실패

### Sub-agent가 직접 `registry-write.sh` 호출 (정책 위반)

- 기술적으로 막을 방법 없음 (bash는 권한 분리 X)
- **검출**: `record-event.sh`에 호출자 정보(`actor` 필드) 기록. orchestrator·9 진입점 외 actor면 stderr 경고.
- **대응**: Sprint 4 drift 룰 W9 (신규 Warn): "비표준 actor가 registry-write 호출 — sub-agent 정책 위반 의심"

### 사용자가 사용자임에도 의도 외 호출

- 사용자는 `registry-write.sh`를 직접 호출 *허용*. 다만 9 진입점 경유가 자동화·검증·이벤트 기록을 같이 해주므로 권장.

---

## 5. 권한 경계 명시 코드 (Sprint 1·2 구현)

### record-event.sh `actor` 필드 (Sprint 2)

```bash
# work_item_transitioned 이벤트에 actor 필드 추가
{
  "event_type": "work_item_transitioned",
  "schema_version": "3.0",
  "actor": "command:/nova:run",   # 또는 "skill:orchestrator", "user:direct"
  "wi_id": "WI-0042-...",
  "from": "active", "to": "done",
  "trigger": "evaluator_pass"
}
```

### actor 추론 규칙

- `$NOVA_CALLER` 환경변수 (9 진입점·skill 호출 시 set) → `command:/nova:run` 등
- 환경변수 미설정 + 부모 PID가 bash interactive → `user:direct`
- 환경변수 미설정 + 부모 PID가 subagent process → `subagent:unknown` (W9 발화 후보)

---

## 6. Sub-agent에 대한 명시 가이드

### evaluator SKILL이 spawn된 sub-agent

```
당신은 evaluator입니다. 다음 규칙 준수 필수:
1. Plan/code 검증 후 PASS/FAIL을 *출력*하라 — 직접 registry-write.sh 호출 금지
2. `require-review` 명령은 메인에 권고만 — 직접 호출은 메인/호출처 책임
3. `record-event.sh evaluator_verdict` 이벤트 기록은 OK (sub-agent도 가능, Nova 현재 패턴 유지)
4. 위반 시 자기 평가 결과가 무효 (Generator ≠ Evaluator 원칙 + 단일 쓰기 경로)
```

### codex SKILL이 위임 받은 외부 runtime

```
당신은 Codex입니다. 코딩 작업을 위임받았습니다:
1. 작업 결과를 JSON 출력 (`{"status":"complete","commit_sha":"...","files":[...]}`)
2. registry-write.sh 호출 금지 — 메인이 받아서 처리
3. 메인이 `evaluator-pass` 또는 `transition done`을 호출할지 결정
```

---

## 7. 검증

```bash
test -f docs/specs/registry-write-authority-v3.md
grep -qE "권한 경계" docs/specs/registry-write-authority-v3.md
grep -qE "evaluator.*require-review.*only\|Evaluator는.*require-review" docs/specs/registry-write-authority-v3.md
grep -qE "Codex.*propose-only\|Codex.*propose only\|Codex 위임은 propose-only" docs/specs/registry-write-authority-v3.md
```

Sprint 0 Done 조건 매핑: `Sprint 0 Done #3` (registry-write-authority-v3.md 존재 + 권한 경계 명시).
