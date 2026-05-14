# NOVA-STATE.md Schema v2.0

> **Status**: Draft — 멀티 AI 자문 합의 95% (2026-05-14) 기반
> **Replaces**: v1 (평탄 테이블, schema_version 없음)
> **Migration**: `/nova:migrate-state` (수동, dry-run 우선)
> **Verification**: [`docs/verifications/2026-05-14--NOVA-STATE-md-스키마-재설계-자문-Context.md`](../verifications/2026-05-14--NOVA-STATE-md-스키마-재설계-자문-Context.md)

---

## 1. 목적

`NOVA-STATE.md`는 프로젝트 루트의 단일 진실 원천(SoT)이며 다음 책임을 진다:

- session-start 시 자동 생성/주입
- `/nova:next`, `/nova:status`, 모든 에이전트 진입 시 첫 번째 읽기 대상
- 에이전트 간 핸드오프 컨텍스트 전달
- 사람이 마크다운 뷰어로 한눈에 진행 흐름 파악

v1의 한계:
1. 계층(AO > Phase > Sprint)이 task 문자열에 묵시 박혀 트리뷰 불가
2. `Goal/Phase/Blocker`가 단일 값 — 병렬 작업 표현 불가
3. 핸드오프 컨텍스트 필드 부재 — 에이전트 간 컨텍스트 단절
4. 평탄 테이블 — 시각적 위계 없음

v2 해법: **YAML frontmatter (기계 권위) + 본문 마크다운 트리 (사람 가독)**.

---

## 2. 파일 위치

| 항목 | 경로 | 비고 |
|------|------|------|
| 메인 SoT | `NOVA-STATE.md` (프로젝트 루트) | v1과 위치 동일 |
| 버전 마커 | frontmatter `schema_version: 2` | 없으면 v1으로 파싱 |
| 아카이브 | `.nova/archive-ao{N}.md` | AO 완료 시 통째 이동 |
| 백업 (마이그레이션) | `NOVA-STATE.md.v1.bak` | 1회성 |

---

## 3. Frontmatter 스키마 (정형, 기계 권위)

```yaml
---
schema_version: 2                    # required, integer
goal: string                          # required, 1-line, ≤120 chars
active_ao: string | null              # 활성 AO ID (e.g., "AO-3") or null
handoff:                              # 활성 핸드오프 | null
  from: string                        # 에이전트 이름 (architect/generator/evaluator 등)
  to: string                          # 다음 에이전트
  outputs: string[]                   # 산출물 파일 경로 (절대/상대)
  assumptions: string[]               # 미검증 전제 (가장 자주 누락되는 컨텍스트)
  next_objective: string              # 다음 에이전트의 첫 문장 (1-line, ≤200 chars)
  blockers: string[]                  # 알려진 장애물 (빈 배열 = 없음)
---
```

**필드 의무성**:

| 필드 | 필수 | Null 허용 | 비고 |
|------|:----:|:--------:|------|
| `schema_version` | ✅ | ❌ | 항상 2 |
| `goal` | ✅ | ❌ | 활성 AO 없을 때도 "다음 AO 대기" 같은 메타 목표 |
| `active_ao` | ✅ | ✅ | null이면 본문 Active Tree도 비어야 함 |
| `handoff` | ✅ | ✅ | null이면 본문 Handoff 섹션 생략 가능 |
| `handoff.from`/`to`/`outputs`/`assumptions`/`next_objective` | ✅ | ❌ | handoff 객체 있으면 5개 모두 필수 |
| `handoff.blockers` | ✅ | ❌ | 빈 배열 허용 |

**왜 5필드인가**: 4필드는 `assumptions` 빠지면 가장 자주 깨짐 (멀티 AI 자문 합의). 6필드(`updated_at` 등)는 git이 이미 가진 정보라 노이즈.

---

## 4. 본문 섹션 구조 (사람 가독)

순서 고정, 필수/조건부/선택 구분:

| # | 섹션 | 의무성 | 비고 |
|---|------|:-----:|------|
| 1 | `# 🚀 Nova State` | 필수 | 헤더 |
| 2 | `## 🎯 Current` | 필수 | goal 한 줄 강조 + 다음 행동 콜아웃 |
| 3 | `## 🌳 Active Tree` | 필수 | AO > Phase > Sprint 트리 (비어도 빈 상태 명시) |
| 4 | `## 🤝 Handoff` | 조건부 | handoff != null일 때만 |
| 5 | `## 📊 Recent Activity` | 필수 | 최근 5개 표 |
| 6 | `## ⚠️ Risks & Gaps` | 선택 | 위험·갭 표 |
| 7 | `## 📦 Archive` | 선택 | `<details>` 접힘 |
| 8 | `## 🔗 Refs` | 선택 | Plan/Design/Verification 포인터 |

---

## 5. Active Tree 규칙

**깊이 3단 고정**: AO > Phase > Sprint. Sprint 하위는 표현하지 않음 (에이전트 내부 일).

**노드 상태 이모지**:

| 이모지 | 상태 | 의미 |
|:------:|------|------|
| 🔄 | in-progress | 활성 작업 중 |
| ✅ | done | 완료, PASS |
| ⬜ | todo | 시작 전 |
| ⏸️ | deferred | 보류 |
| ❌ | failed | 실패 (재시도 필요) |
| ⚠️ | blocked | 블로커 (handoff.blockers 참조) |

**노드 메타 표기**:

```
- 🔄 **AO-3** v5.37.0 릴리스 — `2/3 phases`
  - ✅ Phase 1 · 설계 · *architect*
  - 🔄 Phase 2 · 구현 · *generator* — `1/3 sprints`
    - ✅ Sprint A3 — 통합+가드 · `PASS`
    - 🔄 **Sprint B1** — 에러 렌더 ← **현재**
    - ⬜ Sprint B2 — E2E 검증
```

규칙:
- AO/Phase/Sprint 라벨은 **굵게** (`**AO-3**`)
- 담당 에이전트는 *이탤릭* (`*generator*`)
- 진행률은 `` `N/M sprints` `` 인라인 코드
- 현재 위치는 `← **현재**` 마커

---

## 6. Handoff 매니페스트 (5필드 + α)

본문 렌더 형식 (frontmatter `handoff` 객체를 시각화):

```md
## 🤝 Handoff

> [!IMPORTANT]
> **architect → generator**
>
> - 📂 **산출물**: [`docs/designs/status-dashboard.md`](docs/designs/status-dashboard.md)
> - 💭 **미결 가정**: shell-only 유지, Node 20 환경
> - 🎯 **다음 목표**: Sprint B1 — 에러 렌더 통합
> - ⚠️ **블로커**: 없음
```

**필드 → 본문 매핑**:

| frontmatter | 본문 라벨 | 시각화 |
|------------|----------|--------|
| `from` → `to` | 굵은 화살표 헤더 | `**architect → generator**` |
| `outputs` | 📂 산출물 | 파일 링크 배열 |
| `assumptions` | 💭 미결 가정 | 콤마 구분 (3개 초과 시 리스트) |
| `next_objective` | 🎯 다음 목표 | 1-line |
| `blockers` | ⚠️ 블로커 | 빈 배열은 "없음" 출력 |

---

## 7. Active Window 50줄 룰 (재해석)

v1의 "50줄 soft limit"을 다음과 같이 재정의:

**카운트 대상**:
- frontmatter (전체)
- `## 🎯 Current`
- `## 🌳 Active Tree`
- `## 🤝 Handoff`

**카운트 제외**:
- `## 📊 Recent Activity` (최근 5개로 자동 트림됨)
- `## ⚠️ Risks & Gaps`
- `## 📦 Archive` (`<details>` 접힘)
- `## 🔗 Refs`

**초과 시 자동 조치**:
- Sprint 표시 축약 (`A3` → `A3 (PASS)` 한 줄)
- Phase 완료분 Archive로 이동
- 임계 (`> 60`줄) 도달 시 `/nova:state-trim` 자동 제안

---

## 8. 아카이브 규칙

**자동 트리거**:

| 이벤트 | 동작 |
|--------|------|
| Sprint `done` 표시 | Archive 표에 1행 추가, Active Tree에서 라벨 축약 |
| Phase `done` (모든 Sprint done) | Active Tree에서 제거, Archive 표 헤더 행으로 통합 |
| AO `done` (모든 Phase done) | `.nova/archive-ao{N}.md`로 전체 이동, 본문엔 1줄 포인터 |

**Archive 섹션 포맷**:

```md
<details>
<summary>📦 <b>Archive</b> — 완료된 AO (N개)</summary>

| AO | 결과 | 핵심 산출물 |
|----|:----:|------------|
| status-dashboard Phase 1 | ✅ PASS | scripts/build·render-status |
| ... | | |

</details>
```

---

## 9. 마이그레이션 (v1 → v2) — 사용자 명시 커맨드

**핵심 원칙 (v5.41.0+ 정책 전환)**: 자동 변환 실험(v5.38.0~v5.40.x)은 사용성 최악으로 검증됨 — 사용자 보고: *"자동화가 오히려 노이즈 더 만들었음"*. 변환은 **사용자 명시 호출**로만.

**진입점 — `/nova:migrate-state` 커맨드**:
1. `Step 1` schema_version 점검 (`--check` 옵션)
2. `Step 2` dry-run 실행 (변환 결과 미리보기, STATE.md 안 건드림)
3. `Step 3` 사용자 검수 (4지선다: A apply / B 유지 / C disable / D 의견)
4. `Step 4` apply (사용자 A 선택 시만)
5. `Step 5` 사후 안내 (백업 위치, 복원 방법)

상세: `.claude/commands/migrate-state.md`

**session-start hint**: v1 감지 시 `ADDITIONAL_CONTEXT`에 1줄 hint만:
```
💡 NOVA-STATE.md v1 schema 감지 — /nova:migrate-state 커맨드로 v2 변환 가능 (선택). 자동 변환 안 함 (정보 손실 보호).
```

자동 dry-run, preview 파일 생성, sessionTitle prefix, `NOVA-MIGRATE-PENDING.md` 자동 생성 **모두 제거**.

**직접 호출 (CLI)**: `bash $NOVA_PLUGIN_ROOT/scripts/migrate-nova-state.sh [--dry-run|--apply]`

**변환 절차**:

1. **백업**: `NOVA-STATE.md` → `NOVA-STATE.md.v1.bak`
2. **추론 파싱**:
   - `Goal:` 1-line → `frontmatter.goal` (CJK 친화 자연 자르기, 첫 문장 또는 80자)
   - `Phase:` 1-line → `frontmatter.active_ao` 추론
   - Tasks 테이블 행 중 `"Phase N"` 패턴 → AO/Phase/Sprint 트리
   - Tasks `status=done/deferred` → Archive로
   - Tasks `status=in-progress/todo` → Active Tree로
   - `Recently Done` → Archive로 통합
   - `Last Activity` → Recent Activity로 (최근 5개, CJK 친화 컷)
   - `Known Risks` (위험/심각도/상태) + `Known Gaps` (영역/내용/우선순위) → 통합 표 (Gap은 `[Gap]` 프리픽스로 구분)
   - `Refs` → 그대로 유지
3. **handoff 추론**: 불가 → `null` (다음 에이전트 갱신 시 채움)
4. **graceful fallback**: 추론 실패 시 stderr WARN + 부분 결과 적용 (원본은 .v1.bak 보존)
5. **마커 생성**: 변환 성공 시 frontmatter `schema_version: 2`

---

## 10. 갱신 책임 — L3 우선, 단일 강한 안전망

State Drift (코드 ↔ STATE 불일치)는 자문에서 최대 리스크. 다층은 복잡도 증가 → **L3를 1차 의무로 두고, L1/L2는 선택적 보강**으로 단순화.

| 층 | 메커니즘 | 책임 시점 | 의무성 |
|----|----------|----------|:------:|
| **L3 (필수)** | Evaluator의 State Drift 검증 | 커밋 전 | ✅ 1차 의무 |
| L2 (선택) | PostToolUse hook 경고 | 에이전트 종료 시 | ⚪ 보강 |
| L1 (선택) | MCP `orchestration_update` 자동 patch | 에이전트 작업 중 | ⚪ 보강 |

**L3 검증 도구** (v5.39.0+):

```bash
bash scripts/check-state-drift.sh          # warn 모드 (advisory, exit 0)
bash scripts/check-state-drift.sh --strict # Hard Gate (drift 발견 시 exit 1)
```

**검증 로직**:

```
1. working tree 코드 변경 있는데 NOVA-STATE.md mtime ≤ HEAD commit time
   → State Drift: "코드 N개 변경되었으나 NOVA-STATE.md가 HEAD commit 이전 시점"

2. v2 frontmatter handoff.outputs 명시 파일이 git working tree에 없음
   → Handoff Drift: "handoff.outputs에 명시된 파일 N개가 git에 없음"
```

**연동**:
- Evaluator (`/nova:review`, `/nova:check`) 단계에서 `--strict` 호출 권장
- `pre-commit-reminder.sh` Hard Gate는 별도 STATE 신선도 체크 (오늘 PASS 마커)와 분리 — drift는 *내용 일관성*, 신선도는 *시간*

L3 한 곳에서 막히면 커밋 자체가 안 됨 → 다른 층은 보너스. 다층 의무화의 함정(어디서 잡혀야 하는지 불명확, 책임 분산) 회피.

**사람 편집 권한**:
- frontmatter는 기계 권위 — 사람 수정 시 자동 갱신 때 충돌 가능
- 본문 트리는 자동 렌더이지만 사람도 편집 가능 — frontmatter와 어긋나면 frontmatter가 이김

---

## 11. 통합 정책 — v2 단일 표준

**v1/v2 공존 정책 삭제**. 사용자 통찰: *"v1/v2 공존 자체가 부채 누적의 함정. 미래로 미루는 회피지 해결 아님."*

대신:

| 환경 | 동작 |
|------|------|
| **신규 프로젝트** | `init-nova-state.sh`가 처음부터 v2 포맷으로 생성 |
| **기존 v1 STATE** | session-start hook이 감지 → 자동 v1→v2 변환 (백업 .v1.bak 자동) |
| **수동 변환** | `bash scripts/migrate-nova-state.sh --apply` (디버깅/사전 검증용) |

**파서 진입 로직** (인프라 단순화):

```
schema_version = parse_frontmatter_field(state_md, 'schema_version')
if schema_version == 2:
  → v2 파서 (정상)
else:
  → v1 fallback 1회 + 자동 마이그레이션 트리거 → 다음부터 v2
```

**v1 fallback 영역**:
- `hooks/session-start.sh`: Goal 추출 v1 패턴 fallback (자동 마이그레이션 호출 직전)
- `hooks/pre-compact.sh`: `## Last Activity` legacy 분기 (마이그레이션 전 컴팩션 대응)
- 위 두 곳을 제외한 모든 신규 인프라는 v2 단일 지원

> v1 fallback은 "마이그레이션 한 번 누락된 환경의 안전망"일 뿐, 영구 호환성 보장 아님.

---

## 12. 파서 요구사항

bash/python 두 환경 모두 파싱 가능해야 함 (기존 `build-status`, `render-status` 호환):

**bash 측**:
- frontmatter YAML 블록 추출: `awk '/^---$/{c++; next} c==1' NOVA-STATE.md`
- 본문 트리 파싱은 라인 들여쓰기 + 이모지 정규식
- 권장: 파싱 헬퍼 `scripts/lib/parse-nova-state.sh` 신설

**python 측**:
- `PyYAML` 사용 (기존 의존성)
- frontmatter 객체 → dict 변환, 본문은 별도 파싱

**시각 렌더 (build-status/render-status 영향)**:
- 기존 v1 평탄 테이블 파싱 코드는 fallback으로 유지
- v2 트리 파싱 신규 추가
- 대시보드 출력은 v2 우선 (트리 시각화 가능 시), v1은 평탄 호환

---

## 13. 시각 디자인 (마크다운 뷰어 친화)

**사용 GFM 요소**:
- GFM Alert (`> [!NOTE]`, `> [!IMPORTANT]`) — 콜아웃 박스
- `<details>` / `<summary>` — Archive 접힘
- 표 정렬 (`:----:`, `:----`) — 결과 컬럼 가운데 정렬
- 인라인 코드 / 굵게 / 이탤릭 — 강조 위계
- 이모지 상태 도트 — 색감 + 정렬

**뷰어 호환성**:
- GitHub: 모든 요소 지원
- 사용자 자체 뷰어: GFM Alert 지원 추가 예정 ([별도 명세](#))
- 그 외 뷰어 (Obsidian, Typora 등): admonition 미지원 시 일반 인용으로 graceful fallback — 정보 손실 없음

---

## 14. 테스트 / 검증

**회귀 가드** (`tests/test-state-schema-v2.sh`):

```
T1. v2 frontmatter 파싱 정합성
T2. v1 → v2 마이그레이션 dry-run 일치
T3. 마이그레이션 round-trip 손실 ≤ 5%
T4. Active Window 50줄 카운트
T5. State Drift 검증 (L3) — 코드만 변경 시 FAIL
T6. Handoff 5필드 누락 검증
T7. Archive 자동 트리거 (Sprint done → Archive)
T8. v1/v2 공존 — schema_version 분기
```

**fixture**:
- `.fixtures/nova-state-v2-active.md` — 활성 트리 있는 상태
- `.fixtures/nova-state-v2-idle.md` — 활성 AO 없는 상태 (현재 nova 레포 상태)
- `.fixtures/nova-state-v2-handoff.md` — 핸드오프 중인 상태
- `.fixtures/nova-state-v1-legacy.md` — 마이그레이션 입력용

---

## 15. 결정 확정 (사용자 승인 완료)

| # | 결정 | 확정 | 비고 |
|---|------|------|------|
| 1 | 핸드오프 필드 수 | **5필드** | from/to/outputs/assumptions/next_objective + blockers |
| 2 | frontmatter vs 본문 권위 | **frontmatter** | 충돌 시 기계가 이김, 본문은 자동 렌더 |
| 3 | 갱신 강제 메커니즘 | **L3 우선 + L1/L2 선택** | 단일 강한 안전망 (자문 합의 단순화) |
| 4 | 마이그레이션 트리거 | **session-start 자동 감지 + 자동 변환** | 사용자 의견: "감지 후 개선이 자동화되어야 한다" |
| 5 | v1/v2 공존 정책 | **삭제 — v2 단일 표준** | 사용자 통찰: "공존 자체가 부채 누적 함정" |
| 6 | 시각 요소 풀세트 | **채택** | GFM Alert + details + 이모지 (사용자 자체 뷰어 admonition 지원 추가됨) |

---

## 16. 후속 작업

- [ ] (다) `scripts/migrate-nova-state.sh --dry-run` PoC
- [ ] `scripts/lib/parse-nova-state.sh` 파서 헬퍼
- [ ] `tests/test-state-schema-v2.sh` 회귀 가드
- [ ] `.fixtures/nova-state-v2-*.md` × 4개
- [ ] `.claude/commands/migrate-state.md` 신규 커맨드
- [ ] `hooks/session-start.sh` v2 분기 추가
- [ ] `.claude/agents/evaluator.md` L3 검증 로직 추가
- [ ] `docs/nova-rules.md` §3 (실행 검증)에 State Drift 항목 추가

---

## 17. 용어집 (Glossary)

이 spec과 Nova 문서 전반에서 자주 등장하는 용어를 한국어로 풀어 설명한다.

### 작업 단위

| 용어 | 한국어 풀이 | 설명 |
|------|------------|------|
| **AO** (Auto Orchestration) | 자동 오케스트레이션 | 한 번의 사용자 요청으로 시작되는 작업 묶음. 여러 Phase로 구성. 예: "v5.37.0 릴리스" 전체. |
| **Phase** | 단계 | AO 내부의 큰 단계. 보통 *설계 → 구현 → 검증* 순. 담당 에이전트 1명이 맡음. |
| **Sprint** | 스프린트 | Phase 내부의 작업 묶음. 1~3개 파일 변경 정도 단위. |
| **Task** | 태스크 | Sprint 내부의 개별 변경. STATE.md 트리에는 표현 안 함 (에이전트 내부 일). |

### 에이전트 / 워크플로우

| 용어 | 한국어 풀이 | 설명 |
|------|------------|------|
| **Agent** | 에이전트 | 특정 역할(architect/generator/evaluator 등)을 가진 AI 작업자. |
| **Architect** | 설계자 | 설계 문서를 작성하는 에이전트. |
| **Generator** | 구현자 | 실제 코드를 만드는 에이전트. |
| **Evaluator** | 검증자 | 결과물을 독립 검증하는 에이전트. 메인 컨텍스트와 분리된 별도 창. |
| **Handoff** | 인계 / 핸드오프 | 한 에이전트가 끝나고 다음 에이전트로 컨텍스트 넘기는 행위. |
| **SoT** (Single Source of Truth) | 단일 진실 원천 | 같은 정보의 출처가 여러 곳이면 어긋남 발생 → 1개로 통일. NOVA-STATE.md가 SoT. |

### 데이터 / 파일 형식

| 용어 | 한국어 풀이 | 설명 |
|------|------------|------|
| **Frontmatter** | 머리말 메타 | 마크다운 파일 최상단의 `---` 사이 YAML 블록. 기계가 읽는 정형 데이터. |
| **YAML** | (그대로) | 사람·기계 모두 읽기 쉬운 정형 데이터 포맷. JSON의 마크다운 친구. |
| **GFM** (GitHub-Flavored Markdown) | (그대로) | GitHub이 확장한 마크다운 방언. 표·체크박스·Alert 등 포함. |
| **GFM Alert / Admonition** | 콜아웃 박스 | `> [!NOTE]` 같은 구문으로 컬러 강조 박스를 만드는 GFM 기능. |
| **Fixture** | 고정 입력 | 테스트용 미리 만든 샘플 파일. 실제 데이터 대신 사용. |

### 안전 / 검증 메커니즘

| 용어 | 한국어 풀이 | 설명 |
|------|------------|------|
| **State Drift** | 상태 어긋남 | 실제 코드와 STATE.md 내용이 어긋난 상황. 가장 큰 리스크. |
| **다층 방어 (L1/L2/L3)** | 3겹 안전망 | 한 곳에서 못 막아도 다음 층에서 막힘. L1=MCP 자동, L2=hook 경고, L3=Evaluator 최종 검증. |
| **Graceful Fallback** | 부드러운 대비책 | 정상 동작이 안 될 때 파괴 X, 안전한 기본값으로 떨어짐. 예: 마이그레이션 추론 실패 시 원본 보존. |
| **Dry-run** | 모의 실행 | 실제로 변경하지 않고 "이렇게 바뀔 거다" 결과만 출력. 사용자 확인 후 `--apply`로 진짜 실행. |
| **Round-trip** | 왕복 변환 | v1→v2→v1 변환 후 원본과 같은지 확인. 손실 없으면 변환 신뢰성 높음. |
| **회귀 가드 (Regression Guard)** | 과거 버그 재발 차단 | 한번 고친 버그가 다시 생기지 않도록 자동 잡는 테스트. |

### 윈도우 / 트림 정책

| 용어 | 한국어 풀이 | 설명 |
|------|------------|------|
| **Active Window** | 활성 영역 | STATE.md 중 "지금 진행 중인 부분"만 카운트하는 50줄 룰의 대상 영역. |
| **Archive** | 아카이브 / 완료 보관소 | 완료된 작업이 옮겨지는 곳. 본문은 접힘(`<details>`), 상세는 `.nova/archive-ao{N}.md`. |
| **Trim** | 솎아내기 | 줄 수 초과 시 자동/수동으로 줄이는 행위. |

### 명령어 / 도구

| 용어 | 한국어 풀이 | 설명 |
|------|------------|------|
| **MCP** (Model Context Protocol) | (그대로) | Claude 등이 외부 도구를 호출하는 표준 프로토콜. |
| **Hook** | 훅 / 갈고리 | 특정 이벤트(세션 시작, 도구 사용 후 등)에 자동 실행되는 스크립트. |
| **PostToolUse** | 도구 사용 후 | Claude가 도구 호출을 마친 직후 트리거되는 hook 시점. |
| **session-start** | 세션 시작 | Claude Code가 새 세션을 시작할 때 트리거되는 hook 시점. |
