---
description: "NOVA-STATE.md를 최신 v3 work-item registry로 변환한다. v1/v2 입력 모두 직접 v3 가능. dry-run → 사용자 검수 → apply + drift-check 자동. — MUST TRIGGER: 사용자가 STATE 변환 요청한 직후, session-start v1/v2 hint를 본 직후, 또는 `.nova/work-items/` 부재."
description_en: "Migrate NOVA-STATE.md to v3 work-item registry (latest). Accepts v1/v2 input directly — no multi-hop needed. Flow: dry-run → user review → apply + drift-check auto."
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

- (기본) : **v3 work-item registry로 변환** (v1/v2 입력 모두 직접 가능). dry-run → 사용자 검수 → apply + drift-check 자동
- `--apply` : dry-run 건너뛰고 바로 apply (사용자가 이미 검수 완료 시)
- `--check` : 현재 schema 점검만 (변환 안 함)
- `--target=v2` : v1→v2까지만 (구버전 호환, deprecated). 일반 사용자에게는 v3 권장

## 기본 흐름 (v3 변환 — 단일 명령)

v5.43.1+: `/nova:migrate-state` 한 줄로 v1/v2 → v3 직행. 메인 에이전트가 자동 처리:

```bash
# Step 1: 자동 schema 감지 + dry-run
bash "$NOVA_PLUGIN_ROOT/scripts/migrate-state-v3.sh" --dry-run

# Step 2: 사용자 검수 후 적용
bash "$NOVA_PLUGIN_ROOT/scripts/migrate-state-v3.sh" --apply
# 자동 처리: .nova/{schema,work-items,README.md} 부트스트랩 + NOVA-STATE.md.v2.bak 백업
#            marker 영역 추가 + registry-render-state.sh 자동 호출

# Step 3: drift 18 룰 자동 검증
bash "$NOVA_PLUGIN_ROOT/scripts/registry-drift-check.sh"
```

**v1 입력도 직접 v3 가능** (multi-hop 불필요): migrate-state-v3.sh 파서가 frontmatter 부재 + 본문 표 (Tasks/Recent/KG/Active Tree)를 직접 추출. v1→v2 거쳐갈 이유 없음 (그래도 원하면 `--target=v2`).

**의사 결정 (Step 2 사용자 검수)**:
- A. 결과 OK → `--apply` + drift-check 실행
- B. 보존율 (a) < 80% → 중단 + Nova 본 레포 issue 등록
- C. 추가 검토 → 가이드 (`$NOVA_PLUGIN_ROOT/docs/guides/sibling-migration-v3.md`)
- D. 변환 안 함 → 현 STATE 유지

# Procedure

## Step 1 — schema 점검 (모든 옵션 공통)

```bash
head -10 NOVA-STATE.md
test -f .nova/work-items/index.json && echo "v3-registry-ready" || echo "no-v3-registry"
grep -qF "<!-- nova:registry-rendered:start -->" NOVA-STATE.md && echo "v3-marker-present"
```

**분기**:
- NOVA-STATE.md 부재 → "STATE 없음 — `/nova:setup` 또는 새 세션 시작 시 자동 생성" 안내 후 종료
- `.nova/work-items/index.json` 존재 + v3 marker 존재 → **이미 v3, 종료**: "이미 v3 registry 적용 상태입니다. `/nova:check`로 drift 검증 가능."
- `.nova/work-items/index.json` 의 work_items 존재 + v3 marker **부재** → **hybrid 상태** (registry 는 이미 v3, NOVA-STATE.md 포맷만 미정합): Step 6 진입하되, migrate-state-v3.sh 가 idempotency 가드로 STATE 본문 재파싱을 자동 생략하고 v3 marker 삽입만 수행한다 — registry work-item 은 그대로 보존(재생성·강등·append 없음). dry-run 출력이 "registry 는 v3 완비 — marker 만 삽입 예정"이면 보존율(B)·4지선다 없이 결과 확인 후 바로 `--apply`.
- `--check` 옵션 → 위 정보만 보고 후 종료
- `--target=v2` 옵션 → Step 2 (legacy v1→v2 흐름) 진입
- 그 외 (기본) → **Step 6 (v3 변환)** 진입. v1/v2 입력 모두 동일 처리

## Step 6 — v3 변환 (기본 흐름)

> **이미 v3 registry 보유 시 (hybrid)**: migrate-state-v3.sh 는 idempotency 가드로 STATE 본문 재파싱을 자동 생략하고 v3 marker 삽입만 수행한다. dry-run 출력에 "registry 는 v3 완비" 가 보이면 보존율 임계·4지선다는 적용되지 않는다 — 결과 확인 후 바로 `--apply`.

```bash
# Step 6.1: dry-run 미리보기
bash "$NOVA_PLUGIN_ROOT/scripts/migrate-state-v3.sh" --dry-run
```

출력에서 다음 정보 추출 후 사용자에게 보고:
- 변환 대상 work-item 수 (보존율 a — 임계 ≥ 80%)
- done w/ sha vs proposed 강등 (보존율 b — 참고지표)
- 발견된 섹션 (Tasks/Recent Activity/Known Gaps/Active Tree)
- 입력 schema 추정 (v1 = frontmatter 없음, v2 = `schema_version: 2`)

사용자 4지선다:
- **A** : 결과 OK → `--apply` 실행 + drift-check 자동 검증
- **B** : 보존율 (a) < 80% → 변환 중단 + Nova 본 레포 issue
- **C** : 가이드 확인 — `cat "$NOVA_PLUGIN_ROOT/docs/guides/sibling-migration-v3.md"`
- **D** : 변환 안 함 → 현 STATE 유지

### A 선택 시 (자동 진행)

```bash
# Step 6.2: 실제 적용
bash "$NOVA_PLUGIN_ROOT/scripts/migrate-state-v3.sh" --apply

# Step 6.3: drift 자동 검증
bash "$NOVA_PLUGIN_ROOT/scripts/registry-drift-check.sh"
```

**drift-check exit code 분기**:
- `0` = PASS — 보고만, 종료
- `1` = Warn only (W5 git 미커밋, W7 source_docs 빈 등 — 정상, post-migration 후속 입력 안내)
- `2` = Hard error → 수동 수정 안내 (`docs/guides/sibling-migration-v3.md` FAIL 시나리오 참조)

### apply 후 사용자에게 보고

- `.nova/work-items/*.json` 위치 + 개수
- `NOVA-STATE.md.v2.bak` 백업 위치 (복원 명령 안내)
- `git add .nova/ NOVA-STATE.md .gitignore` 안내 (commit)
- 후속 manual 입력 권장 (source_docs, depends_on은 자동 추론 안 함 — PoC 5 규칙 #3·#4)

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
