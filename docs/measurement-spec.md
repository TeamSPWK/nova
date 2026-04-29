# Measurement Spec — KPI 4종 데이터 계약

> Nova Engineering — measurement-closed-loop Sprint 1 (Phase 0 spec)
> 작성일: 2026-04-29
> Plan: docs/plans/measurement-closed-loop.md
> Design: docs/designs/measurement-closed-loop.md
> 본 문서는 측정 파이프라인의 **단일 데이터 계약**이다. publish-metrics.sh, metrics-validation.yml, README badge, nova-metrics repo(Phase 2) 모두 본 spec에 종속한다.

---

## 1. KPI 4종 정의

| # | KPI | 한국어 라벨 | 분자 | 분모 | n_threshold | 데이터 소스 |
|---|-----|------------|------|------|-------------|-------------|
| 1 | `process_consistency` | Process Consistency | 같은 `orchestration_id`에 `plan_created`가 `sprint_completed` 이전에 존재하는 sprint 수 | `sprint_completed`(planned_files≥3) 총수 | 10 | events.jsonl |
| 2 | `gap_detection_rate` | Gap Detection Rate | `evaluator_verdict=FAIL` 이후 같은 orchestration에서 `sprint_completed=PASS` 또는 `phase_transition=completed` 발생한 FAIL 수 | `evaluator_verdict=FAIL` 총수 | 10 | events.jsonl |
| 3 | `rule_evolution_rate` | Rule Evolution Rate | `evolve_decision` 이벤트 중 `extra.decision == "accept"` | `evolve_decision` 이벤트 총수 | 10 | events.jsonl (재정의, 본 spec) |
| 4 | `multi_perspective_impact` | Multi-Perspective Impact | `jury_verdict` 이벤트 중 `extra.changed_direction == true` | `jury_verdict` 이벤트 총수 | 5 | events.jsonl |

**임계값(n_threshold) 결정 근거**:
- KPI 1·2·3 = 10: 100% 정밀도가 무의미해지는 최소 분모. 10건 미만이면 단일 노이즈 1건이 ±10% 변동을 야기.
- KPI 4 = 5: jury는 비용 ~50K로 고비용 이벤트, 현실적 자연 발생 빈도가 낮음. 5건이면 분포 의미 시작.

---

## 2. n 임계 미달 처리 (badge gray-out 책임)

**원칙**: n < n_threshold 시 KPI는 **모든 파이프라인 단계에서 gray-out + insufficient 라벨**을 강제한다.

| 단계 | 책임 |
|------|------|
| `nova-metrics.sh --json` | `pct: null`, `status: "insufficient"`, `badge_url`에 `lightgrey` 색상 + `n%3D{n}%20insufficient` 텍스트 |
| `publish-metrics.sh` | nova-metrics 출력 그대로 통과 (재산출 X). 단 `cwd_hash`/`session_id` strip 재검증 |
| `metrics-validation.yml` | `pct=null`이면 `status=insufficient` 강제 매칭. 위반 시 schema fail |
| README badge 영역 | shields.io URL 그대로 임베드 — gray가 보이는 게 정직성 신호 |
| nova-metrics repo (Phase 2) | 시계열 그래프에서 insufficient 구간을 점선 또는 회색 음영으로 표시 |

**메모리 정합** (`feedback_evidence_first_identity`): 측정 정체성은 **n 임계 통과 후**에만 주장한다. n=2에서 "78% Process Consistency" 표시 금지 — gray-out으로 honest 노출.

---

## 3. schema_version 정책

### events.jsonl schema_version

| 버전 | 도입 시점 | 의미 | 처리 |
|------|----------|------|------|
| 1 (또는 미명시) | v5.19.x 이전 | 초기 스키마. 일부 필드 누락 가능 | nova-metrics.sh가 best-effort 매핑. KPI 산출 시 누락 시 0 |
| 2 | v5.20.0+ | 현재 스키마 (timestamp ms / monotonic_ns / cwd_hash / session_id 정착) | 우선 처리 대상 |

### baselines JSON schema_version

| 버전 | 의미 |
|------|------|
| 1 (현재) | KPI 4종 + period + delta + badge_url. 본 spec 정의 |

**drift 처리**: 같은 주(week)에 v1+v2 혼재 시, 우세 버전(많은 쪽)을 `events_schema_version`에 기록. drift가 50:50이면 v2 우선 (전향).

---

## 4. baselines JSON schema (출력 — 공개 commit)

```jsonc
{
  "schema_version": 1,
  "period": "2026-W18",                  // YYYY-WNN (ISO 8601 week, UTC)
  "period_start": "2026-04-27",          // 월요일 (UTC)
  "period_end": "2026-05-03",            // 일요일 (UTC)
  "nova_version": "5.23.1",              // scripts/.nova-version
  "events_schema_version": 2,            // 우세 events.jsonl 버전
  "kpis": [
    {
      "kpi": "process_consistency",      // KPI key (snake_case)
      "label": "Process Consistency",     // 사람용 라벨
      "pct": null,                        // null | 0~100 정수
      "n": 0,                             // 분모 (음수 불가)
      "n_threshold": 10,
      "status": "insufficient",           // sufficient | insufficient
      "delta_pct": null,                  // null | 변화율 %p (전주 대비)
      "badge_url": "https://img.shields.io/badge/process_consistency-n%3D0%20insufficient-lightgrey"
    }
    // ... 4 KPI 모두 동일 구조
  ]
}
```

**필드 변환 규칙**:
- `pct`: `(num * 100) / den` 정수 절사. n<n_threshold면 강제 null.
- `delta_pct`: `(현재 pct - 이전 pct)`. 첫 주 또는 한쪽이 null이면 null. **단위는 %p이지 % 아님**.
- `period`: `date -u +%G-W%V` (Linux/macOS 호환).
- `badge_url`: shields.io URL encode 강제 (% → %25, 공백 → %20).

**금지 필드** (publish 단계에서 strip):
- `cwd_hash`, `session_id`, raw `events`, `extra` (개별 이벤트 페이로드).
- 위반 시 metrics-validation.yml가 PR 차단 + Issue 자동 생성.

---

## 5. session_id 갱신 정책 — 의도된 재사용

**현행 동작 검증** (record-event.sh:64-80):
- `.nova/session.id` 파일에 SHA-256 12자 ID 영구 저장.
- 파일 부재 시에만 신규 생성 (`PWD + PID + random` → SHA-256).
- 같은 디렉토리(프로젝트)의 모든 세션이 동일 session_id를 공유.

**판정**: **의도된 재사용** (코드 주석 "프로젝트/세션 격리, privacy-safe, race-safe atomic 발급" — 명시적 의도). 버그 아님.

**의미 명확화**:
- 이름은 `session_id`이지만 실제 동작은 **프로젝트별 영구 익명 ID** (project-local pseudonym).
- 의미 mismatch 존재하지만 **개명하지 않음**:
  - 이미 v5.20.0+ 데이터 누적 (events.jsonl 31795 records — v5.20.0 baseline).
  - 해석 변경은 v1↔v2 호환성 추가 부담.
  - KPI 산출은 `orchestration_id`를 군집화 키로 사용 — `session_id`는 KPI에 직접 영향 없음.
- privacy 관점에서 안전 (PWD 평문 노출 없음, SHA-256 12자).

**Spec 결정**:
- session_id는 **KPI 산출 키로 사용 금지**. orchestration_id가 군집화 키.
- baselines JSON 출력에서 session_id 강제 strip (publish-metrics.sh 단계).
- 추후 진짜 "실행 세션" 구분 필요 시 별도 필드 추가 (`run_id` 등) — 현재 spec 대상 아님.

---

## 6. KPI 3 재정의 — evolve_decision 이벤트 기반

### KPI 3 — 결정 요약

- **결정**: events.jsonl `evolve_decision` 이벤트 기반으로 재정의. rules-changelog.md grep 폐기.
- **emit 지점**: `record-event.sh evolve_decision '{"pattern_id":"...","decision":"accept|reject"}'` (Sprint 2+에서 `/nova:evolve` 및 evolution 스킬 내부에 추가).
- **이행 시점**: 본 spec(Sprint 1) = 계약 정의만. Sprint 2 = nova-metrics.sh 산출 로직 교체. 별도 작업 = emit 지점 실제 추가.

### 현행 구현 결함 (nova-metrics.sh:121-131)

```bash
RULES_LOG="docs/rules-changelog.md"
re_den=$(grep -c '^## .* — proposed' "$RULES_LOG")
re_num=$(grep -c '^## .* — approved' "$RULES_LOG")
```

**문제**:
- rules-changelog.md 실제 형식은 `## [YYYY-MM-DD] {규칙명}` — `— proposed`/`— approved` 패턴 부재.
- 결과: 항상 0/0 반환 (false negative — 측정 안 됨).
- events.jsonl 측정 인프라와 분리 — closed-loop 깨짐.

### 재정의 결정: evolve_decision 이벤트 기반

**선택 이유**:
- closed-loop 원칙 (events.jsonl이 단일 데이터 소스).
- KPI 1·2·4와 일관 (모두 events.jsonl 기반).
- 임계값 적용 자연스러움 (이벤트 카운트).

**계산식**:
- 분모: `event_type == "evolve_decision"` 이벤트 총수.
- 분자: 분모 중 `extra.decision == "accept"` 이벤트 수.

**emit 지점** (Sprint 2+ 또는 별도 작업):
- `/nova:evolve` 커맨드가 외부 기술 동향 분석 → 사용자 결정 시점.
- evolve 스킬(`skills/evolution/SKILL.md`)이 채택/거부 판단 시.
- 호출: `bash hooks/record-event.sh evolve_decision '{"pattern_id":"<8자hex>","decision":"accept|reject"}'`.

**현재 상태** (Sprint 1 종료 시점):
- emit 지점 0개. 즉, 본 spec 적용 후에도 KPI 3 = 0/0 (insufficient gray).
- 의도적: emit은 Sprint 2+ 작업. spec 단계에서는 **계약**만 정의.

**rules-changelog.md 처리**:
- 사람 가독용 변경 이력으로 유지 (자동 산출 입력 아님).
- nova-metrics.sh의 grep 로직은 **Sprint 2에서 제거** (evolve_decision 이벤트 카운트로 교체).
- 본 spec 이후 `re_num = events.jsonl evolve_decision accept`, `re_den = events.jsonl evolve_decision`.

---

## 7. Phase 2 인프라 설계 (deferred — 진입 트리거 충족 시)

### 7.1 Phase 2 진입 트리거

**조건**: Sprint 3 완료 + 4주 누적 후 KPI 4종 중 **2개 이상 분모 ≥ 10** 도달.

**의미**: 단일 KPI sufficient는 우연일 수 있으나 2개 이상이면 dogfood 데이터가 시각화할 가치를 갖춤. n>1 원칙(`nova_spike_skill_deferred` 메모리)과 일관.

**트리거 도달 시 사용자 결정 사항**:
- nova-metrics repo 부트스트랩 시점.
- Astro 빌드 파이프라인 도입 여부.
- 별도 Design 문서 (`measurement-visualization.md`) 작성 후 진행.

### 7.2 jay-swk/nova-metrics repo 구조

```
nova-metrics/                            # 별도 repo (private 또는 public 미정)
├── README.md                            # repo 목적 + KPI 정의 링크 (본 spec 인용)
├── package.json                         # Astro + Observable Plot
├── astro.config.mjs
├── src/
│   ├── pages/
│   │   ├── index.astro                  # 메인 대시보드 (4 KPI 시계열)
│   │   ├── kpi/[name].astro             # KPI별 상세 (drilldown)
│   │   └── api/baselines.json.ts        # raw baselines aggregator (선택)
│   ├── components/
│   │   ├── KpiBadge.astro
│   │   ├── KpiTimeseries.astro          # Observable Plot 시계열
│   │   └── InsufficientNotice.astro     # n<임계 honest 표시
│   └── data/
│       └── fetch-baselines.ts            # cross-repo fetch 로직
├── public/
│   └── favicon.svg
└── .github/workflows/
    └── deploy.yml                        # GitHub Pages 배포
```

### 7.3 cross-repo 데이터 흐름

**선택**: **raw GitHub URL fetch** (submodule 아님).

| 옵션 | 채택? | 이유 |
|------|------|------|
| git submodule | X | 부모 repo 안에 .git 등록되면 빌드 복잡도 증가. `feedback_fixture_no_git_init` 메모리 — 동일 사고 재발 위험 |
| GitHub raw URL fetch | O | `https://raw.githubusercontent.com/TeamSPWK/nova/main/docs/baselines/*.json` 직접 fetch. 빌드 시점 캐시 |
| GitHub API + token | △ | rate limit 우회 가능하나 PAT 관리 비용. 공개 raw URL로 충분 |

**Astro 빌드 시퀀스**:
1. Astro `getStaticPaths()` 단계에서 `https://api.github.com/repos/TeamSPWK/nova/contents/docs/baselines` 디렉토리 listing.
2. 각 `*.json` raw URL을 fetch (Astro Content Collections 또는 직접 fetch).
3. 빌드 시점에 정적 HTML 생성 — runtime fetch 0.
4. Cache-Control: 1시간 (어차피 baselines는 주 1회 갱신).

### 7.4 Astro 빌드 파이프라인 진입점

```typescript
// nova-metrics/src/data/fetch-baselines.ts
const REPO = "TeamSPWK/nova";
const BRANCH = "main";
const BASELINES_PATH = "docs/baselines";

export async function fetchBaselines() {
  const listing = await fetch(
    `https://api.github.com/repos/${REPO}/contents/${BASELINES_PATH}?ref=${BRANCH}`
  ).then(r => r.json());

  const baselines = await Promise.all(
    listing
      .filter((f: any) => f.name.endsWith(".json"))
      .map(async (f: any) => {
        const data = await fetch(f.download_url).then(r => r.json());
        return { period: data.period, ...data };
      })
  );

  return baselines.sort((a, b) => a.period.localeCompare(b.period));
}
```

### 7.5 GitHub Pages 배포

- repo: `jay-swk/nova-metrics` (가칭, 시작 시점 jay 개인 또는 TeamSPWK 결정).
- 도메인: `<repo-owner>.github.io/nova-metrics/` 시작 → 안정 후 custom 도메인 검토.
- 트리거: `nova` repo의 `docs/baselines/*.json` 갱신 시 cross-repo dispatch (옵션). 또는 nova-metrics에서 cron(주 1회) fetch.

---

## 8. Phase 3 future hook (deferred 명시)

본 spec은 Phase 0~2 데이터 계약만 정의한다. Phase 3는 별도 시점 결정:

| Phase 3 후보 | 트리거 |
|--------------|--------|
| 외부 사용자 opt-in 제출 (federated) | 외부 사용자 n>1 도달 (Nova 채택 사례 발생) |
| 비교 KPI (다른 AI Agent Ops) | Phase 2 시계열 안정 후 비교 가치 발생 |
| Cost-per-decision KPI | 청구 데이터 통합 가능 시 (현재 직접 측정 불가) |
| Behavior reproducibility (idempotency) | AXIS-I 측정 인프라 확장 필요 |

**Phase 3 진입 차단 조건**: 외부 사용자 데이터 수집 시 GDPR/PII 검토 필수. 현 spec은 self-only metrics 가정.

---

## 메모리 정합

| 메모리 | 정합 |
|--------|------|
| `feedback_evidence_first_identity` | n<임계 시 모든 단계 gray-out 강제. 정체성 어휘는 본 spec에 미사용 |
| `nova_spike_skill_deferred` | Phase 2 진입을 KPI 2개 이상 sufficient로 차단 — n>1 원칙 |
| `feedback_no_manual_setup` | session_id 정책: 사용자 수동 변경 0. publish-metrics.sh 1회 실행만 명시적 |
| `nova_universal_plugin` | KPI 정의에 SWK 프로젝트명 0. 익명 schema만 |
| `feedback_fixture_no_git_init` | Phase 2 cross-repo는 submodule 거부, raw URL fetch 채택 |
| `feedback_release_sh_staging_trap` | baselines 출력은 publish-metrics.sh 단일 책임 — release.sh와 분리 |
