---
description: "NOVA-STATE.md를 v1 schema에서 v2로 변환한다. dry-run preview → 사용자 검수 → apply 흐름. — MUST TRIGGER: 사용자가 v1 STATE 변환을 명시 요청한 직후, 또는 session-start hint를 본 직후."
description_en: "Migrate NOVA-STATE.md from v1 schema to v2. Flow: dry-run preview → user review → apply. — MUST TRIGGER: when user explicitly asks to convert v1 STATE, or right after seeing the session-start hint."
---

NOVA-STATE.md v1 → v2 schema 마이그레이션을 사용자 검수 흐름으로 수행한다.

## 적용 규칙 (on-demand 로드)

- `docs/specs/nova-state-schema-v2.md §9` 마이그레이션 절차
- `docs/specs/nova-state-schema-v2.md §3` v2 frontmatter 스키마
- `docs/specs/nova-state-schema-v2.md §4` v2 본문 섹션 구조

# Role

너는 Nova STATE 마이그레이션 안내자다. 자동 변환은 절대 하지 않는다. 사용자가 dry-run 결과를 보고 OK해야만 apply.

> "사용자별로 NOVA-STATE.md 변형이 다양해 정형 변환 손실이 있을 수 있다."
> "이 커맨드는 변환 결과를 먼저 보여주고, 사용자 명시 동의를 받은 후에만 적용한다."

# Options

- `--apply` : dry-run 건너뛰고 바로 apply (사용자가 이미 검수 완료 시)
- `--check` : 현재 NOVA-STATE.md schema_version 점검만 (변환 안 함)
- `--target=v3` : v3 work-item registry로 변환 (v5.42.0+, Sprint 1~6). v2 STATE → `.nova/work-items/*.json` + index.json + marker 영역 추가
- (기본) : v1→v2 dry-run → 사용자 검수 → apply 흐름. 단 v2 STATE 감지 시 사용자에게 v3 변환 권고

## v3 마이그레이션 흐름 (`--target=v3`)

v5.42.0+ 사용자가 슬래시 한 줄로 v2→v3 진입:

```bash
# Step 1: dry-run 미리보기 (보존율 + WI 분포)
bash "$NOVA_PLUGIN_ROOT/scripts/migrate-state-v3.sh" --dry-run

# Step 2: 사용자 검수 후 실제 적용
bash "$NOVA_PLUGIN_ROOT/scripts/migrate-state-v3.sh" --apply
# 자동: .nova/{schema,work-items,README.md} 부트스트랩 + NOVA-STATE.md.v2.bak 백업
#       marker 영역 추가 + registry-render-state.sh 자동 호출

# Step 3: drift 18 룰 검증
bash "$NOVA_PLUGIN_ROOT/scripts/registry-drift-check.sh"
```

**의사 결정 (Step 2 사용자 검수)**:
- A. 결과 OK → `--apply` 실행
- B. 보존율 불만족 → v2 유지 + Nova 본 레포 issue 등록
- C. 추가 검토 필요 → 가이드 참조 (`$NOVA_PLUGIN_ROOT/docs/guides/sibling-migration-v3.md`)

**v2 자동 감지 → v3 권고**: schema_version=2 frontmatter 발견 시 사용자에게:
> "현재 v2 STATE입니다. v3 work-item registry로 변환하시겠습니까? (자세히: `/nova:migrate-state --target=v3`)"

# Procedure

## Step 1 — schema_version 점검 (`--check` 옵션)

```bash
head -10 NOVA-STATE.md
```

- frontmatter에 `schema_version: 2` 있으면:
  - `--target=v3` 옵션이 있으면 → v3 변환 분기 (Step 6) 진입
  - 옵션 없으면 → 사용자에게 "이미 v2입니다. v3 work-item registry로 변환하려면 `/nova:migrate-state --target=v3` 실행" 안내 후 종료
- frontmatter 없거나 `schema_version` 없으면 → v1, 다음 단계 진행
- NOVA-STATE.md 자체가 없으면 → "STATE 없음" 보고 후 종료

## Step 6 — v3 변환 분기 (`--target=v3`)

```bash
# dry-run 미리보기
bash "$NOVA_PLUGIN_ROOT/scripts/migrate-state-v3.sh" --dry-run
```

출력에서 다음 정보 추출:
- 변환 대상 work-item 수 (보존율 a)
- done w/ sha vs proposed 강등 (보존율 b)
- 발견된 섹션 (Tasks/Recent Activity/Known Gaps/Active Tree)

사용자에게 4지선다 제시:
- **A** : 결과 OK → `--apply` 실행 + drift-check 자동 검증
- **B** : 보존율 (a) < 80% → v2 유지 + 수동 보정 후 재시도
- **C** : 변환 중단 → v2 유지
- **D** : 가이드 확인 — `cat "$NOVA_PLUGIN_ROOT/docs/guides/sibling-migration-v3.md"`

A 선택 시:
```bash
bash "$NOVA_PLUGIN_ROOT/scripts/migrate-state-v3.sh" --apply
bash "$NOVA_PLUGIN_ROOT/scripts/registry-drift-check.sh"
```

drift-check exit code:
- 0 = PASS (보고 후 종료)
- 1 = Warn only (W5 git 커밋, W7 source_docs 빈 등 — 정상, post-migration 후속)
- 2 = Hard error → 수동 수정 안내 (`docs/guides/sibling-migration-v3.md FAIL 시나리오` 참조)

apply 후 사용자에게:
- `.nova/work-items/*.json` 위치 안내
- `NOVA-STATE.md.v2.bak` 백업 안내
- 후속 manual 입력 (source_docs, depends_on)은 `registry-write.sh update` 명령 안내

## Step 2 — dry-run 실행 (변환 결과 미리보기)

`$NOVA_PLUGIN_ROOT`를 활용해 nova plugin의 migrate 스크립트 호출:

```bash
bash "$NOVA_PLUGIN_ROOT/scripts/migrate-nova-state.sh"
```

(`$NOVA_PLUGIN_ROOT`는 Nova SessionStart hook이 자동 export. 없으면 `~/.claude/plugins/cache/nova-marketplace/nova/*/` 중 최신 버전.)

dry-run 결과를 stdout으로 받고 다음 정보 추출:
- 추론 경고 (Tasks 0건, goal 추론 실패 등) — stderr 확인
- 정보 보존율 — `wc -c` 로 v1 원본 vs v2 결과 크기 비교, 비율 보고

## Step 3 — 사용자 검수 안내

사용자에게 변환 결과를 다음 방식으로 보여준다:

1. **요약 보고** (2~3줄):
   - 정보 보존율 (예: "v1 62KB → v2 48KB, 78% 보존")
   - 발견된 손실 항목 (예: "Tasks 섹션 추출 0건 — Legacy Sections로 passthrough")
   - 핵심 변경 (예: "Goal 추출 OK, Recent Activity 5건 OK, Legacy Sections 1개 보존")

2. **변환 결과 표시**:
   - 짧은 STATE (≤ 200줄): 전체 stdout 출력
   - 긴 STATE: 첫 50줄 + 마지막 30줄 + "전체는 .nova/migrate-preview.md 또는 dry-run 재실행" 안내

3. **사용자 결정 요청** (4지선다):
   - **A** : 결과 OK → 바로 apply (Step 4 진행)
   - **B** : 결과 미흡 → 사용자가 v1 그대로 유지하고 수동 정리 후 다시 호출
   - **C** : 변환 안 함 (v1 유지) → `NOVA_DISABLE_AUTO_MIGRATE=1` set 안내
   - **D** : 추가 의견 (수정 요청 / 손실 항목 검수 등)

## Step 4 — apply (사용자 A 선택 또는 `--apply` 옵션 시)

```bash
bash "$NOVA_PLUGIN_ROOT/scripts/migrate-nova-state.sh" --apply
```

자동 동작:
- `NOVA-STATE.md.v1.bak` 자동 생성 (백업)
- `NOVA-STATE.md` v2 포맷으로 덮어쓰기
- v5.40.x 자동화 잔재 (`NOVA-MIGRATE-PENDING.md`, `.nova/migrate-preview.md`) 있으면 자동 삭제

apply 후 사용자에게:
- 백업 위치 안내 (`NOVA-STATE.md.v1.bak`)
- 복원 방법 안내 (`cp NOVA-STATE.md.v1.bak NOVA-STATE.md`)
- 마크다운 뷰어로 결과 확인 권장

## Step 5 — 사후 안내

apply 성공 후:
1. 다음 세션부터 자동으로 v2 분기 사용 (session-start hook이 frontmatter `schema_version: 2` 인식)
2. v1 fallback 코드 경로 안 탐
3. 백업(`.v1.bak`)은 사용자가 결정 (보존 / 제거 / .gitignore — 기본 `.gitignore`에 이미 `*.md.bak` 패턴 있음)

# Edge Cases

| 케이스 | 대응 |
|-------|------|
| NOVA-STATE.md 없음 | "STATE 없음 — `/nova:setup` 또는 새 세션 시작 시 자동 생성" 안내 후 종료 |
| 이미 v2 | "이미 v2입니다" 보고 후 종료 |
| dry-run 추출 0건 (모든 섹션) | "원본 포맷 비표준 — 자동 변환 위험. v1 유지 권장 + 수동 v2 작성" 안내 |
| 정보 보존율 ≤ 50% | 사용자에게 위험 명시 + 수동 검수 강력 권장 |
| `$NOVA_PLUGIN_ROOT` 없음 | `~/.claude/plugins/cache/nova-marketplace/nova/` 최신 버전 디렉토리 찾기 fallback |
| apply 후 자동 잔재 정리 안 됨 | 수동 `rm NOVA-MIGRATE-PENDING.md .nova/migrate-preview.md` 안내 |

# Output Format

```
━━━ Nova STATE Migration ━━━

📋 점검 결과
- schema: v1 (frontmatter 없음)
- 크기: 62KB (78 줄)
- 비표준 섹션: `## v1.0 Sprint 상태` (1개)

🔄 Dry-run 변환
- v1 62KB → v2 48KB (보존율 78%)
- Goal: "Phase 14 진입" ✅
- Recent Activity: 5건 추출 ✅
- Risks: 4건 (1개 Legacy passthrough) ⚠️
- Refs: 전체 보존 ✅
- Legacy Sections: 1개 (## v1.0 Sprint 상태)

📄 변환 결과 (요약):
{첫 50줄 + 마지막 30줄}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 변환을 진행할까요?

  A. 결과 OK → 바로 apply
  B. v1 그대로 유지
  C. NOVA_DISABLE_AUTO_MIGRATE=1 set (알림 끄기)
  D. 추가 의견 / 수정 요청

선택해주세요.
```

# 자동 동작 금지

- 사용자 명시 동의 없이 `--apply` 실행 절대 금지
- dry-run 결과를 사용자에게 안 보여주고 apply 진행 금지
- `NOVA-STATE.md`를 직접 편집 금지 (반드시 `migrate-nova-state.sh --apply` 경유)

# Related Commands

- `/nova:check` — v2 마이그레이션 후 STATE 정합성 검증
- `/nova:setup` — 신규 프로젝트에 NOVA-STATE.md (v2) 자동 생성

# Spec Reference

- `docs/specs/nova-state-schema-v2.md` — v2 schema 전체 명세 (17섹션 + 27용어)
- `scripts/migrate-nova-state.sh` — 변환 스크립트 (`strip_emphasis` + `graceful passthrough` + dry-run/apply 모드)
