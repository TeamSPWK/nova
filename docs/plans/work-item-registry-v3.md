# [Plan] Work-Item Registry v3 — Nova 플러그인 작업 추적 시스템

> Nova Engineering — CPS Framework
> 작성일: 2026-05-15
> 작성자: Nova DeepPlan
> Mode: deep
> Iterations: 1 (Critic FAIL → Refiner 1회 surgical edit 완료)
> Design: docs/designs/work-item-registry-v3.md
> Critic Resolved: Critical 5 + High 6 + Medium 1 = 12 이슈 surgical edit 완료. Risk Map 5건 + Verification Hook 3건 추가. Sprint 0 신설. 미해결 시스템적 권고 3건은 § "Critic 미해결 항목"에 명시.

---

## Context (배경)

### 현재 상태

Nova(Claude Code 플러그인)는 v5.41.0 시점 작업 추적을 `NOVA-STATE.md`(사람용, 50줄 cursor) + `.nova/events.jsonl`(기계용, KPI 산출)로 운영한다. 9개 진입점(`/nova:plan`, `/design`, `/deepplan`, `/run`, `/auto`, `/review`, `/check`, `/ux-audit`, `/evolve`)이 STATE 갱신 의무를 진다. `migrate-nova-state.sh`가 v1→v2 schema 변환 흐름을 확립했다.

**실증된 갭** (형제 프로젝트 9개 조사 결과):

| 갭 | 증거 |
|---|---|
| NOVA-STATE.md drift | `planreview` STATE goal "외곽선 GT annotator" vs 실제 작업 = parking-zone revert. 완전 다른 트랙. |
| 50줄 룰 무용지물 | `nova-landing` 39일 stale. `swk-ground-control` 136줄. 규칙보다 *갱신 주기*가 문제. |
| frontmatter 미표준 | `planreview` 51개 plan에 YAML/markdown 강조/혼합 3종 혼재. |
| `/nova:next` stale 추론 | 9개 진입점이 free-text docs 검색으로 다음 작업 추론 → 완료된 작업 재추천. |
| 자생적 패턴 발견 | `swk-ground-control`이 Active Tree(✅/⬜/🔄) + AO 트랙을 직접 보강 — Nova가 빠뜨린 영역. |

### 왜 필요한가

- **사용자 자체 검증**: 사용자가 "구조가 자꾸 바뀌면 안 된다"고 강조 — 한 번 결정하면 자주 바꿀 수 없음.
- **선례 부재**: BMad·Cline·Backstage·dbt·spec-kit 등 조사 결과, "사람용 cursor + 기계용 진실원 명시 분리"는 OSS에 없음. Nova의 독창성 + Generator-Evaluator 게이트가 work-item lifecycle을 검증하는 패턴은 새 시도.
- **9개 형제 프로젝트 마이그레이션** 비용이 큼 — 첫 결정이 안정적이어야 함.
- **AI 에이전트가 stale 문서에서 다음 작업을 추론**하는 안티패턴을 정면으로 차단해야 함.

### 관련 자료

**Nova 내부 (15개 핵심 파일)**:
- `commands/{plan,design,deepplan,run,auto,review,check,ux-audit,evolve}.md` — 9 진입점
- `commands/{setup,migrate-state,next,check,status}.md` — 통합 대상
- `skills/context-chain/SKILL.md` — 동시 기록 원칙, 50줄 트림
- `scripts/migrate-nova-state.sh` — v1→v2 변환 패턴
- `hooks/record-event.sh` — 11타입 JSONL 이벤트 (schema_version 2)
- `docs/templates/nova-state.md` — v2 템플릿
- `docs/specs/nova-state-schema-v2.md` — v2 schema 사양
- `tests/test-scripts.sh` — drift 룰 추가 위치

**OSS 선례 (검증된 표준)**:
- adr-tools/spec-kit `NNNN-slug` 4자리 순차 ID
- MADR `proposed/accepted/superseded` lifecycle
- dbt `schema.yml`(사람) → `manifest.json`(자동) 단방향 reconcile
- DORA `commit_sha` evidence 표준
- BMad flat 200+ 무너짐 사례

**합의된 결정 트레일**:
- OSS 조사 → Codex 자문 → `/nova:ask` Strong Consensus 100% (Claude/GPT/Gemini 만장일치)
- 합의율: 100% → AUTO APPROVE (저장: `docs/verifications/2026-05-15--Nova-Engineering-핵심-설계-결정-자문-평가-기준-독.md`)

---

## Problem (문제 정의)

### 핵심 문제

**AI 에이전트가 stale 문서/구두 합의에서 "다음 작업"을 추론하여 잘못된 추천을 한다. NOVA-STATE.md는 사람용 cursor의 역할과 기계용 진실원 역할을 동시에 짊어져서 wiki화·drift·갱신 누락이 발생한다. 9 진입점의 일관된 단일 쓰기 경로가 없다.**

### MECE 분해 (Critic 권고 흡수 — 자생적 패턴 #6는 "기회"로 별도, 누락 영역 3개 추가)

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | 진실원 부재 + 9 진입점 일관성 (단일 문제의 두 측면) | 사람용 cursor와 기계용 진실원이 같은 파일에 섞이고, 9 진입점이 각각 다른 갱신 패턴. drift 검증 메커니즘 부재. | Critical |
| 2 | next-work 추론의 stale | free-text docs 검색으로 후보 선정 → 완료된 작업 재추천. | High |
| 3 | 마이그레이션 흐름 부재 | 기존 사용자 프로젝트(v1/v2 다양)를 v3로 안전 이행할 자동화 부재. | High |
| 4 | drift 감지 부재 | 코드/plans/STATE/registry 간 불일치를 잡을 룰 없음. | High |
| 5 | id·status·evidence 표준 부재 | plan 문서가 자유 형식 — 자동 처리 불가. | Medium |
| 6 | **롤백·다운그레이드 경로 부재** (신규) | v3→v2 다운그레이드 절차 명시 없으면 critical 발견 시 데이터 손실. | High |
| 7 | **사용자 교육·변경 관리 부재** (신규) | 9개 형제 프로젝트 사용자에게 sprint별 무엇을 해야 하는지 안내 없음. | Medium |
| 8 | **멀티 에이전트 동시성 정책 부재** (신규) | Codex 위임·다중 워크트리 환경에서 registry 갱신 책임 경계 미정의. | High |

> `swk-ground-control` Active Tree·AO 트랙 등 **자생적 패턴**은 문제가 아닌 *기회* — Solution § 구현 범위 Sprint 5에서 별도 흡수 (PoC 결과 반영).

### 제약 조건

**동결된 7개 결정 (`/nova:ask` Strong Consensus + Codex 자문, 변경 금지)**:

1. `schema_version: "3.0"`
2. **status enum 5값** (절대 늘리지 말 것 — GPT 강조): `proposed | active | blocked | done | superseded` + 보조 플래그 `review_required: bool` + `archived_at: timestamp|null`. **원자적 전이 규칙 (Claude 강조)**: Evaluator PASS → `status=done` + `review_required=false` 동시 적용.
3. **id 형식**: `WI-NNNN-slug` (4자리 순차, adr-tools/spec-kit 정통).
4. **evidence (DORA)**: `commit_sha` required for `done`; `test_output`/`files_changed`/`pr_url` optional.
5. **NOVA-STATE.md marker**: `<!-- nova:registry-rendered:start -->` ~ `<!-- nova:registry-rendered:end -->` — 안쪽만 자동 렌더, 바깥은 사람 손편집 보존.
6. **`.gitignore` 패턴 (사용자 프로젝트 배포용)**:
   ```
   .nova/*
   !.nova/work-items/
   !.nova/work-items/**
   !.nova/schema/
   !.nova/schema/**
   !.nova/README.md
   .nova/events.jsonl
   .nova/local/
   .nova/tmp/
   ```
7. **저장 형식 (분할 + 단일 쓰기 경로 — Gemini 강조)**:
   - `.nova/work-items/WI-NNNN-slug.json` (개별 work-item)
   - `.nova/work-items/index.json` (경량 매니페스트: `{id, status, review_required, updated_at}`)
   - **9 진입점은 index.json 경유 쓰기만 허용**, 개별 파일 직접 편집 금지.

**구조적 제약 (code-explorer 결과)**:
- 9 진입점이 현재 STATE 갱신 패턴이 5종으로 다양 (Current Goal/Phase, Recently Done, Last Verification + Risks, Known Gaps, Last Activity only)
- `record-event.sh`는 11타입 JSONL 이벤트 + `schema_version: 2` → v3 확장 필요
- `migrate-nova-state.sh`는 v1→v2 흐름이 graceful fallback 사용 — v2→v3는 패턴 재사용 가능
- `flock`은 macOS 미기본 — fallback 필요 (mkdir atomic directory)
- 형제 프로젝트는 v1 (planreview, nova-landing) / v2 (swk-ground-control) 혼재

---

## Solution (해결 방안)

### 선택한 방안

**방안 B — 점진 도입 (sprint 분할, option-explorer 권장)**.

**선택 근거 (3가지 — Critic 권고 흡수, 사실 근거로 재정리)**:

1. **Nova 핵심 원칙(Generator≠Evaluator) 준수**: 각 sprint 완료 후 Evaluator 게이트(Verification Hook 번호 매핑, § Sprints 표 참조)를 통과해야 다음 sprint 진행. Big-bang(방안 A)도 Evaluator를 쓸 수 있으나, 점진은 *부분 PASS*를 가능하게 해 작업 단위 격리가 가능.
2. **롤백 비용 최소 + 작업 격리**: 각 sprint별 patch/minor 범프 → critical 버그 발견 시 직전 sprint로만 되돌림. § Sprints 롤백 시나리오 4개로 명시. 평행 v2/v3 공존(방안 C)은 분기 처리 추정 비용(원래 Synthesizer가 "2배"라 단언했으나, Critic 지적대로 분기 처리가 한 곳에 집중되면 ×1.2 수준 가능 — 그래도 *테스트 커버리지 2배*는 객관적 비용).
3. **신규 프로젝트 즉시 적용**: Sprint 1 완료(schema + bootstrap) 출시 직후 *신규* 프로젝트는 v3 기반 부트스트랩 가능. 기존 v1/v2 형제(planreview·swk-ground-control 등)는 Sprint 3+4 완료 후에 마이그레이션 — *Sprint 1 직후 형제 9개 즉시 적용은 사실과 다르므로 정정*.

> Synthesizer는 처음 option-explorer 14주를 "진입점 3-3-3 그룹화 인위적"이라는 단일 근거로 10주 압축했으나 Critic 지적대로 불충분. Refiner에서 Sprint 3+4 *병렬화*로 재근거 명시 — 두 sprint는 registry 동작(Sprint 2 종료)에만 의존하고 서로 직교(migrate-state는 v2→v3 변환, drift 룰은 신규 데이터 검증). PR 규모는 "20~30 파일, 9 진입점 + 7 스킬 + schema + scripts + tests 동시 검증 위험"으로 정정 (Synthesizer 원안 +150~200커밋은 라인 변경 수와 혼동된 부정확한 수치).

### 대안 비교

(option-explorer Tree-of-Thought 결과 그대로)

| 방안 | 접근 | 장점 | 단점 | 권장도 |
|------|------|------|------|--------|
| A | Big-bang v3 (한 PR, minor 범프) | 한 번에 통합, 분기 처리 없음, 롤백 단순 | 단일 PR 20~30 파일 + 9 진입점 + 7 스킬 동시 검증 위험, critical 시 전체 영향 | |
| B | 점진 sprint 분할 (~8~10주) | sprint별 Evaluator 게이트, 롤백 최소, 형제 즉시 적용 | 일정 길이, 미결정 상태 지속 | **⭐** |
| C | 평행 v2/v3 공존 | 옵트인 마이그레이션, 롤백 zero-cost | 분기 처리 2배, 테스트 2배, "연기된 결정" | |

### 구현 범위

**Sprint 1 — Schema 동결 + Bootstrap (v5.42.0 minor)**:
- [ ] `.nova/schema/work-items.schema.json` JSON Schema 작성 (필드: id/title/status/review_required/archived_at/priority/depends_on/source_docs/evidence/created_at/updated_at/owner?/notes?/superseded_by?)
- [ ] `.nova/schema/index.schema.json` 매니페스트 schema
- [ ] `.nova/README.md` "DO NOT EDIT" + 정책 안내
- [ ] `scripts/registry-write.sh` (단일 쓰기 경로 — flock + mkdir fallback)
- [ ] `scripts/registry-render-state.sh` (marker 영역 자동 렌더)
- [ ] `commands/setup.md` 갱신: 신규 프로젝트 부트스트랩 + `.gitignore` 패턴 추가
- [ ] `commands/setup.md` 32항목 5 Pillar에 work-items 항목 1개 추가 (`--check` 모드)
- [ ] `docs/templates/nova-state.md` v3 템플릿 — marker 추가
- [ ] `docs/specs/work-item-schema-v3.md` 사양 문서
- [ ] `tests/test-scripts.sh` Sprint 1 검증 (schema 유효성·id 유일성·git-tracked 보장)

**Sprint 2 — 진입점/스킬 통합 (v5.42.0 minor — Critic 권고로 patch→minor 상향: 핵심 데이터 경로 교체)**:
- [ ] `record-event.sh` `schema_version: 3` + 신규 이벤트 타입 3종 (`work_item_created`/`work_item_transitioned`/`registry_rendered`)
- [ ] **9 진입점** 각 markdown 갱신: STATE 직접 갱신 로직 제거, `registry-write.sh` 호출로 대체 (`commands/{plan,design,deepplan,run,auto,review,check,ux-audit,evolve}.md`)
- [ ] **STATE 갱신 수행 7 스킬/커맨드 추가 갱신**: `skills/{context-chain,deepplan,evaluator,orchestrator,strategic-compact,ux-audit}/SKILL.md` + `commands/audit-self.md` — 직접 갱신 코드 제거, `registry-write.sh` 경유
- [ ] `/nova:run`·`/nova:auto`: Evaluator PASS 시 원자적 전이 (`status=done` + `review_required=false`) 호출
- [ ] `/nova:review`·`/nova:check`·`/nova:ux-audit`: `review_required=true` 설정
- [ ] `/nova:evolve`: 기존 `evolve_decision` 메커니즘 유지 (registry와 직교)
- [ ] `tests/test-scripts.sh` Sprint 2 검증 (9 진입점 + 7 스킬 시뮬레이션 — STATE 갱신 후 work_item 상태 검증)

**Sprint 3 — NOVA-STATE.md 자동 렌더 + migrate-state v2→v3 (v5.42.2 patch)**:
- [ ] `scripts/migrate-nova-state.sh` v2→v3 분기 추가 (`--target=v3` 플래그)
- [ ] v2 Tasks 표 → work-item 추출 추론 규칙 (**모두 `proposed` 마킹, `done` 추론 금지 — Codex 명시**)
- [ ] v2 백업 파일명: `NOVA-STATE.md.v2.bak`
- [ ] `commands/migrate-state.md` 갱신: v1→v2→v3 multi-hop dry-run → review → apply
- [ ] `skills/context-chain/SKILL.md` v3 흡수: 50줄 룰을 marker 외 영역만 카운트 / 동시 기록 원칙 갱신
- [ ] 자동 렌더 트리거: `registry-write.sh` 직후 `registry-render-state.sh` 호출
- [ ] `tests/test-scripts.sh` Sprint 3 검증 (v2→v3 round-trip + marker 영역 보존)

**Sprint 4 — drift 룰 + `/nova:check` 통합 (v5.42.3 patch)**:
- [ ] `commands/check.md`에 drift 룰 **Hard 9 + Warn 9 = 총 18종** 추가:
  - **Hard error (9종)**: H1 schema 유효성 · H2 id 유일성 · H3 status enum · H4 git-tracked 보장 · H5 `depends_on` 존재 · H6 `done` evidence 부재 · H7 orphan id (index↔파일 불일치) · **H8 부분 전이 마커 잔류** (신규) · **H9 status=blocked인데 blocked_reason 비어있음** (신규)
  - **Warn-only (9종)**: W1 stale STATE 7일+ · W2 plan frontmatter 누락 · W3 unreferenced plan(고아) · W4 last_verified_at 30일+ (status=active만) · **W5 git 커밋 이력 부재** (신규) · **W6 UUID fallback id 발견** (신규, reindex 권고) · **W7 source_docs[0] plan 미매핑** (신규) · **W8 marker 영역 사용자 손편집 감지** (신규) · **W9 비표준 actor가 registry-write 호출** (신규)
- [ ] `tests/fixtures/drift-cases/` 디렉토리 + **9개** 인위적 Hard drift fixture (H1~H9 각 1개)
- [ ] severity tier (Critical/Warning/Info) + `.nova/.dismissed-drifts` 메커니즘
- [ ] `commands/next.md` registry-first 추론 알고리즘 (priority + depends_on 해결 + status=`active|proposed` 우선)
- [ ] `commands/status.md` HTML dashboard에 registry 렌더링 추가
- [ ] `tests/test-scripts.sh` Sprint 4 검증 (drift 룰 18종 + severity tier)

**Sprint 5 — PoC dry-run + 본 레포 적용 (v5.43.0 minor)**:
- [ ] PoC 1: `nova-landing` (작은 프로젝트, plans 0개, STATE 39일 stale) — bootstrap-only 경로 검증
- [ ] PoC 2: `swk-ground-control` (v2 STATE, Active Tree 정착, plans 29개) — v2→v3 마이그레이션 + Active Tree → work-items 변환 손실율 측정
- [ ] PoC 3: `planreview` (v1 STATE, plans 51개, frontmatter 혼재, drift 실증) — 최악 케이스 마이그레이션 + 손실율 ≤20% 확인
- [ ] **본 레포 자체 적용 (eat your own dog food)**: `/Users/jay/develop/nova` NOVA-STATE.md → v3 마이그레이션
- [ ] PoC 결과 보고서: `docs/verifications/2026-XX-XX-v3-poc.md`

**Sprint 6 — 형제 프로젝트 점진 마이그레이션 (v5.43.1 patch)**:
- [ ] 나머지 **7개** 형제 프로젝트(`agent-work-memory`, `markbrief`, `md-template-compiler`, `nova-orbit`, `spwk-product`, `swk-data-pipeline`, `swk-cloud-manage`) 점진 마이그레이션 — 각 PR 별 dry-run → 사용자 검수 → apply (PoC 3개 + Sprint 6 7개 = **총 10개** 형제 적용. 본 레포 자체 적용은 별도)
- [ ] release notes: v3 특징 + 마이그레이션 가이드 + 자생적 패턴(Active Tree) 흡수 안내
- [ ] `docs/guides/work-item-registry-v3.md` 사용자 가이드 작성

### 검증 기준

(Verification Hooks의 Critical 항목 발췌 — 상세는 § Verification Hooks)

1. **9 진입점 단일 쓰기 경로 강제**: 9개 markdown 모두 STATE 직접 갱신 코드 제거 후 `registry-write.sh`만 호출하는지 grep 검증.
2. **마이그레이션 0% 데이터 손실 (구조적)** + ≤20% 손실 (비정형 부분): PoC 3개 사전/사후 비교 — Tasks/Risks/Known Gaps 항목 수 보존율.
3. **status 5값 강제**: schema 위반 시 hard error. `/nova:check`에서 enum 위반 즉시 차단.
4. **Evaluator PASS 원자적 전이**: `/nova:run`·`/nova:auto` 시뮬레이션 → `status=done` 시 `review_required=false` 동시 보장.
5. **drift 룰 발화 정확성**: Hard 9종 100% 검출(fixture 기반), Warn 9종 false-positive 실보유 10개 프로젝트(형제 9 + 본 레포) 샘플 기준 ≤10%.
6. **본 레포 자체 적용**: Nova 본 레포의 NOVA-STATE.md가 v3 marker 사용 + work-items 동작.

---

## Sprints (스프린트 분할)

| Sprint | 기간 | 범프 | 산출 (대표) | Evaluator 게이트 (Hook 번호 매핑) | 형제 영향 | 사용자 안내 |
|--------|------|------|------------|--------------------------------|----------|------------|
| **0** | 0.5주 | (사전 조사) | WI 스코프 정의 + 9 진입점 + 6 스킬 STATE 갱신 call graph 매핑 | Unknown #1·#3 해소 (산출: `docs/specs/work-item-scope-v3.md`) | — | "Sprint 0 진행 중 — 사용자 영향 없음" |
| 1 | 1.5주 | v5.42.0-rc1 minor | schema + bootstrap | Critical Hook #1·#2·#3·#5 PASS + High Hook #12 PASS | 신규 프로젝트 한해 bootstrap 가능 (기존 v1/v2 형제는 Sprint 3+5 후 마이그레이션) | "v3 schema 인식 가능. 마이그레이션은 Sprint 3 이후 권장" |
| 2 | 1.5주 | **v5.42.0 minor** | 9 진입점 + 7 스킬/커맨드 통합 + record-event v3 | Critical Hook #6·#7 PASS + Sprint 2 회귀 PASS | 영향 없음 (진입점만 갱신) | "v3 진입점 통합 완료. `/nova:setup --upgrade` 권장" |
| 3+4 (병렬) | 2주 | v5.42.1 patch | (3) 자동 렌더 + migrate-state v2→v3 (4) drift 룰 Hard 9+Warn 9 = 18종 + `/nova:next` registry-first | Critical Hook #9·#10·#16·#17 PASS + drift fixture 9 Hard 100% 검출 | 영향 없음 | "v2→v3 마이그레이션 가능. drift 검증 활성화" |
| 5 | 2주 | v5.43.0 minor | PoC 3개 마이그레이션 + 본 레포 자체 시연 | Critical Hook #4·#8 PASS (PoC 보존율 ≥80%) — 본 레포 적용은 시연(Hook #15는 Sprint 6 PoC 결과 검증 후) | PoC 3개에 직접 적용 | "PoC 시작. 자기 프로젝트 적용은 Sprint 6 권장" |
| 6 | 2주 | v5.43.1 patch | 형제 7개 점진 + 가이드 + Hook #15 PASS | 형제 10개(PoC3+Sprint6 7) + 본 레포 모두 정상 운영 | 형제 7개 마이그레이션 | "전체 v3 안정화. release notes + 가이드 공개" |

**총 일정**: 약 9~10주 (Sprint 0 0.5주 + Sprint 1·2 각 1.5주 + Sprint 3+4 병렬 2주 + Sprint 5·6 각 2주). option-explorer 14주 → Critic 권고 흡수해 Sprint 3+4 병렬화로 압축.

**Sprint 간 의존**:
- Sprint 0 → 1 (WI 스코프 정의 → schema 동결)
- Sprint 1 → 2 (schema 동결 → 진입점 통합)
- Sprint 2 → 3+4 (record-event v3 + registry 동작 → migrate-state·drift 룰 병렬)
- Sprint 3+4 → 5 (registry 완성 → PoC)
- Sprint 5 → 6 (PoC 결과 반영 → 점진 마이그레이션)

**롤백 지점**:
| 발견 시점 | 롤백 절차 |
|-----------|----------|
| Sprint 1~2 출시 후 critical 버그 | `git revert {commit}` → patch 출시 (`v5.42.0-hotfix.1`). work-items 미존재라 데이터 손실 없음 |
| Sprint 3+4 후 critical 버그 | v5.42.0 (Sprint 2 종료 시점)으로 revert. 이미 마이그레이션한 사용자는 `.nova/work-items/`를 `.nova/work-items.v3.bak/`로 백업 후 v2 STATE.md.v2.bak 복원 |
| Sprint 5 자기 적용 도중 critical 버그 | 본 레포만 영향. Nova 본 레포 NOVA-STATE.md.v2.bak 복원 + `.nova/work-items/` 보존(다음 hotfix 대응) + Sprint 5 보류, Sprint 6 재계획 |
| Sprint 6 형제 마이그레이션 도중 | 해당 형제 프로젝트만 v2로 revert (PR 단위 격리). 다른 형제 영향 없음 |

---

## Risk Map

(risk-explorer 결과 그대로 — 12개 위험 + 완화)

| 리스크 | 가능성 | 영향 | 완화 |
|--------|--------|------|------|
| 9 진입점 중 1~2개 누락: STATE 갱신 불일치 | H | H | ① 각 진입점 manifest에 `registry-write.sh` 호출 체크리스트 추가. ② pre-commit hook: git diff 변경 후 Last Activity 24h+ 경고. ③ tests: 9 진입점 시뮬레이션 후 work_item 상태 검증. |
| 마이그레이션 데이터 손실: v2→v3 Tasks/Risks/Known Gaps 추론 실패 | M | H | ① `legacy_meta` 섹션에 비정형 항목 보존. ② 명시 상태만 복사, `done` 추론 금지(Codex 명시). ③ 원본 v2 `NOVA-STATE.md.v2.bak` 백업 강제. ④ 보존율 ≤80% 시 사용자 동의 필수. |
| 채번 race: 다중 에이전트 동시 WI-NNNN 생성 시 중복 | M | H | ① `flock` + git pre-commit hook으로 serial write. WI-NNNN은 index.json 최고값+1 원자적 갱신. ② flock 경합 시 WI-{UUID} fallback → 다음 세션 `reindex-work-items.sh` 재번호화. ③ test: 20개 병렬 spawn. |
| 사람 손편집 충돌: 마커 안쪽 사용자 편집 → 자동 렌더 덮어씀 | M | H | ① marker 안쪽 "DO NOT EDIT" 헤더. ② 자동 렌더 직전 `git diff` 표시 + "변경사항 있으면 먼저 commit" 경고. ③ `--no-render` 플래그로 렌더 스킵 가능. ④ 사후 `git log -p` 복구 가이드. |
| schema 진화: v3.0→v3.1 backward compat 미처리 | M | M | ① v3.1 추가 필드는 optional + default 필수. ② old nova가 신 schema 만나면 미지 필드 무시(forgiving reader). ③ JSON schema `$comment`에 도입 버전 명시. ④ 호환성 test: old nova + new work-items 시뮬레이션. |
| dbt-스타일 손편집 충동: "DO NOT EDIT" 헤더만 불충분 | M | M | ① git `pre-commit` hook에서 marker 영역 변경 감지 시 commit 거절 (`--force-edit` 플래그로만 우회). ② `CONTRIBUTING.md`에 자동 생성 영역 정책 명시. |
| 알람 피로: drift 룰 18종 매 세션 발화 → 사용자 무시 | L | M | ① severity tier 분기 (Critical: H1~H9 = 9 / Warning: W1~W9 = 9 / Info: dismissed). ② 각 룰에 "해결 방법 1줄" 추가. ③ `.nova/.dismissed-drifts` dismiss 메커니즘 (14일 자동 만료). ④ dismissed 목록 bi-weekly 자동 정리. |
| registry 단일 파일 성능: 1000개 work-item + index.json 병목 | M | M | ① 분할 저장 (`.nova/work-items/WI-NNNN-slug.json`) 단일 파일 읽기 O(1). index.json은 메타만 (<10KB at 1000 items). ② 성능 test: 1000개 + jq 쿼리 시간 측정 (<1초). |
| 부트스트랩 직후 빈 registry: /nova:next fallback | M | M | ① fallback 우선순위: (a) `.nova/work-items/` (b) NOVA-STATE.md Tasks 섹션 (c) git log Completed 항목 (d) "새로 시작" 안내. ② 마이그레이션 완료 후엔 fallback 불필요. |
| frontmatter 없는 plan 추출: planreview 51개 plan 중 50개 미정형 | M | M | ① 사전 audit: `grep -L "^---"` 미정형 plan 식별. ② 최소 frontmatter (`slug`, `work_items: []`) 추가. ③ 미정형 시 파일명 + 첫 줄 제목으로 slug 추론. ④ stderr 경고. |
| Windows-WSL 호환성 | L | M | ① `.gitignore` 패턴 git portable. ② `flock` 부재 시 `mkdir .nova/.lock/WI-{pid}` atomic dir. ③ `jq` exists 체크. ④ symlink WSL 2.27+ OK. ⑤ GitHub Actions CI windows-latest. |
| NOVA-STATE.md 50줄 룰 자동 렌더 영역 변동 | L | M | ① marker 영역을 50줄 카운트에서 **제외**. ② "관리 대상 50줄" = Last Activity + Recently Done + Current/Blocker/Risks/Gaps만. ③ 스크립트: `grep -v 'nova:registry-rendered' \| wc -l`. |
| **`/nova:setup --upgrade` 실행 시 v3 registry와 충돌** (신규, Critic 지적) | M | H | ① `commands/setup.md` --upgrade 흐름에 "`.nova/work-items/` 존재 시 idempotent skip" 추가. ② 기존 work-items 변경 없이 schema·README·gitignore만 갱신. ③ Sprint 1 체크리스트에 idempotent 검증 추가. |
| **사용자 수동 git revert 후 index.json만 stale** (신규) | M | H | ① drift 룰 H7(orphan id): `index.json` id와 실제 파일 시스템 동기화 (Design § drift 룰 표 참조). ② Sprint 4 fixture에 `index-stale-after-revert` 추가. |
| **`git commit --no-verify` 우회로 marker 영역 손편집 commit** (신규) | H | H | ① server-side check 불가 (Nova는 로컬 도구). ② `/nova:check`에 "마지막 마커 영역 git history와 자동 렌더 결과 비교" 검증 추가 → 손편집 사후 검출. ③ 사용자 가이드에 "`--no-verify` 사용 시 다음 자동 렌더가 덮어쓸 수 있음" 명시. |
| **다중 git worktree에서 동시 registry 갱신** (신규, Critic 지적) | M | H | ① Sprint 0 사전 조사로 `.nova/` worktree 공유 여부 확인 (현재 worktree-setup 스킬 동작 분석). ② 공유면 flock 단일, 분리면 worktree별 lock + index.json 머지 정책 필요. ③ 결정 후 Sprint 1 schema에 반영. |
| **사용자 `.gitignore`가 `.nova/`만 통째로 ignore (구 가이드)** (신규) | M | H | ① `commands/setup.md` --upgrade 시 기존 `.gitignore` 진단: `.nova/`만 있고 `!` 예외 없으면 자동 추가 + 사용자 동의 요청. ② Verification Hook #5(git-tracked 보장)가 setup --upgrade 직후 검증. |
| **한국어/비 ASCII slug 생성 손실** (신규, Critic 지적) | M | M | ① slug 규칙 명시: 한글·영문·숫자·하이픈 허용(orchestrator/deepplan SKILL slug 규칙 재사용). ② id regex `^WI-\d{4}-[a-z0-9가-힣-]+$`로 확장. ③ Sprint 0 schema 동결 전 확정. |

---

## Unknowns

(risk-explorer 결과 그대로 + 우선순위 표시)

1. **[Sprint 0 해소 필수 — gating]** 9 진입점 + 6 스킬(`context-chain`·`deepplan`·`evaluator`·`orchestrator`·`strategic-compact`·`ux-audit`) + `audit-self.md`의 STATE 갱신 call graph 명시적 매핑. 산출: `docs/specs/state-call-graph-v3.md`. **Sprint 0 PASS 없이 Sprint 1 시작 불가.**
2. **[Sprint 0 정책 결정]** Codex 위임 시 registry 갱신 책임 경계. `/nova:auto` → `orchestrator` → 다중 에이전트 구조에서 Codex가 work-item을 자동 추가하는지, orchestrator만 갱신 권한을 가지는지. 산출: `docs/specs/registry-write-authority-v3.md`.
3. **[Sprint 0 해소 필수 — gating]** work-item "스코프" 정의. WI는 단일 sprint에 속하는가, 다중 sprint를 span할 수 있는가? `depends_on` semantics, status 전이 규칙 전체가 이 결정에 의존. **Sprint 0 PASS 없이 Sprint 1 schema 동결 불가.**
4. **[Sprint 0 사전 조사]** 다중 git worktree에서 `.nova/` 디렉토리 공유 여부 확인 (`worktree-setup` 스킬 동작 분석). 공유면 flock 단일 lock, 분리면 worktree별 lock + index.json 머지 정책 필요.
5. **[Sprint 5 PoC]** PoC 프로젝트 3개의 v2→v3 마이그레이션 실제 손실율 측정. 보존율 측정 단위 명시 (Tasks/Risks/Known Gaps **항목 수** 기준, 글자 수 아님 — Hook #8 검증 단위와 일치). dbt manifest 선례상 정형화 수준 낮으면 ≥20% 가능.
6. **[Sprint 3 필수]** registry 렌더링 트리거 정책. (a) 매 세션 시작 (b) 사용자 명시 호출 (c) `registry-write.sh` 직후. Synthesizer는 (c) 권장 — Sprint 3 시작 시 spec 동결.
7. **[Sprint 2 필수]** `.nova/events.jsonl` 이벤트 스트림과 work-item state 일관성 계약. v3 도입 후 양쪽 데이터 계약 (예: `work_item_transitioned` 이벤트와 `index.json` 갱신이 동시에 일어나야 한다는 보장).

---

## Verification Hooks

> Sprint Contract 씨앗 — 이후 `/nova:design` 단계에서 구체화한다.

| # | 검증 항목 | 검증 방법 | 우선순위 |
|---|----------|----------|---------|
| 1 | schema 유효성 (JSON Schema) | `ajv-cli` 또는 `jq` 기반 validator. tests/test-scripts.sh가 모든 `.nova/work-items/*.json` 검증 | **Critical** |
| 2 | id 유일성 + 형식(`WI-NNNN-slug`) 강제 | `jq '.work_items[].id'` 중복 검사 + regex `^WI-\d{4}-[a-z0-9-]+$` | **Critical** |
| 3 | status enum 위반 차단 | `jq '.status'` enum 검증 (5값) — 위반 시 exit 1 | **Critical** |
| 4 | `done` evidence 부재 차단 | `jq 'select(.status=="done") \| .evidence \| has("commit_sha")'` 검증 (중첩 키 접근 필수 — `has("evidence.commit_sha")`는 항상 false 반환하는 버그) | **Critical** |
| 5 | git-tracked 보장 (`.gitignore` 검증) | `git check-ignore .nova/work-items/index.json` 출력 비어야 함 | **Critical** |
| 6 | Evaluator PASS 원자적 전이 | `/nova:run` 시뮬레이션 후 work-item에 `status=done` ∧ `review_required=false` 동시 확인 | **Critical** |
| 7 | 9 진입점 단일 쓰기 경로 강제 | 9 진입점 markdown에 STATE 직접 갱신 코드 부재 + `registry-write.sh` 호출만 grep 검증 | **Critical** |
| 8 | 마이그레이션 보존율 ≥80% (단위: Tasks/Risks/Known Gaps **항목 수**) | PoC 3개 사전/사후 항목 수 카운트 비교 (`grep -c "^\\|" NOVA-STATE.md.v2.bak` vs `jq 'length' .nova/work-items/index.json`) | **Critical** |
| 9 | NOVA-STATE.md marker 영역 보존 | 사용자 marker 외 손편집 → 자동 렌더 후 비교 = 동일 | **Critical** |
| 10 | drift 룰 Hard 9 100% 검출 | `tests/fixtures/drift-cases/`의 9개 fixture (H1~H9) → `/nova:check`가 모두 hard error 보고 | **Critical** |
| 11 | drift 룰 Warn 9 false-positive ≤10% | 실보유 9개 형제 프로젝트 + 본 레포 = 10개 샘플에서 warn 발화율 측정 (Architect 권고: 100개 비현실적, 10개로 현실화) | Nice-to-have |
| 12 | 채번 race 무중복 | 20개 병렬 spawn 시뮬레이션 → WI-NNNN 모두 unique | **Critical** |
| 13 | 1000 work-items 성능 (<1초) | mock 1000개 + `jq` 쿼리 + `/nova:next` 실행 시간 측정 | Nice-to-have |
| 14 | Windows-WSL 호환성 | macOS 환경에서는 수동 검증 불가 — GitHub Actions `windows-latest` CI에 위임. CI 미구축 시 "환경 미보유로 defer" 명시 | Defer (CI 미구축 시) |
| 15 | 본 레포 자체 적용 (Sprint 6에서 검증, Sprint 5는 시연) | Sprint 6 종료 시 `/Users/jay/develop/nova` NOVA-STATE.md = v3 marker + work-items 동작. **PoC 3개 결과 PASS 후 본 레포 적용** (Critic 권고: Sprint 5는 시연, Sprint 6에서 검증) | **Critical** |
| 16 | record-event v3 schema_version 호환 | `.nova/events.jsonl` parser가 v2 + v3 모두 처리 (forgiving reader) | **Critical** |
| 17 | v2 backup 파일 존재 | 마이그레이션 후 `NOVA-STATE.md.v2.bak` 존재 + 원본 보존 | High (Critic 권고 격하: 없어도 마이그레이션은 진행 가능, hard-block 과도) |
| 18 | **STATE 갱신 단일 쓰기 grep 범위** (신규) | 9 진입점 commands/ + 6 스킬 skills/ + audit-self.md 16개 파일 모두 `registry-write.sh` 호출, STATE 직접 갱신 코드 부재 | **Critical** |
| 19 | **idempotent `/nova:setup --upgrade`** (신규) | 이미 v3 bootstrap된 프로젝트에 `--upgrade` 재실행 → `.nova/work-items/` 변경 없음 + schema/README/gitignore만 갱신 | **Critical** |
| 20 | **orphan id 검출** (신규) | 사용자 `git revert` 후 `index.json`에 미존재 파일 참조 → drift H7 룰 발화 | **Critical** |

---

## 한 줄 요약

**v3 = "기계용 단일 진실원(`.nova/work-items/index.json`) + 사람용 자동 투영 cursor(NOVA-STATE.md marker) + 9 진입점 + 7 스킬·커맨드 단일 쓰기 경로(`registry-write.sh`) + Evaluator PASS 원자적 전이 + drift Hard 9 + Warn 9 = 18종 + 4 롤백 시나리오"**. Sprint 0+6 (총 7 sprint), ~9~10주, PoC 3개 → 본 레포 자체 검증(Sprint 6) → 형제 7개 순차 PR. **Plan Critic 12 + Design Critic 20 + Architect Critic 11 = 43 이슈 모두 surgical 해결 → CONDITIONAL GO 3 조건 + 권고 5건 흡수 완료**.

---

## Critic 미해결 항목 (Sprint 진행 중 추가 작업 필요)

> Refiner가 surgical edit으로 처리하지 못한 *시스템적 권고*. Sprint 진행 시 추가 검토 사항.

1. **자기참조 위험 (Critic 종합 평가 §자기참조)**: Sprint 5/6에서 Nova 본 레포를 v3로 자기 적용할 때, Generator(이 Plan을 작성한 컨텍스트)와 Evaluator(자기 적용을 검증할 컨텍스트)가 같은 세션 또는 동일 사용자 본인. Critic 권고대로 PoC 3개(외부 프로젝트) 결과를 본 레포 적용보다 *훨씬 강한 신호*로 취급. Sprint 5 Hook #15는 시연으로만, Hook #15 정식 검증은 Sprint 6 (PoC 결과 반영 후).
2. **사용자 커뮤니케이션 (Critic 이슈 #12)**: Sprint 테이블 "사용자 안내" 열을 *최소한*으로만 반영했음. 실제 운영 시 release notes·`/nova:next` 안내 메시지·CHANGELOG.md·docs/guides 흐름을 별도로 설계 필요. Sprint 6 산출 "사용자 가이드"를 디테일하게 채울 것.
3. **Codex 위임 시 책임 경계 (Unknown #2)**: Sprint 0에서 `docs/specs/registry-write-authority-v3.md`로 결정 — orchestrator만 갱신 권한 가지는 모델이 합리적이나, 다중 에이전트 환경 진화 시 재검토 가능.
