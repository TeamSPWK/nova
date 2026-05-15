# [Design] Work-Item Registry v3 — Nova 플러그인 작업 추적 시스템

> Nova Engineering — CPS Framework
> 작성일: 2026-05-15
> Plan: `docs/plans/work-item-registry-v3.md`
> Verification: (Sprint 5 PoC 후 추가)
> Critic Iterations: 1 (Critical 8 + High 8 + Medium 4 = 20 이슈 surgical edit 완료)

---

## Context (설계 배경)

### Plan 요약

- **핵심 문제**: AI 에이전트가 stale 문서에서 다음 작업을 추론, NOVA-STATE.md가 wiki화·drift, 9 진입점 단일 쓰기 경로 부재.
- **선택한 방안**: 방안 B — 점진 도입 7 sprint (Sprint 0~6, ~9~10주). `.nova/work-items/`(기계용 진실원, 분할 저장 + index.json) + NOVA-STATE.md marker(사람용 자동 투영 cursor).
- **동결된 7개 결정**: schema_version 3.0 / status 5값+보조플래그+원자적 전이 / id `WI-NNNN-slug` / evidence DORA(`commit_sha`) / marker 영역 / `.gitignore` 패턴 / 분할 저장 + index.json 단일 쓰기.

### 설계 원칙

1. **단방향 reconcile (dbt 패턴)**: registry → STATE.md. 역방향 금지.
2. **단일 쓰기 경로**: 9 진입점 + 7 스킬·커맨드 = 16 파일 모두 `scripts/registry-write.sh` 경유. 직접 JSON 편집 금지.
3. **원자적 전이 (Claude/Codex 합의)**: Evaluator PASS = `status=done` + `review_required=false` 동시 적용. 부분 갱신 불가.
4. **Forgiving Reader (Postel 원칙)**: old Nova가 신 schema 만나면 미지 필드 무시하고 진행. backward compat 보장.
5. **마이그레이션 보수성 (Codex 명시)**: `done` 추론 금지. 모든 마이그레이션 항목 기본 `proposed`.
6. **strict 신규 / warn-first 과거**: 신규 데이터는 hard error, 과거 데이터는 warn-only로 채택 저항 최소.
7. **자생적 패턴 흡수**: `swk-ground-control` Active Tree(✅/⬜/🔄) + AO 트랙 → v3 marker 영역 자동 렌더에 정식 흡수.

---

## Problem (설계 과제)

### 기술적 과제

| # | 과제 | 복잡도 | 의존성 |
|---|------|--------|--------|
| 1 | JSON Schema 작성 + ajv-cli/jq 검증 인프라 | 중간 | 없음 |
| 2 | `scripts/registry-write.sh` 단일 쓰기 경로 + flock atomic | 높음 | 과제#1 |
| 3 | `scripts/registry-render-state.sh` marker 영역 자동 렌더 | 높음 | 과제#2 |
| 4 | 9 진입점 + 7 스킬 STATE 직접 갱신 코드 제거 + registry-write 호출 | 높음 | 과제#2 |
| 5 | `record-event.sh` schema_version 2→3 + 신규 이벤트 3종 | 중간 | 과제#1 |
| 6 | `migrate-nova-state.sh` v2→v3 분기 (Tasks 표 → work-item 추론) | 높음 | 과제#1, #2 |
| 7 | drift 룰 Hard 9 + Warn 9 = 18종 + severity tier + dismissed 메커니즘 | 중간 | 과제#2, #5 |
| 8 | `/nova:next` registry-first 알고리즘 + fallback | 중간 | 과제#2 |
| 9 | 채번 race 처리 (flock + UUID fallback + reindex) | 높음 | 과제#2 |
| 10 | marker 영역 손편집 가드 (`--no-verify` 우회 사후 검출 포함) | 중간 | 과제#3, #7 |
| 11 | 다중 worktree 동시 갱신 정책 (Sprint 0 사전 조사 → 결정) | 중간 | Sprint 0 |
| 12 | `/nova:setup --upgrade` idempotent + 기존 `.gitignore` 진단 | 중간 | 과제#1 |
| 13 | 마이그레이션 보존율 측정 (항목 수 카운트) | 낮음 | 과제#6 |
| 14 | drift fixture 6 인위적 케이스 생성 | 낮음 | 과제#7 |

### 기존 시스템과의 접점

- **`hooks/record-event.sh`** (11타입 JSONL, schema_version 2) → 3타입 추가 + schema_version 3 확장
- **`scripts/migrate-nova-state.sh`** (v1→v2 graceful fallback) → v2→v3 분기 추가, multi-hop 지원
- **`docs/templates/nova-state.md`** (v2 템플릿) → marker 영역 + 자동 렌더 placeholder 추가
- **9 commands + 7 skills** = 16 파일 (STATE 갱신 수행) → `registry-write.sh` 호출로 일관 변경
- **`commands/setup.md`** (32항목 5 Pillar) → work-items 항목 1개 추가 + idempotent --upgrade
- **`commands/next.md`** (free-text 추론) → registry-first 알고리즘
- **`commands/check.md`** → drift 룰 Hard 9 + Warn 9 = 18종 통합
- **`commands/status.md`** (HTML 대시보드) → registry 렌더링 추가
- **`tests/test-scripts.sh`** → Verification Hook 20건 + drift fixture 6건

### 호환성 고려사항

- macOS는 `flock` 미기본 → `mkdir` atomic directory fallback (각 work-item ID 단위 lock dir).
- Windows-WSL은 GitHub Actions windows-latest CI에 위임 (사용자 macOS 환경에서는 수동 검증 defer).
- 한국어 slug: id regex `^WI-\d{4}-[a-z0-9가-힣-]+$` (orchestrator/deepplan SKILL slug 규칙 재사용).
- v2 STATE 보유 프로젝트(swk-ground-control)는 Active Tree 항목을 work-item으로 매핑, v1(planreview)은 Tasks 표를 추론.

---

## Solution (설계 상세)

### 아키텍처

```
사용자 프로젝트 루트
├── NOVA-STATE.md                       # 사람용 cursor (50줄, marker 외 손편집 보존)
│   <!-- nova:registry-rendered:start -->
│   ... (자동 렌더 영역: Active Tree, Recent Activity)
│   <!-- nova:registry-rendered:end -->
│
├── .nova/                               # Nova 메타 디렉토리
│   ├── README.md                        # "DO NOT EDIT" + 정책 안내
│   ├── work-items/                      # ← git-tracked (registry 진실원)
│   │   ├── index.json                   # 경량 매니페스트 (단일 쓰기 경로)
│   │   ├── WI-0001-foo-feature.json     # 개별 work-item
│   │   ├── WI-0002-bar-fix.json
│   │   └── .lock/                       # mkdir atomic lock dir (커밋 제외)
│   ├── schema/                          # ← git-tracked (JSON Schema)
│   │   ├── work-item.schema.json
│   │   ├── index.schema.json
│   │   └── event-v3.schema.json
│   ├── events.jsonl                     # ← git-ignored (기계용 KPI 이벤트)
│   ├── local/                           # ← git-ignored (사용자 로컬)
│   └── tmp/                             # ← git-ignored (임시)
│
└── docs/plans/{slug}.md                 # plan frontmatter에 work_item_ids 참조

Nova 본 레포 (이 설계 작업 위치)
├── scripts/registry-write.sh            # 단일 쓰기 경로 (CRUD + transition)
├── scripts/registry-render-state.sh     # marker 영역 자동 렌더
├── scripts/registry-drift-check.sh      # Hard 9 + Warn 9 = 18종
├── scripts/reindex-work-items.sh        # UUID fallback 후 재번호화
├── hooks/record-event.sh                # schema_version 3 확장
├── commands/{plan,design,...}.md        # 16 파일 → registry-write 호출
└── tests/fixtures/drift-cases/          # 인위적 drift 6 fixture
```

### 데이터 모델

#### work-item JSON (`.nova/work-items/WI-NNNN-slug.json`)

```jsonc
{
  "schema_version": "3.0",
  "id": "WI-0042-add-search-filter",      // ^WI-\d{4}-[a-z0-9가-힣-]+$
  "title": "검색 필터 추가",
  "status": "active",                       // proposed|active|blocked|done|superseded
  "review_required": false,                 // bool — Evaluator 게이트 대기 신호
  "archived_at": null,                      // ISO 8601 timestamp | null
  "priority": "high",                       // low|medium|high|critical
  "depends_on": ["WI-0040-database-index"], // 다른 WI id 배열
  "source_docs": [
    "docs/plans/search-redesign.md"
  ],
  "evidence": {
    "commit_sha": ["abc123def"],            // done 시 필수, 배열(다중 커밋 허용)
    "test_output": "tests/test-search.sh",  // optional
    "files_changed": ["src/search.ts"],     // optional
    "pr_url": null                          // optional
  },
  "created_at": "2026-05-15T10:00:00Z",
  "updated_at": "2026-05-15T11:30:00Z",
  "owner": "jay",                           // optional
  "notes": "",                              // optional, free-text (안정 계약 X)
  "superseded_by": null,                    // string id | null
  "blocked_reason": null,                   // status=blocked일 때 필수
  "last_verified_at": "2026-05-15T11:30:00Z" // /nova:review·check PASS 시 갱신
}
```

#### index.json 매니페스트 (`.nova/work-items/index.json`)

```jsonc
{
  "schema_version": "3.0",
  "next_seq": 43,                           // 다음 채번 시드 (race-safe atomic increment)
  "work_items": [
    {
      "id": "WI-0042-add-search-filter",
      "status": "active",
      "review_required": false,
      "priority": "high",
      "updated_at": "2026-05-15T11:30:00Z"
    }
    // ... (경량 — 4~5 필드만)
  ],
  "generated_at": "2026-05-15T11:30:00Z"
}
```

**경량 매니페스트 정당화**: `/nova:next`가 후보 선정 시 `priority + status + review_required + updated_at`만 필요. 상세는 개별 파일 lazy load.

#### Plan 문서 frontmatter (`docs/plans/{slug}.md`)

```yaml
---
title: "Search Redesign"
work_items: [WI-0042, WI-0043, WI-0044]    # 역참조
superseded_by: null
last_verified: 2026-05-15
status: active                              # 미정형 plan은 신규 frontmatter 추가
---
```

#### 신규 record-event.sh 이벤트 (schema_version 3)

```jsonc
// work_item_created
{"event_type":"work_item_created","schema_version":"3.0","ts":"...","wi_id":"WI-0042","status":"proposed"}

// work_item_transitioned
{"event_type":"work_item_transitioned","schema_version":"3.0","ts":"...","wi_id":"WI-0042",
 "from":"active","to":"done","trigger":"evaluator_pass","actor":"/nova:run"}

// registry_rendered
{"event_type":"registry_rendered","schema_version":"3.0","ts":"...","render_path":"NOVA-STATE.md",
 "items_in_view":12,"trigger":"post_write"}
```

### 데이터 계약 (Data Contract)

> 구현자가 잘못된 가정을 하지 않도록, 모든 필드 단위·포맷·변환 규칙을 명시한다.

| 필드 | 타입 | 단위/포맷 | 변환 규칙 | 비고 |
|------|------|----------|----------|------|
| `schema_version` | string | semver string (`"3.0"`·`"3.1"`·`"3.10"`) | **semver 숫자 비교** (Critic #10 lexicographic 오류 방지): `split(".") \| map(tonumber)` 후 배열 비교. major 차이 = 호환 안 됨, minor 차이 = forgiving reader. jq 구현: `($a \| split(".") \| map(tonumber)) as $av \| ($b \| split(".") \| map(tonumber)) as $bv \| if $av[0] != $bv[0] then "incompatible" elif $av[1] < $bv[1] then "old-reader" else "ok" end` | hard-coded 상수, 갱신 시 migrate 필수 |
| `id` | string | **정규 형식** `^WI-\d{4}-[a-z0-9가-힣-]+$` **OR UUID fallback** `^WI-[a-f0-9]{8}-[a-z0-9가-힣-]+$` (Critic #20: schema에 `oneOf` 두 패턴 명시) | slug 생성: 공백→`-`, 한글 유지, 특수문자 제거 (orchestrator/deepplan 규칙 재사용). UUID fallback id는 H1에서 *허용되나* W6(신규 warn)으로 "reindex 권고" 발화 | 4자리 순차 (`0001`~`9999`), 초과 시 `_extend-id-format-v3.1` 마이그레이션. UUID는 lock 획득 실패 시만 |
| `title` | string | UTF-8, 최대 200자 | 없음 | 자유 텍스트 (안정 계약 X) |
| `status` | enum | `"proposed"\|"active"\|"blocked"\|"done"\|"superseded"` | 전이 규칙 §전이도 참조 | 5값 동결 (절대 늘리지 않음 — GPT 강조) |
| `review_required` | bool | `true`/`false` | Evaluator PASS → `false`, /nova:review·check → `true` (원자적 전이) | status=done 시 항상 false (불변식) |
| `archived_at` | string\|null | ISO 8601 UTC (`"2026-05-15T10:00:00Z"`) | **`transition <id> superseded` 호출 시 자동 set** (Critic #9: 책임 위치 명시). `done→superseded` 전이도 마찬가지로 archived_at set. status=done은 archived_at 무관 (null 유지) | timestamp = 상태가 아닌 **사건 기록**. 불변식: `status=superseded ⟹ archived_at non-null` |
| `priority` | enum | `"low"\|"medium"\|"high"\|"critical"` | 없음 | /nova:next 정렬 키 (critical > high > medium > low) |
| `depends_on` | string[] | WI id 배열 | depends_on에 미존재 id → drift Hard 룰 발화 | 순환 의존 시 drift 검출 (Sprint 4) |
| `source_docs` | string[] | repo-relative paths | 절대경로 금지 (이식성), `./docs/...` 같은 prefix 금지 | 존재하지 않는 path → drift Warn 룰 |
| `evidence.commit_sha` | string[] | git SHA (40자 hex 또는 단축형 7자+) | done 전이 시 최소 1개 필수, 비어있으면 hard error | DORA 표준 1차 키 |
| `evidence.test_output` | string\|null | repo-relative path 또는 jsonl entry id | 없음 | optional, /nova:run 자동 set 가능 |
| `evidence.files_changed` | string[]\|null | repo-relative paths | `git diff --name-only` 결과 | optional, /nova:run 자동 set 가능 |
| `evidence.pr_url` | string\|null | https URL | github.com 도메인 검증 | optional |
| `created_at` | string | ISO 8601 UTC | `new Date().toISOString()`, 갱신 불가 (immutable) | record-event ts와 일치 |
| `updated_at` | string | ISO 8601 UTC | 모든 갱신 시 자동 set | index.json `updated_at`과 sync 필수 |
| `owner` | string\|null | 문자열 | 없음 | optional, 다중 협업 환경 |
| `notes` | string | UTF-8 free-text | 없음 | optional, 안정 계약의 핵심 X |
| `superseded_by` | string\|null | WI id | status=superseded 시 권장 (warn-only) | enum과 분리 (MADR 합침 패턴 회피) |
| `blocked_reason` | string\|null | UTF-8 free-text | status=blocked 시 필수 (hard error) | 빈 문자열도 위반 |
| `last_verified_at` | string\|null | ISO 8601 UTC | /nova:review·check PASS 시 자동 set | **status=active만** 30일+ stale 시 W4 발화 (Critic #11 통일: proposed·blocked는 검증 대상 아님, done은 archived). drift 룰 표 W4와 동기화 |
| `index.next_seq` | integer | 양의 정수 (≥1) | atomic increment via flock or mkdir lock | race-safe 필수 |

#### 마이그레이션 매핑 (v2 → v3)

| v2 STATE 영역 | v3 work-item 매핑 | 추론 규칙 |
|--------------|------------------|----------|
| Current.Goal | (매핑 안 함 — Plan/Design 참조로 처리) | drop |
| Tasks 표 (status: todo/doing/done) | work-item 1개씩 | **모두 `status=proposed`로 변환** (done 추론 금지 — Codex 명시. **"done 추론 금지" 정의**: STATE 텍스트 컬럼의 "done" *문자열*을 보고 done 변환 금지. evidence 기반 확인(commit_sha grep 등)은 *추론*이 아니라 *증거 확인*이라 허용 — Architect #10 명시). title=Task 컬럼, notes=Note 컬럼, priority="medium" 기본 |
| Recently Done 3개 (todo→done 이력) | work-item 1개씩 | **commit_sha 추출 가능 시만 `status=done`** (STATE 텍스트에서 `[a-f0-9]{7,40}` 패턴 grep). 추출 실패 시 `status=proposed` + `notes="이전 STATE에서 done이었음 — evidence 확인 필요"`. **보존율 분자 = 변환된 WI 파일 수 (status 무관)**, 분모 = 동적 카운트(Tasks+Recently Done+Known Gaps+Active Tree 모든 항목). Critic #13: `29` 같은 하드코딩 없음. |
| Known Risks 표 | (work-item 매핑 안 함 — `docs/specs/risks-v2.md`로 보존) | **migrate-nova-state.sh 자동 복사** (Critic #14: 책임 명시) + 파일 상단에 `<!-- 사용자 검수 필요 — v2 자동 추출, 정확성 보장 안 됨 -->` 마커. Sprint 3 Done 조건에 포함. |
| Known Gaps 표 | work-item (`status=proposed`, `priority=low`) | gap 1줄 → work-item 1개 |
| Last Activity (5건) | (매핑 안 함 — record-event.sh로 backfill 불가 시 drop) | drop |
| Refs | (매핑 안 함 — source_docs에 반영) | merge into source_docs |
| Active Tree (swk-ground-control 등 v2.5) | work-item (`status=active`, `priority=high`) | ✅→done(단 commit_sha 있을 때만), ⬜→proposed, 🔄→active. tree 위치는 notes에 기록 |

**보존율 측정 (Hook #8, Critic #13 + Architect 권고 3 라벨 분리)**:

두 지표로 분리 보고 — "100% 보존"의 모호함을 해소:

```bash
# (a) 항목 수 보존율 (structure-level) — 임계 ≥0.8 (필수)
numerator_struct=$(ls .nova/work-items/WI-*.json 2>/dev/null | wc -l)
denominator=$(bash scripts/count-v2-items.sh NOVA-STATE.md.v2.bak)
python3 -c "print($numerator_struct / $denominator >= 0.8)"

# (b) 상태 보존율 (status-level) — 참고지표 (commit_sha 보유율, 정보 손실 정량화)
done_in_v2=$(grep -cE "^\| .* \| done \|" NOVA-STATE.md.v2.bak)   # v2 STATE done 행 수
done_in_v3=$(jq -r '.work_items[] | select(.status=="done")' .nova/work-items/index.json | wc -l)
python3 -c "print(f'status preservation: {$done_in_v3}/{$done_in_v2}')"  # 정보 보고만, 임계 없음
```

**라벨 정책 (Sprint 6 사용자 가이드 명시 필수)**:
- "보존율 100%" = *항목 수* 보존이며 *상태/정보* 보존 아님
- planreview/nova-landing 같이 commit_sha 부재 프로젝트는 (a)=100%, (b)=0% — 모두 proposed로 강등은 *정상*
- (b) 낮음 = 정보 손실 아닌 *DORA 표준 부재* — 사용자가 후속 evidence 채우면 됨

`scripts/count-v2-items.sh` 명세 (Sprint 5 신규):
- v2 STATE의 Tasks 표 본문 행 수 (헤더·구분선 제외, `awk -F'|' 'NF>3 && !/^[\s|]*[-]+/'` 패턴)
- + Recently Done 표 본문 행 수
- + Known Gaps 표 본문 행 수
- + Active Tree의 ✅⬜🔄🚫 항목 수 (`grep -cE "^- (✅|⬜|🔄|🚫)"`)
- Last Activity는 카운트 제외 (마이그레이션에서 drop)

#### v2→v3 마이그레이션 추가 규칙 (D 단계 PoC 결과 흡수)

D 단계 PoC(swk-ground-control 9항목 / planreview 6항목 / nova-landing 6항목 모두 100% 보존)에서 발견된 5건 명시:

| # | 영역 | 규칙 | 예외/근거 |
|---|------|------|----------|
| 1 | `priority` 추론 | v2/v1 STATE에 priority 필드 없음 → **모두 `medium` 기본** | active/🔄 상태인 항목만 `high` 휴리스틱 허용 (선택, default off) |
| 2 | `blocked_reason` 추출 | 🚫 항목 발견 시 *그 항목 자체 줄 + 직후 줄*에서 자유 텍스트 추출. 부재 시 `"미정의 — 사용자 입력 필요"` 기본값 | 🚫 항목 0건인 프로젝트(PoC 3개 중 swk-gc)는 미검증 — Sprint 5 추가 fixture 필요 |
| 3 | `depends_on` 추론 | **절대 추론 금지** — v2/v1 STATE에 의존성 표현 없음. 모두 `[]` 빈 배열 | 사용자 post-migration 수동 입력 |
| 4 | `source_docs` 자동 추가 | **자동 추가 금지** — STATE Refs는 프로젝트 전체 참고용, work-item별 매핑 불가. 모두 `[]` 빈 배열 | 사용자 post-migration 수동 입력 (Sprint 6 가이드 안내) |
| 5 | `commit_sha` 부재 시 처리 | Recently Done에 commit SHA 패턴(`[a-f0-9]{7,40}`) **추출 실패 시 → status=`proposed`로 강등** + `notes`에 "이전 STATE에서 done이었음" 기록 | done 추론 절대 금지 (Codex 명시). nova-landing·planreview는 commit_sha 부재율 100% → 모두 proposed |

**PoC 검증 결과** (D 단계):

| 프로젝트 | 마이그레이션 대상 | 생성 WI | status 분포 (추정) | 보존율 |
|---------|-----------------|--------|------------------|--------|
| swk-ground-control (v2.5 Active Tree) | 9 (✅8+⬜1) | 9 | done=8 (commit_sha 추출 OK), proposed=1 | **100%** ✅ |
| planreview (v1) | 6 (In Progress 1+RD 3+KG 2) | 6 | proposed=6 (commit_sha 모두 부재) | **100%** ✅ |
| nova-landing (v1, stale 39일) | 6 (Tasks 3+RD 1+KG 2) | 6 | proposed=6 | **100%** ✅ |

→ **Sprint 1 schema 동결 GO**. 필드 추가 불필요. 위 5개 마이그레이션 규칙만 Sprint 3 migrate-state v2→v3 분기에 반영.

### API 설계 (스크립트 인터페이스)

#### `scripts/registry-write.sh` — 단일 쓰기 경로 (Critic #3·#4 반영: exit code + stdout 계약 모든 명령에 명시)

```bash
# === create ===
bash scripts/registry-write.sh create <title> [--priority=low|medium|high|critical] [--source-doc=PATH]
  # stdout: WI-NNNN-slug (성공 시) | stderr: 에러 메시지
  # exit 0: 성공 (정규 id 채번)
  # exit 1: lock 획득 실패 → UUID fallback id 출력 + W6 발화 권고
  # exit 2: schema 위반 (잘못된 priority 등) 또는 인자 부족
  # 내부: acquire_lock → index.next_seq++ → WI 파일 생성 → index 갱신 → release_lock → (lock 외부) record-event work_item_created + render-state.sh

# === transition ===
bash scripts/registry-write.sh transition <wi-id> <new-status> [--evidence-commit=SHA] [--blocked-reason=TEXT]
  # stdout: 갱신된 work-item id (성공 시) | stderr: 에러
  # exit 0: 성공
  # exit 2: status=done인데 --evidence-commit 누락 / status=blocked인데 --blocked-reason 누락 / 불변식 위반
  # 자동 처리: status=done → review_required=false + last_verified_at set + commit_sha 추가
  #            status=superseded → archived_at set
  #            status=blocked → blocked_reason 저장

# === update ===
bash scripts/registry-write.sh update <wi-id> <field>=<value> [<field>=<value> ...]
  # stdout: 갱신된 work-item id (성공 시)
  # exit 0: 성공
  # exit 2: immutable 필드(id, created_at, schema_version) 변경 시도 / 잘못된 필드명

# === evaluator-pass ===
bash scripts/registry-write.sh evaluator-pass <wi-id> --commit-sha=SHA [--test-output=PATH] [--files=PATH1,PATH2]
  # stdout: "PASS WI-NNNN-slug" (성공 시)
  # exit 0: 성공 (status=done + review_required=false + evidence 원자 set)
  # exit 2: --commit-sha 누락 / WI 미존재 / 이미 done
  # **의미**: `transition done --evidence-commit=SHA`의 sugar 명령. /nova:run·auto가 호출

# === require-review ===
bash scripts/registry-write.sh require-review <wi-id>
  # stdout: "REVIEW_REQUIRED WI-NNNN-slug" (성공 시)
  # exit 0: 성공 (review_required=true set)
  # exit 2: WI 미존재 / 이미 review_required=true
  # **의미**: /nova:review·check·ux-audit·audit-self의 *메인 컨텍스트*가 호출. status는 변경 안 함, 플래그만 set.
  # **호출 권한**: sub-agent(evaluator·ux-audit skill 등) 직접 호출 금지. sub-agent는 권고 stdout만 → 메인이 받아 호출.
  # (Sprint 0 `docs/specs/registry-write-authority-v3.md` 결정)
```

#### `scripts/registry-render-state.sh` — 자동 렌더

```bash
bash scripts/registry-render-state.sh [--dry-run] [--state-file=NOVA-STATE.md]
  # marker 영역 안쪽만 갱신
  # 렌더 내용: Active Tree (status=active|proposed top 10) + Recent Activity (last 7 days work_item_transitioned events)
  # marker 외 영역 = byte-level 일치 보존
  # dry-run: stdout에 diff만 출력, 파일 수정 X
```

#### `scripts/registry-drift-check.sh` — Hard 9 + Warn 9 = 18종

```bash
bash scripts/registry-drift-check.sh [--severity=critical|warning|all] [--exclude-dismissed]
  # /nova:check가 내부 호출
  # exit code: 0=PASS, 1=Warn only, 2=Hard error
  # 출력: jsonl 진단 (각 줄에 rule_id, severity, wi_id?, suggestion)
```

#### `scripts/reindex-work-items.sh` — UUID fallback 회수

```bash
bash scripts/reindex-work-items.sh [--dry-run]
  # WI-{UUID} 형식 work-item을 WI-NNNN 순차 형식으로 재번호화
  # depends_on·source_docs·superseded_by 자동 갱신
  # dry-run: 변환 매핑만 출력
```

### 핵심 로직

#### 1. 채번 (Atomic Sequence) — Critic #2·#12 반영

```bash
# 우선순위: flock(있으면) → mkdir atomic + PID 검증 → UUID fallback
# Critic #2 SIGKILL stale lock 대응: lock dir 내 PID 파일 + kill -0 검증
# Critic #12 lock 범위: index.json 갱신만 lock 내부, render-state/record-event는 lock 외부

LOCK_DIR=".nova/work-items/.lock"
LOCK_FILE="$LOCK_DIR/index.lock"      # flock target
LOCK_HOLD="$LOCK_DIR/index.lock.d"    # mkdir target
LOCK_PID="$LOCK_HOLD/pid"             # holder PID

acquire_lock() {
  mkdir -p "$LOCK_DIR" 2>/dev/null
  # 분기 1: flock 사용 가능
  if command -v flock >/dev/null 2>&1; then
    exec 200>"$LOCK_FILE"
    flock -x -w 5 200 && return 0
    return 1
  fi
  # 분기 2: mkdir atomic + stale PID 검증
  local attempts=0
  while [ $attempts -lt 50 ]; do
    if mkdir "$LOCK_HOLD" 2>/dev/null; then
      echo $$ > "$LOCK_PID"
      return 0
    fi
    # stale lock 검출: PID 살아있는지 확인
    if [ -f "$LOCK_PID" ]; then
      local holder=$(cat "$LOCK_PID" 2>/dev/null)
      if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
        # holder 죽음 → 강제 정리 후 재시도
        rm -rf "$LOCK_HOLD"
        continue
      fi
    fi
    attempts=$((attempts+1))
    sleep 0.1
  done
  return 1
}

release_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 200>&-  # fd 닫기
  else
    rm -rf "$LOCK_HOLD"
  fi
}

assign_id() {
  local slug=$1
  if ! acquire_lock; then
    # 50회 retry 실패 → UUID fallback + stderr 경고
    echo "WARN: lock 획득 실패 — UUID fallback. reindex 권장: bash scripts/reindex-work-items.sh" >&2
    echo "WI-$(uuidgen | tr A-Z a-z | cut -c1-8)-$slug"
    return 0
  fi
  local next=$(jq -r '.next_seq' .nova/work-items/index.json)
  local id=$(printf "WI-%04d-%s" "$next" "$slug")
  jq ".next_seq = $((next+1))" .nova/work-items/index.json > .nova/work-items/.tmp \
    && mv .nova/work-items/.tmp .nova/work-items/index.json
  release_lock
  echo "$id"
}
```

**lock 범위 명시**: `acquire_lock`은 index.json 갱신 직전, `release_lock`은 직후. `record-event.sh`·`registry-render-state.sh` 호출은 **lock 외부**(이들이 느리더라도 다른 호출자를 막지 않음).

#### 2. 원자적 전이 (Evaluator PASS) — Critic #1·#3·#9 반영

```bash
# Critic #1: 두 파일 갱신 사이 SIGINT/SIGKILL 취약 → .pending-transition 마커로 부분 적용 감지
# Critic #3: transition done도 evaluator_pass와 동일하게 review_required=false 동시 set
# Critic #9: status=superseded 시 archived_at 자동 set 책임을 transition에 귀속
# Critic #12: render-state.sh와 record-event.sh는 lock 외부 호출

evaluator_pass() {
  local wi=$1 sha=$2
  local ts=$(date -u +%FT%TZ)
  local pending=".nova/work-items/.pending-transition-$wi"
  acquire_lock || return 1
  # 1) 부분 적용 감지 마커: 두 파일 갱신 시작 전 기록
  echo "{\"wi\":\"$wi\",\"target\":\"done\",\"ts\":\"$ts\"}" > "$pending"
  # 2) WI 파일 갱신
  jq --arg sha "$sha" --arg ts "$ts" '
    .status = "done" | .review_required = false |
    .evidence.commit_sha += [$sha] |
    .updated_at = $ts | .last_verified_at = $ts
  ' ".nova/work-items/$wi.json" > ".nova/work-items/.tmp-$wi" \
    && mv ".nova/work-items/.tmp-$wi" ".nova/work-items/$wi.json"
  # 3) index.json 갱신 (한 transaction)
  jq --arg id "$wi" --arg ts "$ts" '
    (.work_items[] | select(.id == $id)) |= (
      .status = "done" | .review_required = false | .updated_at = $ts
    )
  ' .nova/work-items/index.json > .nova/work-items/.tmp-index \
    && mv .nova/work-items/.tmp-index .nova/work-items/index.json
  # 4) 부분 적용 마커 제거 (양쪽 갱신 완료)
  rm -f "$pending"
  release_lock
  # 5) lock 외부에서 이벤트·렌더
  bash hooks/record-event.sh work_item_transitioned "$(jq -cn --arg id "$wi" \
    '{wi_id:$id, from:"active", to:"done", trigger:"evaluator_pass"}')"
  bash scripts/registry-render-state.sh
}

transition() {
  local wi=$1 new_status=$2 sha=${3:-}
  local ts=$(date -u +%FT%TZ)
  acquire_lock || return 1
  # status=done 강제 invariant: review_required=false + evidence.commit_sha 필수
  if [ "$new_status" = "done" ]; then
    [ -z "$sha" ] && { release_lock; echo "ERR: done requires --evidence-commit=SHA" >&2; return 2; }
  fi
  # status=blocked 강제 invariant: blocked_reason 필수 (caller가 update로 별도 set)
  # status=superseded 강제 invariant: archived_at 자동 set
  local jq_expr=".status = \"$new_status\" | .updated_at = \"$ts\""
  case "$new_status" in
    done) jq_expr+=" | .review_required = false | .evidence.commit_sha += [\"$sha\"] | .last_verified_at = \"$ts\"" ;;
    superseded) jq_expr+=" | .archived_at = \"$ts\"" ;;
  esac
  jq "$jq_expr" ".nova/work-items/$wi.json" > ".nova/work-items/.tmp-$wi" \
    && mv ".nova/work-items/.tmp-$wi" ".nova/work-items/$wi.json"
  jq --arg id "$wi" --arg ts "$ts" --arg s "$new_status" '
    (.work_items[] | select(.id == $id)) |= (
      .status = $s | .updated_at = $ts |
      (if $s == "done" then .review_required = false else . end)
    )
  ' .nova/work-items/index.json > .nova/work-items/.tmp-index \
    && mv .nova/work-items/.tmp-index .nova/work-items/index.json
  release_lock
  bash hooks/record-event.sh work_item_transitioned "$(jq -cn --arg id "$wi" --arg s "$new_status" \
    '{wi_id:$id, to:$s, trigger:"transition"}')"
  bash scripts/registry-render-state.sh
}

# 부분 적용 복구 (세션 시작 시 또는 /nova:check에서 호출)
recover_pending_transitions() {
  for p in .nova/work-items/.pending-transition-*; do
    [ -f "$p" ] || continue
    local wi=$(jq -r '.wi' "$p")
    local target=$(jq -r '.target' "$p")
    # WI 파일과 index.json status 불일치 → drift Hard 룰 H8(신규)로 보고
    local wi_status=$(jq -r '.status' ".nova/work-items/$wi.json" 2>/dev/null)
    local idx_status=$(jq -r ".work_items[] | select(.id==\"$wi\") | .status" .nova/work-items/index.json)
    if [ "$wi_status" != "$idx_status" ]; then
      echo "DRIFT H8: WI $wi 부분 전이 감지 — wi=$wi_status, index=$idx_status. 수동 복구 필요" >&2
    fi
    # 정상이면 마커 제거
    [ "$wi_status" = "$target" ] && [ "$idx_status" = "$target" ] && rm -f "$p"
  done
}
```

**불변식 강제 위치 매트릭스**:
| 불변식 | 강제 위치 |
|---|---|
| `status=done ⟹ review_required=false` | `evaluator_pass`, `transition done` 둘 다 동시 set |
| `status=done ⟹ evidence.commit_sha ≥ 1` | `transition done`이 `--evidence-commit` 없으면 exit 2 거부 |
| `status=blocked ⟹ blocked_reason non-empty` | `transition blocked` 시 caller가 `update blocked_reason=...` 먼저 호출 필수 (drift H9 신규로 검증) |
| `status=superseded ⟹ archived_at non-null` | `transition superseded`이 자동 set |

#### 3. status 전이 도

```
  proposed ──> active ──> done
     │            │         │
     │            └─> blocked (blocked_reason 필수)
     │                  │
     │                  └─> active (블로커 해소)
     │
     └─> superseded (superseded_by 권장)

  done ──> superseded (재정의된 경우)
  any ──> superseded (대체 작업 발생)
```

**불변식**:
- `status=done` ⟹ `review_required=false`
- `status=done` ⟹ `evidence.commit_sha` 1개 이상
- `status=blocked` ⟹ `blocked_reason` non-empty
- `status=superseded` ⟹ `archived_at` non-null

#### 4. drift 룰 (Hard 9 + Warn 9 = 18종, 단일 출처화) — Critic #15·#16·#17·#18 + Architect 권고 1·#8 반영

> **Warn 룰 단일 출처화**: 이전에 에러처리표·scope spec·authority spec에 분산됐던 W5~W9를 모두 이 표에 흡수. 구현자는 이 표 하나만 보면 됨.

**실행 순서 강제**: H1 → H2 → H3 → H4 → H5 → H6 → H7 → H8 → H9. H1 실패 시 H2~H9 SKIP (Critic #18 unhandled jq 실패 방어).

| # | severity | 룰 | 검출 명령 (exit 패턴: 0=PASS, 1=Warn 검출, 2=Hard 검출) |
|---|---------|-----|----------|
| H1 | Hard | schema 유효성 위반 | **ajv 우선**: `ajv validate -s .nova/schema/work-item.schema.json -d ".nova/work-items/WI-*.json" 2>&1`. **ajv 부재 시 jq fallback (제한적)**: status enum 5값 + review_required bool + evidence.commit_sha array + id regex 핵심 3+1 검증 (`jq -e '.status \| IN("proposed","active","blocked","done","superseded")'` + `.review_required \| type == "boolean"` + `.evidence.commit_sha \| type == "array"` + `.id \| test("^WI-(\\\\d{4}\|[a-f0-9]{8})-.+$")`). fallback 한계는 stderr로 명시. |
| H2 | Hard | id 유일성 위반 | `jq empty .nova/work-items/index.json \|\| exit 2; dup=$(jq -r '.work_items[].id' .nova/work-items/index.json \| sort \| uniq -d); [ -n "$dup" ] && exit 2` |
| H3 | Hard | status enum 위반 | `for f in .nova/work-items/WI-*.json; do jq -e '.status \| IN("proposed","active","blocked","done","superseded")' "$f" >/dev/null \|\| { echo "$f"; exit 2; }; done` |
| H4 | Hard | gitignore 제외 보장 실패 (Critic #17 명확화) | `git check-ignore .nova/work-items/index.json >/dev/null 2>&1 && exit 2`. "git-tracked" = "gitignore 제외" 의미. *커밋 이력*은 별도 룰 H4b로 분리: `git log --oneline -- .nova/work-items/index.json \| head -1` 비어있고 staged도 아니면 W5(신규 warn) 발화 |
| H5 | Hard | depends_on 미존재 id | `for f in .nova/work-items/WI-*.json; do for dep in $(jq -r '.depends_on[]?' "$f"); do [ -f ".nova/work-items/$dep.json" ] \|\| { echo "$f depends_on $dep missing"; exit 2; }; done; done` |
| H6 | Hard | done evidence 부재 (Critic #16 exit code 패턴 정정) | `viol=$(for f in .nova/work-items/WI-*.json; do jq -e 'select(.status=="done") \| (.evidence.commit_sha \| length == 0)' "$f" 2>/dev/null && echo "$f"; done); [ -n "$viol" ] && exit 2`. 핵심: `[... | select() | ...] | length > 0` 패턴으로 "위반 있음 = 검출"을 일관되게 표현 |
| H7 | Hard | orphan id (index↔파일 불일치) | `comm -23 <(jq -r '.work_items[].id' .nova/work-items/index.json \| sort) <(ls .nova/work-items/WI-*.json 2>/dev/null \| sed 's\|.*/\\\|\|;s/\\.json$//' \| sort) \| grep -q . && exit 2` |
| **H8** (신규) | Hard | 부분 전이 마커 잔류 (Critic #1) | `ls .nova/work-items/.pending-transition-* 2>/dev/null \| grep -q . && exit 2` — recover_pending_transitions로 처리 후 잔류 시 수동 복구 |
| **H9** (신규) | Hard | status=blocked인데 blocked_reason 비어있음 (불변식) | `for f in .nova/work-items/WI-*.json; do jq -e 'select(.status=="blocked") \| (.blocked_reason \| (. == null or . == ""))' "$f" 2>/dev/null && exit 2; done` |
| W1 | Warn | stale STATE 7일+ | `jq '.work_items \| max_by(.updated_at) \| .updated_at' .nova/work-items/index.json` → ts 비교 | Sprint 4 |
| W2 | Warn | plan frontmatter 누락 | `find docs/plans -name '*.md' \| xargs grep -L '^---' 2>/dev/null` | Sprint 4 |
| W3 | Warn | unreferenced plan (고아) | plan에서 work-item source_docs 역참조 없음 | Sprint 4 |
| W4 | Warn | last_verified_at 30일+ stale (Critic #11: **status=active만 적용** — proposed/blocked는 검증 대상 아님) | `for f in .nova/work-items/WI-*.json; do jq -e 'select(.status=="active") \| ((now - (.last_verified_at \| fromdateiso8601)) > 2592000)' "$f"; done` | Sprint 4 |
| W5 (신규, Critic #17) | Warn | git 커밋 이력 부재 | index.json이 ignore 제외인데 `git log --oneline -- .nova/work-items/index.json` 비어있음 | Sprint 4 |
| W6 (신규, Architect 권고 1) | Warn | UUID fallback id 발견 — reindex 권고 | `jq -r '.work_items[].id' index.json \| grep -E '^WI-[a-f0-9]{8}-'` non-empty | Sprint 4 |
| W7 (신규, scope spec §1 §결정 5) | Warn | `source_docs[0]` plan 미매핑 (sprint 소속 추론 실패) | source_docs[0] 파일에 `^---`로 시작하는 frontmatter 부재 또는 `source_docs=[]` (마이그레이션 직후 일괄 발화 예상 — Sprint 3 가이드 안내) | Sprint 4 |
| W8 (신규, authority spec §4) | Warn | marker 영역 사용자 손편집 감지 (`--no-verify` 우회 사후 검출) | 마지막 자동 렌더 결과 vs 현재 marker 영역 byte-level diff non-empty | Sprint 4 |
| W9 (신규, authority spec §4 §검출) | Warn | 비표준 actor가 registry-write 호출 | `.nova/events.jsonl`의 `work_item_*` 이벤트 중 `actor` 필드가 `command:/nova:*` 또는 `skill:orchestrator` 또는 `user:direct`가 아닌 entry | Sprint 4 |

**severity tier**:
- `critical` (H1~H9): 배포 차단, `/nova:check` exit 2
- `warning` (W1~W9): 다음 세션 권장, `/nova:check` exit 1
- `info`: dismissed warn (`.nova/.dismissed-drifts` 매칭)

**dismiss 메커니즘**:
```bash
echo "W1:WI-0042:2026-05-15" >> .nova/.dismissed-drifts
# rule_id:wi_id:dismiss_date 포맷. 14일 후 자동 만료
```

#### 5. NOVA-STATE.md 자동 렌더 (marker 영역)

```markdown
## Active Tree
<!-- nova:registry-rendered:start -->
<!-- 자동 생성 영역 — registry-render-state.sh가 갱신. 손편집하지 마세요 -->
<!-- 손편집 필요 시: bash scripts/registry-render-state.sh --no-render --edit 사용 -->

### 활성 작업 (status=active)
- ✅ [WI-0040-database-index](.nova/work-items/WI-0040-database-index.json) — done 2026-05-14
- 🔄 [WI-0042-add-search-filter](.nova/work-items/WI-0042-add-search-filter.json) — review_required
- ⬜ [WI-0043-pagination](.nova/work-items/WI-0043-pagination.json) — depends_on WI-0042
- 🚫 [WI-0044-cache-invalidate](.nova/work-items/WI-0044-cache-invalidate.json) — blocked: Redis 인증 미해결

### 최근 활동 (7일)
- WI-0040 active → done | 2026-05-14T15:00:00Z
- WI-0042 proposed → active | 2026-05-13T09:00:00Z

<!-- nova:registry-rendered:end -->
```

**렌더 트리거** (Sprint 3 결정):
- `registry-write.sh` 직후 자동 (Sprint 3 Spec으로 동결)
- 사용자가 명시적 `bash scripts/registry-render-state.sh --force`도 가능

**손편집 검출**: `/nova:check`가 마커 영역의 git history와 현재 자동 렌더 결과 diff. 차이 있으면 W5 추가 (Sprint 4에서 추가 검토).

### 에러 처리

| 에러 | 대응 |
|------|------|
| `flock`/`mkdir` lock 획득 5초 초과 (50 retry) | UUID fallback (`WI-{uuid8}-{slug}`) + stderr 경고 + W6(신규 warn) "reindex 권고". 다음 세션 `/nova:check` 안내: "WI-UUID 발견 → `bash scripts/reindex-work-items.sh` 실행" |
| stale lock dir (SIGKILL로 잔류, Critic #2) | `kill -0 $PID` 검증으로 holder 사망 확인 후 `rm -rf $LOCK_HOLD` 강제 정리 후 재시도 |
| 부분 전이 마커 잔류 (Critic #1, SIGINT during transition) | 다음 세션 시작 시 `recover_pending_transitions` 자동 실행 → 양쪽 status 일치 시 마커만 제거 / 불일치 시 H8(신규 hard) drift 발화 + 수동 복구 안내 (`bash scripts/registry-write.sh update <wi-id> status=...`) |
| schema 위반 (잘못된 status enum 등) | exit 2 + stderr 상세 위치 (`.nova/work-items/WI-XXXX.json:line 5`) |
| `done` 전이에 commit_sha 누락 | exit 2 + "use --evidence-commit=SHA" 안내 |
| `blocked` 전이에 blocked_reason 누락 (Critic 불변식) | exit 2 + "use --blocked-reason=TEXT" 안내. caller가 update로 별도 set 가능 |
| 마이그레이션 보존율 < 80% | dry-run 단계에서 경고 + `--force` 플래그 없으면 apply 거부 + `legacy_meta` 섹션으로 비정형 보존 |
| `record-event.sh` schema v2/v3 혼재 | forgiving reader — v2 entry는 `event_type`만 추출, v3 entry는 풀 파싱 |
| `--no-verify`로 marker 영역 손편집 commit | /nova:check W5(신규 warn — 마커 영역 git history vs 자동 렌더 결과 diff)로 사후 검출 + "다음 자동 렌더가 덮어쓸 수 있음" 경고 |
| 다중 worktree에서 `.nova/` 공유 (Sprint 0 spec `state-call-graph-v3.md` §4 **Case B(분리) 확정**) | 각 worktree별 독립 `.nova/work-items/` + 머지 시 `next_seq` 최댓값+1 정책. **dead-spot 주의**: `.pending-transition` 마커는 worktree 범위만 검출 — cross-worktree 부분 전이는 머지 후 H8 발화로 사후 감지 (Architect #3) |
| **orchestrator Phase 7 시작 직후 SIGINT** (Architect #4 신규) | Phase 7 진입 즉시 `.pending-transition-$wi` 마커 생성 → `evaluator-pass` 완료 후 마커 제거. SIGINT가 evaluator_verdict 기록 후·evaluator-pass 호출 전에 들어와도 다음 세션 시작 시 `recover_pending_transitions`가 마커 발견 → H8 발화로 사용자 안내 |
| 한국어 slug regex 거부 | regex 확장 (`a-z0-9가-힣-`) — Sprint 0 schema 동결 시 확정 + UUID fallback id는 별도 `oneOf` 패턴 |
| `.gitignore`에 `.nova/`만 있는 구 가이드 사용자 | setup --upgrade 시 자동 진단 + 사용자 동의 후 패턴 갱신 |
| ajv 미설치 환경 (Critic #15) | jq fallback 자동 전환. fallback 검증 범위 = status enum + review_required bool + evidence.commit_sha array + id regex (4종 핵심). 한계는 stderr로 명시 ("ajv 없으면 부분 검증") |
| `schema_version` lexicographic 비교 오류 (Critic #10) | 항상 `split(".") \| map(tonumber)`로 숫자 배열 비교. 문자열 직접 비교 금지 |

---

## Sprint Contract (스프린트별 검증 계약) — 구현 전 필수

> Generator(구현자)와 Evaluator(검증자)가 **사전에 합의**하는 성공 조건.
> Evaluator는 이 계약을 기준으로 PASS/FAIL을 판정한다.

### 스프린트별 Done 조건 (Critic #5·#6·#7·#8 반영)

**열 의미**:
- `상태`: ⚙️ = 해당 Sprint에서 신규 생성 / 📄 = 이미 존재하는 파일 / 📋 = 결정 spec 문서
- `검증 명령`은 *해당 sprint 종료 시점* 기준 실행 가능 여부. 미존재 스크립트 참조는 명시.

| Sprint | 상태 | Done 조건 | 검증 명령 (해당 sprint 종료 시점) | 우선순위 |
|--------|------|----------|--------------------------------|---------|
| **0** | 📋 | `docs/specs/work-item-scope-v3.md` 존재 + WI 스코프(단일/다중 sprint·span 가능 여부) 명시 | `test -f docs/specs/work-item-scope-v3.md && grep -qE "단일 sprint\|다중 span" docs/specs/work-item-scope-v3.md` | **Critical** |
| **0** | 📋 | `docs/specs/state-call-graph-v3.md` 존재 + 16 파일(9 commands + 6 skills + audit-self) 매핑 | `grep -cE "commands/\|skills/" docs/specs/state-call-graph-v3.md` ≥ 16 | **Critical** |
| **0** | 📋 | `docs/specs/registry-write-authority-v3.md` Codex/orchestrator/진입점 권한 경계 결정 | `test -f docs/specs/registry-write-authority-v3.md && grep -qE "권한 경계" docs/specs/registry-write-authority-v3.md` | **Critical** |
| **0** | 📋 | 다중 worktree `.nova/` 공유 여부 결정 (case A 공유 / case B 분리) + state-call-graph spec에 명시 | `grep -qE "worktree.*공유\|worktree.*분리" docs/specs/state-call-graph-v3.md` | **Critical** |
| **1** | ⚙️ | `.nova/schema/work-item.schema.json` + `.nova/schema/index.schema.json` 작성 (UUID fallback oneOf 패턴 포함) | `for s in .nova/schema/*.schema.json; do jq empty "$s" \|\| exit 2; done` | **Critical** |
| **1** | ⚙️ | `scripts/registry-write.sh` 신규 생성 (5 명령 + lock + 부분 전이 복구) | `test -x scripts/registry-write.sh && bash scripts/registry-write.sh create "test wi" \| grep -qE '^WI-[0-9]{4}-' && jq -e '.work_items[] \| select(.id \| startswith("WI-"))' .nova/work-items/index.json` | **Critical** |
| **1** | ⚙️ | `scripts/setup.sh` 신규 생성 (또는 `commands/setup.md` 흐름의 bash 진입점) — 신규 프로젝트 부트스트랩 | `cd /tmp/test-bootstrap-$$  && bash "$NOVA_PLUGIN_PATH/scripts/setup.sh" && test -f .nova/schema/work-item.schema.json && grep -q '!.nova/work-items/' .gitignore` (환경변수 `$NOVA_PLUGIN_PATH` 사용, placeholder 제거) | **Critical** |
| **1** | ⚙️ | `/nova:setup --upgrade` idempotent (기존 v3 registry 변경 없음) | `cd "$TEST_PROJ" && git stash; bash "$NOVA_PLUGIN_PATH/scripts/setup.sh" --upgrade; git diff --exit-code .nova/work-items/` | **Critical** |
| **1** | ⚙️ | `tests/test-channel-race.sh` 신규 작성 + 채번 race 20개 병렬 spawn → 중복 0 | `bash tests/test-channel-race.sh 20 \| sort \| uniq -d \| wc -l` = 0 | **Critical** |
| **1** | ⚙️ | `tests/test-stale-lock.sh` 신규 작성 + SIGKILL stale lock dir 복구 검증 (PID 기반) | `bash tests/test-stale-lock.sh` exit 0 | High |
| **1** | ⚙️ | `scripts/reindex-work-items.sh` 신규 작성 (UUID fallback → 정규 id 재번호화 + depends_on·superseded_by·source_docs 자동 갱신, Architect 권고 2) | `bash scripts/reindex-work-items.sh --dry-run` exit 0 + 변환 매핑 stdout | High |
| **1** | ⚙️ | `setup.sh` 출력에 **Sprint 1~2 gap 경고** 표시 (Architect #7): "9 진입점 registry-write 통합은 Sprint 2(v5.42.0) 이후" | `bash scripts/setup.sh \| grep -qE "9 진입점.*Sprint 2"` | **Critical** |
| **2** | 📄 | 9 진입점 + 7 스킬 = 16 파일 모두 STATE **직접 쓰기 코드** 부재 (Critic #6: 거짓양성 109건 회피) | `grep -rE "(\\\\bcat[[:space:]]+>[[:space:]]*NOVA-STATE\|\\\\becho[[:space:]]+.*>[[:space:]]*NOVA-STATE\|\\\\bsed[[:space:]]+-i.*NOVA-STATE\|\\\\bappend.*NOVA-STATE)" commands/*.md skills/*/SKILL.md \| wc -l` = 0 (가이드 텍스트로 *언급*하는 행은 정상 — bash 쓰기 명령만 검출) | **Critical** |
| **2** | 📄 | `record-event.sh` `schema_version: 3` + 신규 이벤트 3종 동작 | `bash hooks/record-event.sh work_item_created '{"wi_id":"WI-0001-test","status":"proposed"}' && tail -1 .nova/events.jsonl \| jq -e '.schema_version=="3.0" and .event_type=="work_item_created"'` | **Critical** |
| **2** | 📄 | Evaluator PASS 원자적 전이 + 부분 전이 마커 자동 정리 | `bash scripts/registry-write.sh evaluator-pass WI-0001-test --commit-sha=abc123 && jq -e '.status=="done" and .review_required==false and (.evidence.commit_sha \| length > 0)' .nova/work-items/WI-0001-test.json && ! ls .nova/work-items/.pending-transition-* 2>/dev/null` | **Critical** |
| **2** | ⚙️ | **1000 WI 성능 예비 측정 (500개 기준, Architect 권고 5)** — Sprint 4 정식 측정 전 병목 사전 발견 | `bash tests/perf/500-items-bench.sh \| awk '$1>1.0 {exit 1}'` (jq 갱신 + next 추론 합쳐 1초 이내) | High |
| **3** | ⚙️ | `migrate-nova-state.sh --target=v3 --input=PATH --project=PATH` 신규 분기 + `--project` 플래그 추가 (Critic #8: Sprint 6에서 쓰일 플래그 Sprint 3에 귀속) | `bash scripts/migrate-nova-state.sh --target=v3 --input=tests/fixtures/v2-state.md --dry-run` exit 0 + `grep -q '\\-\\-project' scripts/migrate-nova-state.sh` | **Critical** |
| **3** | ⚙️ | v2→v3 마이그레이션 **모든 work-item 기본 `proposed`** (`done` 추론 0건, Codex 명시) | `bash scripts/migrate-nova-state.sh --target=v3 --apply --input=tests/fixtures/v2-state.md && jq -e '.work_items \| map(select(.status=="done")) \| length' .nova/work-items/index.json` = 0 | **Critical** |
| **3** | ⚙️ | `scripts/registry-render-state.sh` 신규 생성 + marker 영역 외 byte-level 보존 | `cp NOVA-STATE.md /tmp/before && bash scripts/registry-render-state.sh && diff <(sed '/<!-- nova:registry-rendered:start/,/end -->/d' /tmp/before) <(sed '/<!-- nova:registry-rendered:start/,/end -->/d' NOVA-STATE.md)` 빈 출력 | **Critical** |
| **3** | ⚙️ | Known Risks 자동 이동 책임 결정 (Critic #14): `migrate-nova-state.sh`가 `docs/specs/risks-v2.md`로 자동 복사 + 사용자 검수 마커 추가 | `bash scripts/migrate-nova-state.sh --target=v3 --apply --input=tests/fixtures/v2-state.md && test -f docs/specs/risks-v2.md && grep -q "검수 필요" docs/specs/risks-v2.md` | High |
| **3** | 📄 | record-event v3 forgiving reader (v2 + v3 entry 혼재 parser 동작) | `bash scripts/nova-metrics.sh --events tests/fixtures/v2-v3-mixed.jsonl` exit 0 | High |
| **3** | ⚙️ | **마이그레이션 직후 W7 일괄 발화 안내** (Architect 권고 4): migrate-state.sh dry-run 출력 + Sprint 6 사용자 가이드에 "마이그레이션 직후 모든 WI가 source_docs=[] 기본이라 W7 일괄 발화 예상 — `update <wi> source_docs+=docs/plans/...` 수동 채움 필요" 명시 | `bash scripts/migrate-nova-state.sh --target=v3 --apply --input=tests/fixtures/v2-state.md && bash scripts/registry-drift-check.sh --severity=warning \| grep -c "W7" \| awk '$1>0 {exit 0} {exit 1}'` (W7 발화 확인) | High |
| **4** | ⚙️ | `scripts/registry-drift-check.sh` 신규 생성 + `tests/fixtures/drift-cases/` 9개 fixture(H1~H9, H8/H9 신규) | `for f in tests/fixtures/drift-cases/*; do bash scripts/registry-drift-check.sh --severity=critical --fixture="$f"; rc=$?; [ "$rc" = "2" ] \|\| { echo "FAIL $f rc=$rc"; exit 1; }; done` | **Critical** |
| **4** | ⚙️ | `tests/test-warn-falsepositive.sh` 신규 작성 + 실보유 10개 프로젝트 W1~W4 false-positive ≤ 10% | `bash tests/test-warn-falsepositive.sh` → 발화율 출력 ≤ 0.10 | Nice-to-have |
| **4** | ⚙️ | `/nova:next` registry-first 추론 (빈 registry fallback 동작) | `mkdir /tmp/empty-proj && cd $_ && jq -n '{schema_version:"3.0",next_seq:1,work_items:[]}' > .nova/work-items/index.json && bash "$NOVA_PLUGIN_PATH/commands/next.sh"` exit 0 + STATE Tasks fallback 출력 | **Critical** |
| **4** | ⚙️ | severity tier + `.nova/.dismissed-drifts` 14일 자동 만료 | `echo "W1:WI-0042:$(date -u +%F)" >> .nova/.dismissed-drifts && bash scripts/registry-drift-check.sh --exclude-dismissed --severity=warning \| grep -v "W1:WI-0042"` | High |
| **5** | 📄 | PoC `nova-landing` bootstrap-only 동작 | `cd /Users/jay/develop/nova-landing && bash "$NOVA_PLUGIN_PATH/scripts/setup.sh" --dry-run` exit 0 | **Critical** |
| **5** | 📄 | PoC `swk-ground-control` v2→v3 마이그레이션 보존율 ≥80% (분자=생성된 WI 파일 수, 분모=동적 카운트, Critic #13) | `before=$(bash scripts/count-v2-items.sh /Users/jay/develop/swk-ground-control/NOVA-STATE.md.v2.bak); bash scripts/migrate-nova-state.sh --target=v3 --apply --project=/Users/jay/develop/swk-ground-control; after=$(ls /Users/jay/develop/swk-ground-control/.nova/work-items/WI-*.json \| wc -l); python3 -c "print($after / $before >= 0.8)"` = True | **Critical** |
| **5** | ⚙️ | `scripts/count-v2-items.sh` 신규 작성 — v2 STATE Tasks·Active Tree·Recently Done·Known Gaps 항목 동적 카운트 | `bash scripts/count-v2-items.sh tests/fixtures/v2-state-sample.md \| grep -qE '^[0-9]+$'` (정수 출력) | **Critical** |
| **5** | 📄 | PoC `planreview` v1→v2→v3 multi-hop (frontmatter 추론) | `bash scripts/migrate-plans-frontmatter.sh /Users/jay/develop/planreview/docs/plans && find /Users/jay/develop/planreview/docs/plans -name '*.md' \| xargs grep -L '^---' \| wc -l` ≤ 5 (대다수 frontmatter 추가됨) | High |
| **5** | ⚙️ | `scripts/migrate-plans-frontmatter.sh` 신규 작성 — 미정형 plan에 최소 frontmatter 추가 | `find tests/fixtures/plans-no-fm -name '*.md' \| head -1 \| xargs bash scripts/migrate-plans-frontmatter.sh --dry-run \| grep -q 'work_items:'` | High |
| **5** | 📄 | Nova 본 레포 자체 적용 *시연* (Sprint 6 검증) | `cd /Users/jay/develop/nova && bash "$NOVA_PLUGIN_PATH/scripts/setup.sh" --upgrade --dry-run` exit 0 — 자기 적용 lock conflict 검증은 Sprint 6 | Nice-to-have (Sprint 6 정식) |
| **6** | 📄 | 형제 7개 **순차 PR** 마이그레이션 PASS — 각 PR 0.5~1일 = 3.5~7일 (Architect #11: 병렬 시 worktree race, 순차로 확정) | `for p in agent-work-memory markbrief md-template-compiler nova-orbit spwk-product swk-data-pipeline swk-cloud-manage; do bash "$NOVA_PLUGIN_PATH/scripts/migrate-nova-state.sh" --target=v3 --apply --project=/Users/jay/develop/$p \|\| exit 1; done` exit 0 | **Critical** |
| **6** | 📄 | Nova 본 레포 자체 검증 PASS (PoC 3개 결과 반영 후) | `cd /Users/jay/develop/nova && bash tests/test-scripts.sh && bash scripts/registry-drift-check.sh --severity=critical` exit 0 | **Critical** |
| **6** | ⚙️ | `docs/guides/work-item-registry-v3.md` 사용자 가이드 작성 (절차 + FAIL 시 해결 + cheatsheet, CLAUDE.md 가이드라인 준수) | `wc -l docs/guides/work-item-registry-v3.md` ≥ 100 + `grep -qE "TL;DR\|cheatsheet" docs/guides/work-item-registry-v3.md` | High |
| **6** | ⚙️ | release notes (v5.43.x) + Sprint별 사용자 안내 (Critic 종합 평가 §사용자 커뮤니케이션) | `grep -qE "work-item-registry-v3" CHANGELOG.md && grep -qE "Sprint 1~3 사이.*마이그레이션 권장 X\|마이그레이션 권장 시점" docs/guides/work-item-registry-v3.md` | High |
| **6** | ⚙️ | Sprint 0~5 사용자 안내 메시지 통합 점검 (변경 관리 정책) | `grep -qE "Sprint별 사용자 안내\|쥬넨 단계 정책" docs/guides/work-item-registry-v3.md` | Medium |

### 관통 검증 조건 (End-to-End)

> "저장됨" ≠ "사용 가능함". 데이터가 입력부터 최종 표시까지 관통하는지 검증한다.

| # | 시작점 (사용자 행동) | 종착점 (결과 확인) | 우선순위 |
|---|---------------------|-------------------|---------|
| 1 | `/nova:plan` 호출하여 새 plan 작성 | `.nova/work-items/WI-NNNN-{slug}.json` 생성 + NOVA-STATE.md marker 영역에 active로 표시 | **Critical** |
| 2 | `/nova:run` 실행 후 Evaluator PASS | work-item status=done + review_required=false + evidence.commit_sha 채워짐 + NOVA-STATE.md marker에서 ✅로 변경 + record-event work_item_transitioned 발화 | **Critical** |
| 3 | `/nova:next` 호출 | registry-first 추론으로 후보 1~3개 제시 (priority + depends_on 해결 + status=active\|proposed). 빈 registry는 NOVA-STATE.md Tasks fallback | **Critical** |
| 4 | `/nova:check` 호출 | drift Hard 9 검사 + Warn 9 검사 → 인위적 drift fixture 100% 검출, 정상 프로젝트 false-positive ≤ 10% | **Critical** |
| 5 | `/nova:migrate-state --target=v3 --dry-run` → 검수 → `--apply` | v2 NOVA-STATE.md 백업(`.v2.bak`) + `.nova/work-items/` 생성 + 모든 항목 `proposed` 기본 + 보존율 ≥80% | **Critical** |
| 6 | 사용자가 marker 영역 손편집 후 `git commit --no-verify` | 다음 `/nova:check`가 W5(차이 발견) 경고 + 다음 자동 렌더가 덮어쓸 수 있음 안내 | High |
| 7 | 다중 git worktree에서 두 세션이 동시에 `/nova:plan` (Sprint 0 spec `state-call-graph-v3.md` §4로 **Case B 분리** 확정) | 각 worktree의 `.nova/work-items/`에 독립 발급 (예: main WI-0042, worktree WI-0042). 머지 시 git이 충돌 감지 → 사용자 수동 머지 + `bash scripts/reindex-work-items.sh` 실행. drift H2(id 유일성)가 잔류 위반 사후 검출. **단일 lock으로 race 차단은 의도 안 함** — 분리가 격리의 핵심. **`.pending-transition` 마커도 worktree 분리 — cross-worktree dead-spot은 머지 후 H8로 사후 감지** (Architect #3) | **Critical** |
| 8 | orchestrator Phase 7 시작 직후 SIGINT (Architect #4 신규) | Phase 7 진입 직후 `.pending-transition-$wi` 마커 생성 (evaluator-pass 호출 *전*). SIGINT 발생 시 마커 잔류 → 다음 세션 `recover_pending_transitions` 호출 → H8 drift 발화 → 사용자가 수동 복구 (`registry-write.sh update <wi> status=done evidence.commit_sha+=[...]` 또는 active 복원) | **Critical** |

### 역방향 검증 체크리스트

- [ ] Plan § Problem § MECE 분해 8개 영역 모두 Design § Solution에서 다루는가?
  - [x] #1 진실원 부재 + 9 진입점 일관성 → § Solution § 아키텍처 + § registry-write.sh
  - [x] #2 next-work stale → § /nova:next registry-first
  - [x] #3 마이그레이션 흐름 부재 → § migrate-nova-state.sh v2→v3
  - [x] #4 drift 감지 부재 → § registry-drift-check.sh
  - [x] #5 id·status·evidence 표준 부재 → § 데이터 모델 + § 데이터 계약
  - [x] #6 롤백·다운그레이드 → § Plan Sprint 4 롤백 시나리오 4개 (Design은 정책만 참조)
  - [x] #7 사용자 교육·변경 관리 → § Sprint Contract Sprint 6 사용자 가이드 + release notes
  - [x] #8 멀티 에이전트 동시성 → § Sprint Contract Sprint 0 spec + § 채번 race + § 다중 worktree 에러 처리
- [ ] Plan § 동결된 7개 결정 모두 Design § 데이터 모델 + § 데이터 계약에 반영되었는가?
- [ ] Plan § Risk Map 17건의 완화책이 Design § 핵심 로직 + § 에러 처리에 구현되어 있는가?
- [ ] Plan § Verification Hooks 20건이 Sprint Contract Done 조건에 모두 매핑되어 있는가? (특히 신규 Hook #18·#19·#20)
- [ ] Plan § Critic 미해결 항목 3건의 시스템적 권고가 Design에서 다뤄지는가?
  - [x] 자기참조 위험 → § Sprint Contract Sprint 5/6 분리 (Sprint 5는 시연, Sprint 6 검증)
  - [x] 사용자 커뮤니케이션 → Sprint 6 Done 조건 갱신: "Sprint 1~3 사이 사용자에게 *지금 마이그레이션 권장 X* 메시지를 release notes·`/nova:next` 안내·`docs/guides/work-item-registry-v3.md`에 명시" + Sprint별 안내 메시지 통합 점검 Done 조건 추가
  - [x] Codex 위임 책임 경계 → Sprint 0 `docs/specs/registry-write-authority-v3.md`

### 평가 기준

- **기능**: Verification Hook 20건 + Sprint Contract Done 조건 **37개** + 관통 검증 7건 모두 PASS.
- **설계 품질**:
  - 단방향 reconcile 원칙 위반 0건 (registry → STATE만)
  - 9 진입점 + 7 스킬 = 16 파일이 모두 단일 쓰기 경로(`registry-write.sh`) 사용
  - schema_version 진화 시 forgiving reader가 old Nova에서 동작
- **단순성**:
  - 사용자가 직접 편집해야 할 파일 = NOVA-STATE.md(marker 외) + `docs/plans/*.md` frontmatter만
  - `/nova:setup`이 모든 부트스트랩 자동화 (사용자 수동 단계 0)
  - 마이그레이션은 dry-run → review → apply 3단계로 통일

---

## Design 반복 루프 (E2E 실패 시)

E2E 테스트나 `/nova:check` 검증에서 설계 자체의 문제가 발견되면:

1. Design 문서를 수정하고 Sprint Contract를 업데이트한다.
2. 수정된 Design을 기준으로 재구현한다.
3. Sprint 0 spec 3개(work-item-scope·state-call-graph·registry-write-authority)는 schema 동결과 동등한 무게 — 변경 시 minor 범프 트리거.

특히 관통 검증 #7(다중 worktree race) 실패 시:
- Sprint 0 사전 조사 결과를 재검토
- worktree별 lock vs 단일 lock 정책 재결정
- schema에 worktree-aware 필드 추가 필요 시 schema_version 3.1로 진화

---

## 한 줄 요약

**Design v3 = "registry-write.sh 단일 쓰기 경로(5 명령 + exit 계약 명시) + flock/mkdir atomic 채번(PID stale 검증) + Evaluator PASS 원자적 전이(부분 전이 마커 + 부분 적용 복구) + marker 영역 자동 렌더 + drift Hard 9/Warn 9 = 18종 + 마이그레이션 보수성(done 추론 금지·항목/상태 보존율 분리)". Sprint Contract 37개 Done 조건(현재 가능/신규 생성 구분) + 관통 검증 7건. Plan Critic 12 + Design Critic 20 + Architect Critic 11 = 43 이슈 surgical edit 완료.**
