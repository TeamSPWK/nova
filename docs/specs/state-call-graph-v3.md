# [Spec] STATE Call Graph (v3) — 16 파일 갱신 매핑 + Worktree 정책

> Sprint 0 gating spec — Sprint 1 schema 동결 + Sprint 2 진입점 통합 전 필수
> 작성일: 2026-05-15
> 출처: Plan Critic Unknown #1·#4, Design Critic #19, Sprint 0 subagent 조사
> 관련: `work-item-scope-v3.md`, `registry-write-authority-v3.md`

---

## 1. 결정 (요약)

| # | 결정 | 근거 |
|---|------|------|
| 1 | **NOVA-STATE.md 갱신 권한 = 9 진입점 + orchestrator + 메인 사용자만** | sub-agent 직접 갱신 X (현재 Nova 패턴) |
| 2 | **registry-write.sh 호출 위치 = 16 파일 매트릭스 각 행의 "갱신 패턴" 열** | Sprint 2 통합 시 `registry-write.sh` 호출로 *치환* |
| 3 | **`.nova/work-items/` worktree 공유 여부 = 분리 (Case B)** | 현재 `.nova/events.jsonl` 분리 패턴 + session.id 격리와 일관 |
| 4 | **`NOVA-STATE.md` worktree 공유 여부 = 공유 (main 레포만)** | context-chain SKILL이 단일 STATE 가정 |
| 5 | **evolve_decision 권한 = registry-write 호출 금지 (JSONL only 유지)** | v5.20.0 의도된 분리, 다중 호출 트림 루프 회피 |

---

## 2. 16 파일 STATE 갱신 매트릭스

### 2.1 9 진입점 (commands)

| # | 파일 | 갱신 트리거 | 갱신 영역 | 현재 패턴 | v3 work-item 전이 | v3 registry-write 호출 |
|---|------|------------|----------|----------|------------------|----------------------|
| 1 | `commands/plan.md` | `/nova:plan` 완료 직후 | Current(Goal/Phase), Refs, Last Activity | 마크다운 지시 (메인 에이전트 Edit) | proposed → active (phase:planning) | `registry-write.sh create <title> --source-doc=docs/plans/<slug>.md` |
| 2 | `commands/design.md` | `/nova:design` 완료 직후 | Current(Phase), Refs, Last Activity | 마크다운 지시 | active 유지 (phase:building) | `registry-write.sh update <wi> source_docs+=docs/designs/<slug>.md` |
| 3 | `commands/deepplan.md` | `/nova:deepplan` 완료 직후 | Current(Phase), Refs, Last Activity | 마크다운 지시 + plan_created 이벤트 | proposed → active (phase:planning) | `registry-write.sh create <title> --source-doc=docs/plans/<slug>.md` |
| 4 | `commands/run.md` | `/nova:run` 검증 완료 후 | Recently Done, Phase, Tasks, Last Activity | 마크다운 지시 + sprint_started/completed/blocker 이벤트 | PASS → done / FAIL → active 유지 / blocked | `registry-write.sh evaluator-pass <wi> --commit-sha=SHA` (PASS) OR `transition <wi> blocked --blocked-reason=...` |
| 5 | `commands/auto.md` | `/nova:auto` 사이클 완료 후 (orchestrator 위임) | Recently Done, Last Activity (orchestrator가 수행) | orchestrator skill이 위임 | PASS → done / FAIL → active | orchestrator가 `evaluator-pass` 또는 `transition` 호출 |
| 6 | `commands/review.md` | `/nova:review` 완료 직후 | Refs(Last Verification), Last Activity, Known Risks | 마크다운 지시 + evaluator_verdict | review_required=true | `registry-write.sh require-review <wi>` |
| 7 | `commands/check.md` | `/nova:check` 완료 직후 | Refs(Last Verification), Last Activity, Known Gaps | 마크다운 지시 (evaluator_verdict는 내부 evaluator 호출 시) | review_required=true (Critical 시) | `registry-write.sh require-review <wi>` (Critical 발견 시) |
| 8 | `commands/ux-audit.md` | `/nova:ux-audit` 완료 직후 | Last Activity, Known Risks (Critical 발견 시) | 마크다운 지시 + log-metric.sh | review_required=true (Critical 시) | `registry-write.sh require-review <wi>` |
| 9 | `commands/evolve.md` | `/nova:evolve --scan/--apply` 완료 후 | Last Activity (오직) | 마크다운 지시 + evolve_decision 이벤트 (JSONL only) | **work-item 전이 X — registry 직교** | **호출 안 함** (evolve_decision은 JSONL only) |

### 2.2 6 skills + audit-self (10~16)

| # | 파일 | 갱신 트리거 | 갱신 영역 | 현재 패턴 | v3 영향 |
|---|------|------------|----------|----------|----------|
| 10 | `skills/context-chain/SKILL.md` | 9 진입점 STATE 갱신 후 호출 | 전체 (Current/Tasks/Recently Done/Last Activity) | 50줄 트림 + 동시 기록 원칙 명시 | **v3 갱신 필요**: marker 영역 카운트 제외 + work-item 인덱스 참조 동시 기록 |
| 11 | `skills/deepplan/SKILL.md` | Phase E 저장 후 STATE 갱신 | Current(Phase:planning), Refs, Last Activity | deepplan 내부 SKILL이 Edit 수행 | `registry-write.sh create` 호출 추가 (Phase E) |
| 12 | `skills/evaluator/SKILL.md` | 판정 직후 evaluator_verdict 이벤트만 | **STATE 직접 갱신 안 함** | sub-agent → 이벤트만, STATE는 호출처 | v3에서도 유지 — `registry-write.sh` 호출 절대 X (sub-agent 정책) |
| 13 | `skills/orchestrator/SKILL.md` | Phase 7 결과 보고 후 | Recently Done, Last Activity | orchestrator Phase 7 직접 갱신 | `registry-write.sh evaluator-pass` (PASS 시) OR `transition` 호출 추가 |
| 14 | `skills/strategic-compact/SKILL.md` | (STATE 갱신 트리거 아님) | — | 세션-수준 압축 판단만 | **v3 영향 없음** (세션 압축 ≠ 상태 갱신) |
| 15 | `skills/ux-audit/SKILL.md` | 종합 보고서 출력 직후 | Last Activity, Known Risks | ux-audit Phase 4 + log-metric.sh | sub-agent라 STATE 직접 갱신 X — commands/ux-audit.md가 require-review 호출 |
| 16 | `commands/audit-self.md` | Phase 5 결과 정리 후 | Last Activity, Known Risks (Critical 시) | audit-self 커맨드 내부 + audit_self_verdict 이벤트 | `registry-write.sh require-review` (Critical 발견 시) |

### 핵심 통찰

1. **STATE 갱신은 9 진입점 + orchestrator + audit-self만**: 11개 파일이 *실질적 STATE 갱신*. 5개(strategic-compact, evaluator, ux-audit skill, deepplan skill 일부, context-chain)는 *지시·이벤트 기록·구조 정의만*.
2. **evolve는 work-item과 직교**: `evolve_decision`이 JSONL only로 의도된 분리. v3에서도 `commands/evolve.md`는 `registry-write.sh` 호출 안 함 — Nova 메타-진화는 work-item과 별도 lifecycle.
3. **sub-agent는 절대 STATE 갱신 안 함**: evaluator·ux-audit skill 등 sub-agent로 spawn되는 모든 skill은 *이벤트 기록*만. STATE 갱신은 호출처(9 진입점) 또는 메인 책임.

---

## 3. v3 통합 시 변경 매트릭스 (Sprint 2 작업)

각 파일에서 *제거*해야 할 마크다운 지시와 *추가*해야 할 `registry-write.sh` 호출:

| 파일 | Sprint 2 작업 | 검증 명령 (Sprint 2 Done 조건 매핑) |
|------|-------------|--------------------------------|
| `commands/plan.md` | 기존 "NOVA-STATE.md를 Edit으로 갱신" 지시 제거 → `registry-write.sh create` 호출 단계로 교체 | `grep -A5 "## 갱신" commands/plan.md \| grep -q "registry-write.sh create"` |
| `commands/design.md` | 동일 패턴 → `registry-write.sh update` 호출로 변경 | `grep -q "registry-write.sh update" commands/design.md` |
| `commands/deepplan.md` | Phase E의 NOVA-STATE.md 갱신 + plan_created 이벤트 → `registry-write.sh create` 추가 | `grep -q "registry-write.sh create" commands/deepplan.md` |
| `commands/run.md` | Phase 6 State Update의 마크다운 지시 → `evaluator-pass` 또는 `transition blocked` 호출 | `grep -qE "evaluator-pass\|transition blocked" commands/run.md` |
| `commands/auto.md` | orchestrator 스킬이 처리 (auto.md 자체는 위임만) | (orchestrator 검증으로 대체) |
| `commands/review.md` | "Last Verification + Known Risks 추가" 지시 → `require-review` 호출 | `grep -q "require-review" commands/review.md` |
| `commands/check.md` | "Last Verification + Known Gaps 테이블 관리" → `require-review` (Critical 시) | `grep -q "require-review" commands/check.md` |
| `commands/ux-audit.md` | "Critical 발견 시 Known Risks 추가" → `require-review` | `grep -q "require-review" commands/ux-audit.md` |
| `commands/evolve.md` | **변경 안 함** — JSONL only 유지 | `! grep -q "registry-write.sh" commands/evolve.md` |
| `skills/context-chain/SKILL.md` | 50줄 트림 룰을 marker 영역 카운트 제외로 갱신 | `grep -qE "marker.*제외\|registry-rendered.*카운트" skills/context-chain/SKILL.md` |
| `skills/deepplan/SKILL.md` | Phase E에 `registry-write.sh create` 추가 | `grep -q "registry-write.sh create" skills/deepplan/SKILL.md` |
| `skills/evaluator/SKILL.md` | **변경 안 함** — sub-agent 정책 유지 (이벤트만) | `! grep -q "registry-write.sh" skills/evaluator/SKILL.md` |
| `skills/orchestrator/SKILL.md` | Phase 7에서 `evaluator-pass` 또는 `transition` 호출 추가 | `grep -qE "registry-write.sh.*(evaluator-pass\|transition)" skills/orchestrator/SKILL.md` |
| `skills/strategic-compact/SKILL.md` | **변경 안 함** | (변경 없음 확인) |
| `skills/ux-audit/SKILL.md` | **변경 안 함** — commands/ux-audit.md가 require-review 호출 | `! grep -q "registry-write.sh" skills/ux-audit/SKILL.md` |
| `commands/audit-self.md` | Phase 5에서 `require-review` 호출 (Critical 시) | `grep -q "require-review" commands/audit-self.md` |

**Sprint 2 grep 검증 명령 (Critic #6 거짓양성 회피)**:
```bash
# 직접 쓰기 코드 부재 (마크다운 텍스트 *언급*은 허용)
grep -rE "(\bcat[[:space:]]+>[[:space:]]*NOVA-STATE|\becho[[:space:]]+.*>[[:space:]]*NOVA-STATE|\bsed[[:space:]]+-i.*NOVA-STATE|\bappend.*NOVA-STATE)" commands/*.md skills/*/SKILL.md
# 위 명령 출력이 빈 줄이면 통과 (현재 0건)
```

---

## 4. Worktree 정책

### 4.1 결정: `.nova/work-items/` 분리 (Case B)

**근거 3가지**:

1. **`.nova/events.jsonl` 이미 분리 패턴**: `record-event.sh`의 `SESSION_ID_FILE = ${EVENTS_DIR}/session.id`는 worktree별 독립 session id 생성. 이벤트 로그가 격리되도록 의도 설계됨. work-items도 같은 디렉토리(`.nova/`)에 있으니 일관성.
2. **`hooks/worktree-setup.sh` 심볼릭 링크 대상 명시**: 현재 worktree-setup이 심볼릭 링크하는 것은 `.env`·`.env.local`·`.npmrc`·`.secret/` 등. `.nova/`는 명시적 제외. nova 자체가 worktree별 격리를 의도.
3. **NOVA-STATE.md만 main 레포 공유**: context-chain SKILL이 단일 STATE 가정. `.nova/`가 분리되어도 NOVA-STATE.md는 main만 진실원. 자동 렌더는 main의 STATE만 갱신.

### 4.2 동시 갱신 정책

| 시나리오 | 결과 |
|---------|------|
| main + worktree A 모두 `/nova:plan` 동시 실행 | 각 자기 `.nova/work-items/`에 독립 WI 생성. id 충돌 가능 (둘 다 WI-0042) |
| 머지 시 충돌 해소 | git이 `.nova/work-items/index.json` conflict 감지 → 사용자 수동 머지 + `bash scripts/reindex-work-items.sh` 실행 권고 |
| 동일 WI id가 두 worktree에 다른 내용 | drift H2 (id 유일성) 발화 — 사용자가 어느 쪽 채택할지 선택 후 reindex |

### 4.3 Design § 관통 검증 #7 확정

Design의 "Sprint 0 결정에 따라" 조건부 표현 → **Case B (분리) 확정**.

관통 검증 #7 정정:
> 다중 git worktree에서 두 세션이 동시에 `/nova:plan`: 각 worktree의 `.nova/work-items/`에 독립적으로 WI 발급 (예: main에 WI-0042, worktree에 WI-0042). 머지 시 git이 충돌 감지 → 사용자가 reindex 실행. *단일 lock으로 race 차단은 의도 안 함* — 분리가 격리의 핵심.

### 4.4 `.pending-transition` 마커 dead-spot (Architect #3)

worktree 분리 환경에서 `.pending-transition-$wi` 마커도 worktree별로 격리된다:

- worktree A에서 `evaluator-pass` 도중 SIGKILL → A의 `.nova/work-items/.pending-transition-WI-0042` 잔류
- main worktree의 `/nova:check` 실행 시 **A의 마커를 볼 수 없음** — H8(부분 전이 잔류)가 main 범위만 검출
- **사후 감지 경로**: A를 main에 머지하면 `.pending-transition-*` 파일이 main에 추가됨 → 다음 `/nova:check` 또는 세션 시작 시 `recover_pending_transitions` 호출 → H8 발화

**규약**:
- H8은 *현재 worktree* 범위만 검출 — cross-worktree pending은 *머지 후 발견*
- worktree A 사용자는 SIGKILL 후 같은 worktree에서 다시 작업하면 즉시 발견. main 사용자는 머지 후 발견
- 머지 PR에 `.pending-transition-*` 파일이 포함되면 PR 리뷰어가 발견하도록 git diff에서 명시

---

## 5. orchestrator + auto-mode 흐름 (registry-write 호출 시퀀스)

### 5.1 `/nova:run` Generator-Evaluator 사이클

```
사용자 → /nova:run
   ├── 1. Generator subagent spawn (senior-dev)
   │      └── 작업 수행 (Edit/Write/Bash) → 결과 stdout 출력
   ├── 2. 메인이 결과 수령 → `registry-write.sh transition <wi> active` (이미 active면 skip)
   ├── 3. Evaluator subagent spawn (qa-engineer / evaluator skill)
   │      └── PASS/FAIL 판정 stdout + evaluator_verdict 이벤트 기록
   ├── 4. 메인이 판정 수령
   │      ├── PASS → `registry-write.sh evaluator-pass <wi> --commit-sha=...`
   │      └── FAIL → `registry-write.sh require-review <wi>` + Refiner subagent spawn
   └── 5. 메인이 NOVA-STATE.md 자동 렌더 트리거 (registry-write 내부에서 자동)
```

### 5.2 `/nova:auto` orchestrator 흐름 (Phase 7 SIGINT 안전, Architect #4)

```
사용자 → /nova:auto
   ├── orchestrator skill Phase 1~6 수행
   │      ├── Generator subagent spawn (senior-dev 등)
   │      └── Evaluator subagent spawn (qa-engineer / evaluator skill)
   │          └── evaluator_verdict 이벤트 기록 (sub-agent도 record-event 가능)
   └── orchestrator Phase 7 (메인 컨텍스트로 복귀)
          ├── **Step 7-0 (필수)**: `.pending-transition-$wi` 마커 생성 (의도 전이 기록)
          │   touch ".nova/work-items/.pending-transition-$wi"
          │   echo "{wi:$wi, target:done|blocked|...}" > ".nova/work-items/.pending-transition-$wi"
          ├── Step 7-1: PASS → `registry-write.sh evaluator-pass <wi> --commit-sha=...`
          ├── Step 7-1': FAIL → `registry-write.sh require-review <wi>`
          ├── Step 7-1'': 블로커 → `registry-write.sh transition <wi> blocked --blocked-reason=...`
          └── **Step 7-2 (필수, 마커 제거)**: registry-write가 성공적으로 끝났을 때만
              rm -f ".nova/work-items/.pending-transition-$wi"
```

**SIGINT 시 안전성**:
- Step 7-0과 Step 7-1 사이 SIGINT → 마커 잔류, WI 미갱신, evaluator_verdict는 이벤트로 남음
- 다음 세션 시작 시 `recover_pending_transitions` (또는 `/nova:check`)가 마커 발견 → H8 발화
- 사용자가 evaluator_verdict 이벤트 + 마커를 보고 수동 복구 결정 가능

**핵심**: orchestrator Phase 7은 *메인 컨텍스트* — sub-agent가 아님. 따라서 `registry-write.sh` 호출 권한 있음. **Step 7-0 마커 생성은 SIGINT 이후 복구의 유일한 단서** — 빠뜨리면 evaluator_verdict ↔ WI 상태 불일치가 영구 dead-spot.

---

## 6. evolve_decision 권한 (예외 처리)

`commands/evolve.md`는 `registry-write.sh`를 호출하지 않음 — v5.20.0 의도된 분리 유지.

이유:
- evolve는 Nova *메타-진화* (룰/스킬/훅 변경 제안)
- work-item은 *프로젝트 작업* (코드 변경)
- 두 lifecycle이 직교 — evolve 결정을 work-item으로 추적하면 사용자가 메타-작업과 프로젝트 작업이 섞여 혼란

**v3에서도 유지**: evolve_decision은 `.nova/events.jsonl`에만 append. NOVA-STATE.md 갱신 트리거 X. work-item registry 영향 X.

---

## 7. 검증

```bash
test -f docs/specs/state-call-graph-v3.md
# 16 파일 모두 매트릭스에 등장
for f in commands/plan.md commands/design.md commands/deepplan.md commands/run.md commands/auto.md commands/review.md commands/check.md commands/ux-audit.md commands/evolve.md skills/context-chain/SKILL.md skills/deepplan/SKILL.md skills/evaluator/SKILL.md skills/orchestrator/SKILL.md skills/strategic-compact/SKILL.md skills/ux-audit/SKILL.md commands/audit-self.md; do
  grep -q "\`$f\`" docs/specs/state-call-graph-v3.md || echo "MISSING: $f"
done
# worktree 결정 명시
grep -qE "분리.*Case B\|`.nova/work-items/` worktree.*분리" docs/specs/state-call-graph-v3.md
# evolve 권한 분리 명시
grep -qE "evolve.*JSONL only\|evolve_decision.*registry-write 호출 금지" docs/specs/state-call-graph-v3.md
```

Sprint 0 Done 조건 매핑:
- `Sprint 0 Done #2`: state-call-graph-v3.md 존재 + 16 파일 매핑 (`grep -cE "commands/|skills/" ≥ 16`)
- `Sprint 0 Done #4`: 다중 worktree `.nova/` 공유 여부 결정 (Case B 분리 명시)
