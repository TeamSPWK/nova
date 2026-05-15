# [Spec] Work-Item 스코프 정의 (v3)

> Sprint 0 gating spec — Sprint 1 schema 동결 전 필수
> 작성일: 2026-05-15
> 출처: Plan Critic Unknown #3 (`/docs/plans/work-item-registry-v3.md`), Design Critic #19
> 관련: `state-call-graph-v3.md`, `registry-write-authority-v3.md`

---

## 1. 결정 (요약)

| # | 결정 | 근거 |
|---|------|------|
| 1 | **WI는 단일 sprint에 속한다** | 다중 sprint span은 status 전이 + Evaluator 게이트와 충돌 |
| 2 | **WI 간 의존은 `depends_on` 필드로 표현** (cross-sprint 가능) | 단일 sprint 강제와 별개로 작업 의존성은 자유 |
| 3 | **1 변경 = 1 WI 원칙** — 한 commit/변경이 여러 WI를 spawn하면 *복합 작업*으로 간주, 분할 권고 | evidence.commit_sha 1차 키 정합성 |
| 4 | **WI 생애 = 단일 sprint 내 proposed→active→done(또는 superseded)** | status 전이도 일관성 |
| 5 | **`superseded_by`로 다른 sprint의 후속 WI 참조 가능** | 작업 진화 표현 |

---

## 2. 단일 sprint 속함 (결정 1)

### 정의

- 하나의 work-item은 **하나의 sprint 그룹**에 속한다.
- "sprint 그룹"은 plan 문서의 § Sprints 섹션의 sprint 분할 (예: Sprint 1 / Sprint 2).
- WI 파일의 `source_docs[0]`이 가리키는 plan 문서 + plan 내 sprint 번호 = WI의 sprint 소속.

### 비단일 시나리오 거절 사유

| 시나리오 | 거절 사유 |
|---------|----------|
| WI가 Sprint 1에서 시작해 Sprint 3까지 active 유지 | sprint 게이트(Evaluator PASS)가 sprint 종료 시점에 WI status 동결을 요구 — 다중 span 시 어떤 sprint에서 done 판정할지 모호 |
| 하나의 WI가 여러 plan을 참조 | source_docs는 배열이지만 *역할*은 단일 plan에 종속 (다른 plan은 reference only) |
| Sprint 1 종료 시 미완 WI를 Sprint 2로 carry-over | carry-over는 **새 WI**(`superseded_by` 사용) 또는 status=blocked 후 sprint 종료 후 재시작 |

### 예외: Sprint Contract Done 조건

- Plan의 § Sprints 표에서 한 sprint가 여러 Done 조건을 가질 수 있음 (Sprint Contract 31개 중 Sprint 4는 4개 Done 조건). 이때:
  - **각 Done 조건 = 1 WI**가 자연스러움 (세부 작업 분할)
  - 또는 **sprint 단위 = 1 WI**도 허용 (WI 내부에 sub-checklist는 notes 필드)
  - **결정 권장**: 검증 명령이 1개면 sprint 단위 1 WI, 여러 개면 Done 조건별 WI 분할
- 단, 한 WI가 *여러 sprint에 걸치는 것은 항상 금지*.

---

## 3. depends_on 필드 의미 (결정 2)

### 사용 케이스

```jsonc
{
  "id": "WI-0042-search-filter",
  "depends_on": [
    "WI-0040-database-index",   // 같은 sprint
    "WI-0035-auth-refactor"     // 다른 sprint (Sprint 2 종료된 WI)
  ]
}
```

### 규칙

- `depends_on`은 **다른 WI id 배열** (자기 id 포함 금지 — 순환 의존 검출 룰 W1 신규 — Sprint 4)
- `depends_on`의 WI가 *어느 sprint든* 상관없음 — 작업 의존성 자연스러움
- 단, **`/nova:next` 추천 알고리즘**은 `depends_on`의 *모든 WI가 status=done*인 WI만 후보로 선정
- `depends_on`의 WI가 미존재 → drift H5 (Hard) 발화

### 비사용 케이스

- "WI A가 WI B와 동시에 진행되어야 한다" 같은 *병렬 작업*은 `depends_on`이 아니라 *같은 sprint 그룹*에 두 WI를 둠
- "WI A 후 WI B가 자동 spawn된다" 같은 *연쇄 트리거*는 `depends_on` 아니라 *수동 작업* (사용자 또는 orchestrator가 명시적으로 새 WI 생성)

---

## 4. 1 변경 = 1 WI 원칙 (결정 3)

### 정당화 (Codex evidence 원칙과 정합)

- `evidence.commit_sha`가 DORA 표준 1차 키이며 *단일 작업의 완료 증거*.
- 한 commit이 여러 WI를 동시 done으로 만든다면 → 어떤 WI의 commit_sha인지 모호 + work-item lifecycle 추적 가치 저하.
- 한 변경에 여러 WI가 필요하면 → *작업이 너무 큼* → 사전 분할이 정답.

### 허용 케이스

- 한 commit이 여러 WI의 *부분 진전*에 기여 (예: 인프라 작업이 3개 WI 모두에 필요한 setup) → **`source_docs` 또는 `notes`에 commit_sha 기록** but `evidence.commit_sha`는 비워둠. status=done 전이는 별도 commit으로 분리.

### 거절 케이스

- 한 commit으로 WI-A와 WI-B를 동시에 done 처리 → 거절. 두 WI 중 하나는 *원래 한 WI였어야* 함 → 통합 또는 분할.

---

## 5. 생애 주기 (결정 4)

```
[Sprint N 시작]
   │
   v
 proposed ──> active ──> done
                │           │
                └─> blocked ─┘
                     │
                     └─> active (블로커 해소)
[Sprint N 종료, Evaluator PASS]
   │
   v
 다음 sprint
```

### sprint 종료 시 status별 처리

| status | sprint 종료 시 행동 |
|--------|------------------|
| `done` | 다음 sprint로 carry 안 함. Recent Activity 영역에 표시. |
| `active` | sprint 종료 *전*에 done 또는 blocked로 전이되어야 함. 미전이 시 sprint 미완 (Evaluator FAIL) |
| `blocked` | sprint 종료 *허용*. 단, blocked_reason이 다음 sprint에서 해소되지 않으면 새 WI로 fresh start 권고 |
| `proposed` | 시작 안 된 WI. sprint 종료 시 미시작이면 `archived_at` set 후 다음 sprint에서 새 WI로 재제안 또는 drop 결정 |

---

## 6. superseded_by 의미 (결정 5)

### 사용 케이스

- WI-A가 Sprint 1에서 done 됐는데, Sprint 3에서 *재정의된 WI-B*가 WI-A의 기능을 대체.
- 이때 WI-A.status는 done 유지하되, **WI-B 생성 시 WI-A.superseded_by = WI-B** + WI-A.archived_at set.

### 규칙

- `superseded_by`는 **다른 sprint의 후속 WI** id (같은 sprint도 가능하나 드뭄).
- `superseded_by` set 시 `archived_at` 자동 set + status=superseded.
- 역참조: 후속 WI는 `notes`에 "supersedes WI-A" 기록 (기계 표현 없음 — 단방향 superseded_by만).

### 비사용

- WI 취소·삭제 = `superseded_by` 아님. status=superseded + `notes`에 사유 기록 (취소 사유는 자유 텍스트).

---

## 7. Schema 영향 (Sprint 1 동결 사항)

### 동결 필드 의미

```jsonc
// .nova/schema/work-item.schema.json (Sprint 1 작성)
{
  "type": "object",
  "properties": {
    "depends_on": {
      "type": "array",
      "items": { "type": "string", "pattern": "^WI-(\\d{4}|[a-f0-9]{8})-[a-z0-9가-힣-]+$" },
      "uniqueItems": true,
      "description": "다른 WI id. 순환 의존 검출은 drift H5(미존재)·W1 신규(순환)"
    },
    "source_docs": {
      "type": "array",
      "items": { "type": "string", "pattern": "^(docs|specs|tests|scripts|hooks|skills|commands|agents)/" },
      "description": "repo-relative path. source_docs[0] = primary plan (sprint 소속 결정)"
    },
    "superseded_by": {
      "oneOf": [
        { "type": "null" },
        { "type": "string", "pattern": "^WI-(\\d{4}|[a-f0-9]{8})-[a-z0-9가-힣-]+$" }
      ]
    }
  }
}
```

### sprint 소속 표현 (필드 추가 X)

- **결정**: 별도 `sprint` 필드를 두지 않음. `source_docs[0]` plan의 Sprint 표에서 추론.
- 이유: plan이 진실원, WI는 plan을 참조. plan의 sprint 번호 변경 시 WI 자동 따라감 (역참조 비용 0).
- drift W7 (신규): `source_docs[0]` plan의 Sprint 표에 매핑되는 entry 없음 → warn.

---

## 8. 결정 영향 표 (다른 spec)

| 결정 | state-call-graph-v3.md 영향 | registry-write-authority-v3.md 영향 |
|------|---------------------------|----------------------------------|
| 단일 sprint 속함 | sprint 종료 시 `registry-write.sh transition active→done`을 9 진입점 중 어느 게 트리거? (run/auto/review) | sprint 전이 권한 = orchestrator only (cross-sprint state 변경) |
| `depends_on` cross-sprint | `/nova:next` 추론 알고리즘에 depends_on 해결 로직 | next 호출 권한 = read-only (사용자만, sub-agent X) |
| 1 변경 = 1 WI | commit_sha 추출 시 ambiguous case 거절 정책 | evaluator_pass 호출 = 1 WI 당 1 commit_sha |
| superseded_by 후속 sprint | transition superseded 시 archived_at + render-state.sh 재호출 | superseded 권한 = orchestrator (의도적 폐기는 신중) |

---

## 9. 검증

이 spec이 통과되었음을 검증:

```bash
test -f docs/specs/work-item-scope-v3.md
grep -qE "단일 sprint" docs/specs/work-item-scope-v3.md
grep -qE "1 변경 = 1 WI\|1 변경, 1 WI" docs/specs/work-item-scope-v3.md
grep -qE "depends_on" docs/specs/work-item-scope-v3.md
```

Sprint 0 Done 조건 매핑: `Sprint 0 Done #1` (work-item-scope-v3.md 존재 + 스코프 명시).
