# .nova/ — Nova Work-Item Registry (v3)

> ⚠️ **DO NOT EDIT** `.nova/work-items/`·`.nova/schema/` 파일을 직접 손편집하지 마세요.
> 모든 변경은 `bash scripts/registry-write.sh` 또는 `/nova:` 슬래시 커맨드 경유.

## 무엇인가

이 디렉토리는 Nova v3 work-item registry입니다 — **기계용 단일 진실원**.

- 진척 상황·검토 상태·증거(commit SHA)는 모두 여기에 기록됩니다.
- `NOVA-STATE.md`의 자동 렌더 영역(`<!-- nova:registry-rendered:start -->` ~ `<!-- nova:registry-rendered:end -->`)은 이 디렉토리를 *투영*만 합니다 (양방향 동기화 X).
- 사람용 cursor(`NOVA-STATE.md` marker 바깥)과 기계용 진실원(`.nova/`)이 명확히 분리됩니다.

## 디렉토리 구조

```
.nova/
├── README.md           # 이 파일 — git-tracked
├── schema/             # JSON Schema (v3.0) — git-tracked
│   ├── work-item.schema.json
│   └── index.schema.json
├── work-items/         # work-item 진실원 — git-tracked
│   ├── index.json      # 경량 매니페스트 (단일 쓰기 경로)
│   ├── WI-NNNN-slug.json
│   └── .lock/          # mkdir atomic lock — git-ignored
├── events.jsonl        # KPI 이벤트 로그 — git-ignored
├── local/              # 사용자 로컬 — git-ignored
└── tmp/                # 임시 — git-ignored
```

## git-tracked / git-ignored 정책

`/nova:setup`이 `.gitignore`에 다음 패턴을 자동 추가합니다:

```gitignore
.nova/*
!.nova/work-items/
!.nova/work-items/**
!.nova/schema/
!.nova/schema/**
!.nova/README.md
.nova/work-items/.lock/
.nova/events.jsonl
.nova/local/
.nova/tmp/
```

| 영역 | 정책 | 사유 |
|------|------|------|
| `.nova/work-items/*.json` | **git-tracked** | clone 후 즉시 진실원 복원 — registry는 원격에서 작동해야 함 |
| `.nova/schema/*.json` | **git-tracked** | 검증 도구(`/nova:check`)가 schema 의존 |
| `.nova/README.md` | **git-tracked** | 이 README |
| `.nova/events.jsonl` | git-ignored | 로컬 KPI 이벤트, 머신간 race condition 방지 |
| `.nova/local/` · `.nova/tmp/` | git-ignored | 사용자별·실행별 |
| `.nova/work-items/.lock/` | git-ignored | atomic lock 디렉토리 |

## 사용 (CRUD)

| 작업 | 명령 | 비고 |
|------|------|------|
| 생성 | `bash scripts/registry-write.sh create <slug> [field=value ...]` | 자동 채번 (WI-NNNN), 기본 status=proposed |
| 갱신 | `bash scripts/registry-write.sh update <wi-id> <field>=<value>` | `id`·`created_at`·`schema_version`은 immutable |
| 상태 전이 | `bash scripts/registry-write.sh transition <wi-id> <new-status>` | 5상태 전이, invariant 자동 보호 |
| Evaluator PASS | `bash scripts/registry-write.sh evaluator-pass <wi-id> --commit-sha=<sha>` | 원자적: `status=done` + `review_required=false` + evidence 동시 set |
| 검증 요청 | `bash scripts/registry-write.sh require-review <wi-id>` | `review_required=true` |

> 9개 슬래시 커맨드(`/nova:plan`·`/nova:design`·`/nova:run`·`/nova:review`·`/nova:check`·`/nova:auto`·`/nova:ux-audit`·`/nova:next`·`/nova:status`)가 적절한 시점에 자동 호출합니다. 직접 호출은 권장하지 않습니다 — 자동화·검증·이벤트 기록을 함께 해주므로.

## 손편집 정책

| 영역 | 손편집 | 위반 시 |
|------|--------|---------|
| `.nova/work-items/WI-*.json` | ❌ 금지 | drift W8 — `registry-write` 경유 권고 |
| `.nova/work-items/index.json` | ❌ 절대 금지 | drift Hard — `/nova:check` 실패 |
| `.nova/schema/*.json` | ❌ 금지 | Nova plugin 업데이트 시 덮어쓰기 (수동 변경 손실) |
| `NOVA-STATE.md` (marker 안쪽) | ❌ 금지 — 자동 렌더 영역 | 다음 렌더 시 덮어쓰기 |
| `NOVA-STATE.md` (marker 바깥) | ✅ 자유 | 사람 손편집 보존 |

## status enum (5값, 동결)

| status | 의미 | 전이 |
|--------|------|------|
| `proposed` | 생성됨, 아직 시작 안 함 | → active / superseded |
| `active` | 진행 중 | → blocked / done / superseded |
| `blocked` | 블로커로 중단 (`blocked_reason` 필수) | → active / superseded |
| `done` | 완료 (`evidence.commit_sha` 필수, `review_required=false`) | → superseded |
| `superseded` | 폐기 또는 다른 WI로 대체 (`archived_at` 자동 set) | (종착) |

**원자적 전이 보장**: Evaluator PASS 시 `status=done` + `review_required=false` + evidence 갱신이 한 트랜잭션. `.pending-transition-<id>` 마커로 중단 복구.

## 보조 플래그

| 필드 | 타입 | 설명 |
|------|------|------|
| `review_required` | bool | true = `/nova:review`·`/check`·`/ux-audit` 대기. Evaluator PASS 시 false. |
| `archived_at` | timestamp\|null | superseded 전이 시 자동 set. |
| `last_verified_at` | timestamp\|null | `/nova:review`·`/check` PASS 시 자동 set. status=active만 30일+ stale 체크. |

## drift 룰 18종 (Hard 9 + Warn 9)

`/nova:check`가 다음 위반을 자동 검출 (자세히는 Nova 본 레포 `docs/designs/work-item-registry-v3.md §drift 룰`):

- **Hard 9 (배포 차단, exit 2)**: schema 위반·id 충돌·status enum 위반·git-tracked 보장·`done` evidence 부재·`depends_on` 존재성·순환 의존·schema_version 호환·invariant 불일치
- **Warn 9 (경고, exit 0)**: stale STATE·plan frontmatter 누락·unreferenced plan·last_verified_at stale·UUID fallback id·미존재 source_docs·blocked_reason 누락·손편집 의심·비표준 actor

## 스키마 진화 정책

- `schema_version: "3.0"` → `"3.1"` (minor): 필드 추가만 허용. **forgiving reader**: 미지 필드 무시.
- `"3.x"` → `"4.0"` (major): breaking change. `/nova:migrate-state --target=v4` 흐름 필요.
- 사용자가 schema 파일을 직접 손편집하면 Nova plugin 업데이트 시 덮어쓰기 — schema 변경은 Nova 본 레포 issue/PR로 제안.

## 마이그레이션 (v1·v2 → v3)

```bash
/nova:migrate-state --target=v3          # dry-run (기본)
/nova:migrate-state --target=v3 --apply  # 실제 적용
```

- v2 STATE의 Tasks 표·Recently Done·Known Gaps·Active Tree 항목을 work-item으로 변환.
- **commit_sha 추출 실패 시 `proposed`로 강등** (done 추론 절대 금지 — Codex 명시).
- `priority`는 모두 `medium` 기본, `depends_on`·`source_docs`는 빈 배열 — 사용자가 post-migration 수동 입력.
- 백업: `NOVA-STATE.md.v2.bak` 자동 생성.

## 자세히

- 설계 문서: <https://github.com/jay-swk/nova/blob/main/docs/designs/work-item-registry-v3.md>
- Plan: <https://github.com/jay-swk/nova/blob/main/docs/plans/work-item-registry-v3.md>
- Sprint 0 specs:
  - <https://github.com/jay-swk/nova/blob/main/docs/specs/work-item-scope-v3.md>
  - <https://github.com/jay-swk/nova/blob/main/docs/specs/state-call-graph-v3.md>
  - <https://github.com/jay-swk/nova/blob/main/docs/specs/registry-write-authority-v3.md>
