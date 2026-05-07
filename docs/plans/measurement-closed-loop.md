# [Plan] Measurement Closed-Loop — events.jsonl 후험 활용 (흡수→측정→입증)

> Nova Engineering — CPS Framework
> 작성일: 2026-04-29
> 작성자: Nova DeepPlan
> Mode: deep
> Iterations: 1 (Critic FAIL → Refiner 1회 → Critic PASS)
> Design: designs/measurement-closed-loop.md

---

## Context (배경)

### 현재 상태

Nova v5.23.1 기준 측정 인프라는 거의 완비 상태이나 **활용 채널이 부재**한 단방향 파이프다.

**완비된 것** (재사용 대상):
- `scripts/nova-metrics.sh` — KPI 4종 산출 (Process consistency / Gap detection rate / Rule evolution rate / Multi-perspective)
- `scripts/_metrics-helpers.py` — KPI 산출 helper (stdin JSONL → numerator/denominator)
- `scripts/analyze-observations.sh` (521줄) — 행동 패턴 분석 (tool-frequency, sequence, failures, confidence 4종)
- `scripts/log-metric.sh` — 메트릭 이벤트 append + rotation (1000줄)
- `scripts/snapshot-baseline.sh` — baseline 스냅샷 자동 생성 (5 섹션 markdown)
- `hooks/record-event.sh` — JSONL 이벤트 기록 (schema v2, flock/mkdir fallback, privacy filter)
- `hooks/pre-tool-use-record.sh` + `hooks/stop-event.sh` — 자동 이벤트 수집
- `hooks/_privacy-filter.py` — 14 패턴 + Shannon entropy 필터
- `.nova/events.jsonl` — 3,063줄 누적 (11일치, 2026-04-19~04-29)

**부재한 것** (이번 Plan 대상):
- 주간 자동 갱신 GitHub Actions 워크플로우
- README badge 외부 가시성
- 시계열 시각화 채널 (정적 사이트)
- KPI 정의 문서 (`docs/measurement-spec.md`)
- n 임계값 정책 + gray-out UI

### 왜 필요한가

ECC 흡수(P0~P2-3)로 **외부 카탈로그 입력**은 닫혔다. 다음 자연스러운 단계는 **출력 측면 = 흡수한 룰의 효과를 측정·입증하는 closed loop 완성**. 메모리 `feedback_evidence_first_identity` 정합 — "정체성은 효과 측정 후 발견". 측정 인프라 → 효과 입증 → 후험적 정체성 승격이 닫혀야 ECC 흡수가 의미를 갖는다.

v5.20.0에 깔린 measurement-infrastructure가 데이터를 쌓고 있으나(11일치 3,063줄: tool_call 1821 / session_start 1010 / session_end 196 / commit_blocked 5 / evaluator_verdict 3 / jury_verdict 1) 매몰비용 회수가 0인 상태.

### 관련 자료

- `docs/plans/measurement-infrastructure.md` — v5.20.0 측정 인프라 plan (PASS, done)
- `docs/baselines/v5.20.0-baseline.md` — 수동 스냅샷 (2,194줄 기준선)
- `docs/proposals/2026-04-29-ecc-adversarial-gap.md` — ECC 흡수 출처 (P0~P2-3 클로저)
- `.github/workflows/ci.yml` (기존) + `.github/workflows/notify-landing.yml` (기존, repository_dispatch 패턴 검증됨)
- 외부: `jay-swk/nova-landing` (Next.js 랜딩, v3.12 멈춤 상태) — 분리/재활성화 논의 대상

---

## Problem (문제 정의)

### 핵심 문제

**measurement infrastructure가 단방향 파이프 상태 — 데이터는 쌓이나 활용 채널 0**. ECC 흡수 효과를 측정·입증할 closed loop가 부재하므로, "정체성은 효과 측정 후 발견" 원칙을 실행할 수단이 없다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| P1 | KPI 정의 부재 | `docs/measurement-spec.md` 미작성. 4 KPI의 분자/분모/n 임계값/공개 필드 범위가 코드(nova-metrics.sh) 에만 묵시적 존재. schema drift 시 추적 불가 | High |
| P2 | 자동화 채널 부재 | 주간 cron으로 nova-metrics.sh를 실행해 baseline JSON commit + badge 갱신하는 GitHub Actions 부재 | High |
| P3 | 외부 가시성 0 | README에 측정 결과 노출 채널 없음. nova-landing(별도 repo)도 멈춤 상태 | Medium |
| P4 | 시계열 시각화 부재 | 단일 baseline.md(스냅샷)만 존재. 추세·변화율·KPI간 상관 시각화 0 | Medium |
| P5 | n=1 dogfood 함정 | 3,063줄 전체가 단일 session_id, 단일 cwd_hash. 외부 노출 시 통계적 환상 위험 | **High** (risk-explorer 발견) |
| P6 | KPI 3 dead metric | `rule_evolution_rate`의 grep 패턴(`^## .* — proposed`)이 `rules-changelog.md` 실제 형식(`### [YYYY-MM-DD]`)과 영구 불일치 | **High** (risk-explorer 발견) |
| P7 | schema drift 미해소 | 같은 날(2026-04-29) v1 209건 + v2 746건 교차 기록. snapshot-baseline.sh가 v2를 0건으로 잘못 카운트한 의심 | **High** (risk-explorer 발견) |
| P8 | **GitHub Actions 데이터 접근 공백** | `.nova/`가 `.gitignore` 50번 라인에 있어 Actions checkout 후 `events.jsonl` 부재. `nova-metrics.sh`가 분모 0 → KPI 전부 N/A 파이프라인. Phase 1 작동 불가 | **Critical** (Critic 발견) |

### 의도적 scope-out (MECE 완결성)

본 Plan은 다음 영역을 의도적으로 제외한다 — 향후 별도 Plan으로 재검토:

- **성능/지연 메트릭(`duration_ms`)**: PostToolUse hook(v5.21.0 Spike) 미검증. 데이터 수집 인프라 부재. Phase 2 또는 별도 Plan에서 재검토.
- **에러율 / commit_blocked 발화율**: 5건 데이터 존재하나 KPI 4종 외 별도 모니터링. Phase 2 진입 시점에 K5로 추가 검토.
- **비용 측정 (Anthropic API 토큰)**: Nova는 사용자 키 의존이라 비용 데이터 부재. Out of scope.
- **MECE 보강**: P5(n=1 함정)와 P6(dead metric)은 결과적 유사성("KPI 신뢰 불가")이 있으나 원인이 분리 — P5는 데이터 양 부족, P6는 정의 오류. Mutually Exclusive 인정.

### 제약 조건

**기술적 제약** (code-explorer 발견):
- nova-metrics.sh 출력이 **stdout 텍스트 전용** — badge shields.io 연동을 위해 `--json` 모드 신규 추가 필요
- PostToolUse hook(v5.21.0 Spike) 미검증 — `duration_ms` 필드 기록 불가 → "도구 평균 시간" KPI 추가 보류
- worktree 신뢰도 왜곡 — session_id가 CWD 기반 해시이므로 worktree A/B가 분리 JSONL 생성 (v5.20.0 scope-out 그대로 유지)
- mcp-server 하위에 별도 events.jsonl 존재 (2줄) — 집계 범위 명시 필요

**구조적 제약** (risk-explorer 발견):
- 단일 사용자 dogfood — 통계적 의미 0인데 신뢰도 환상 줄 위험
- cwd_hash SHA-256 앞 8자리는 브루트포스 역산 가능 — 공개 시 환경 프로파일링 위험
- events.jsonl 단일 파일 append-only — 손상/truncation 무감지

**운영 제약**:
- 1인 운영 환경 — 별도 repo 부트스트랩 비용은 회수 시점이 외부 사용자 신호에 종속

---

## Solution (해결 방안)

### **데이터 흐름 결정 (Critic Critical #1 해소)**

`.nova/events.jsonl`은 `.gitignore` 처리 유지(privacy). 따라서 **GitHub Actions가 직접 측정하지 않는다**. 자동화 모델 재설계:

**자동화 모델: 로컬 측정 + Actions 보조**
1. **로컬 (사용자 책임, 주간 리츄얼)**: `bash scripts/publish-metrics.sh` 실행 → `nova-metrics.sh --json` → `docs/baselines/{YYYY-WNN}.json` 생성 + commit. privacy filter 검증 + cwd_hash/session_id 등 식별 필드 strip 후 집계만 commit.
2. **GitHub Actions (자동)**: `docs/baselines/*.json` 변경 감지 → README badge 마크다운 영역 자동 갱신 + 정합성 검증(JSON schema 위배·금지 필드 포함 등) + 검증 실패 시 PR 또는 Issue.
3. **주간 cron**: Actions가 직접 측정하지 않으므로 cron 의존 제거. 대신 사용자가 4주 이상 publish-metrics.sh 미실행 시 NOVA-STATE에 리마인더 출력.

**선택 근거**:
- privacy 보장 (events.jsonl 비공개 유지)
- 사용자 명시 결정으로 baseline commit (silent failure 위험 제거)
- 1인 운영 부담: 주 1회 명령 1개 실행 (≤30초)
- evidence_first_identity 정합 (사용자가 직접 측정 → 의도적 입증)

### 선택한 방안: **방안 C (YAGNI 우선)** ⭐

option-explorer 권장. Phase 0(spec) + Phase 1(badge + baselines)을 nova main repo에서 즉시 진행하고, **Phase 2(nova-metrics 별도 repo + Astro + Observable Plot)는 데이터 임계 도달 시 진입**한다.

**선택 근거**:
1. **사용자 결정 5개 모두 보존** — opt-in 보류, repo 분리, Astro+Plot, github.io, n 솔직 노출. 폐기 항목 0.
2. **메모리 `evidence_first_identity` 정합** — 측정 → 효과 입증 → 시각화는 데이터 충분할 때 의미. n=1 시점 Astro 부트스트랩은 환상 강화.
3. **메모리 `nova_spike_skill_deferred` 정합** — "n>1 신호 시 진입" 원칙. 방안 C는 KPI별 분모 임계값(예: 각 KPI ≥ 10)을 명시적 트리거로 사용.
4. **재작업 비용 0** — Phase 1에서 commit하는 `docs/baselines/{week}.json`이 Phase 2 Astro 빌드 입력으로 그대로 재사용. Phase 2 진입 시 schema/필드명 변경 없음.
5. **1인 운영 부담 최소** — Phase 2 nova-metrics repo 부트스트랩(Astro 세팅, GH Pages 권한, DNS 등) 비용을 외부 신호 시점까지 deferred.

**vs 사용자 "임시 아닌 미래" 의도와의 정합**:
방안 C는 Phase 2를 **폐기하지 않는다**. Phase 0 spec에서 **Phase 2 인프라 설계를 미리 명시**(JSON schema, repo 구조, Astro 빌드 진입점)하여 미래 진입 비용을 최소화. "지금 만들지 않을 뿐 설계는 완료" 상태로 미래형 보장.

### **방안 B 트렌드 아이디어 partial 흡수 결정 (Critic Medium #5 해소)**

방안 B의 "트렌드(변화율) 표시" 아이디어는 Phase 1.5로 흡수한다:
- **Phase 1**: 절대값 + n 명시 + gray-out (n<임계 시)
- **Phase 1.5 (조건부 자동 진입)**: baselines가 **2주 이상 누적**되면 README badge에 "전주 대비 ±N%p" 추가 표기 활성화. n=2 이상이면 변화율은 직관적 의미 있음 (n=1은 절대값만, n=2부터 delta 가능)
- **트리거**: `docs/baselines/*.json` 파일 수가 ≥2일 때 publish-metrics.sh가 자동으로 delta 계산 + badge 영역에 추가

이로써 방안 B의 가치 있는 아이디어를 채택하되, 방안 C의 단계적 가시성 진화 구조를 보존.

### 대안 비교

| 방안 | 접근 | 장점 | 단점 | 권장도 |
|------|------|------|------|--------|
| A (안전 직렬) | Phase 0 PASS → Phase 1 PASS → Phase 2 직렬. spec 선행 후 단계별 진행. nova-metrics repo + Actions dispatch 즉시 부트스트랩 | schema 안정화 후 파이프라인 → 필드명 변경 비용 0. 각 Phase 독립 검증 | Phase 2 시작 가장 느림. 1인 운영에서 spec PASS 판단 기준 주관적. badge 늦게 노출 | |
| B (병렬 가속) | Phase 0 + 1 동시 진행. monorepo 가짜 분리(nova/metrics/ + gh-pages 브랜치). 트렌드(변화율)만 표시 | badge 빠른 노출. 트렌드 표시로 n 부족 시 절대값 오해 차단 | spec 미확정 상태에서 파이프라인 구성 시 재작업. gh-pages 브랜치 nova-landing과 충돌 위험. n<3 시 변화율 자체 무의미 | |
| C (YAGNI 우선) | Phase 0 + 1만 즉시. Phase 2는 KPI 분모 ≥ 10 도달 시 진입. baselines JSON nova main repo 축적 | 즉시 환수 가능 비용만 지출. baselines JSON은 Phase 2 그대로 재사용. evidence_first_identity 구조적 강제. YAGNI + 실증 | 시각화 부재 → 외부 가시성 텍스트 badge 한정. Phase 2 진입 시점 데이터 종속 → 타임라인 불확실 | ⭐ |

**권장 방안**: C — 1인 운영 + 외부 사용자 미활성 + n=1 dogfood 맥락에서 nova-metrics repo 전체 부트스트랩은 환수 불가 비용. baselines JSON 재사용성으로 Phase 2 전환 비용 0. evidence_first_identity 메모리와 구조적으로 일치.

### 구현 범위

#### Phase 0 — 측정 명세 (Spec) 정밀화

- [ ] `docs/measurement-spec.md` 신규 작성 (300~500줄 목표)
  - [ ] events.jsonl schema v2 공식 정의 (필수/선택/nullable 필드)
  - [ ] schema_version 분기 정책 (v1↔v2 혼재 처리: `select(.schema_version==2)` 필터 또는 v1→v2 매핑 레이어)
  - [ ] **KPI 4종 공식**: 분자/분모 이벤트 종류 + n 임계값 + 의미 단위
    - KPI 1: Process consistency = `sprint_completed && evaluator_verdict.PASS` / `sprint_completed`. 임계 n≥10
    - KPI 2: Gap detection rate = `gap_detected` / `plan_created`. 임계 n≥10
    - KPI 3: Rule evolution rate **재정의 필수** — `rules-changelog.md` 실제 형식(`### [YYYY-MM-DD]`)에 맞게 grep 재작성 **또는** evolve_decision 이벤트 기반으로 전면 교체. 후자 선택 시 `evolve_decision` 이벤트 emit 지점(어느 hook/script가 발화할지)을 spec에 명시 + Sprint 1에서 emit 추가 구현 포함
    - KPI 4: Multi-perspective = `jury_verdict` / `evaluator_verdict`. 임계 n≥5
  - [ ] **session_id 재사용 문제 사전 조사** (Sprint 1 시작 전 필수): record-event.sh 분석 → 의도된 동작 vs 버그 판정 → spec에 결과 반영. 버그면 hook 수정 + 기존 3,063줄 사용 정책 결정
  - [ ] **n<임계 노출 정책**: gray-out + n 명시 (배지 형식: `kpi_name | n=3 | insufficient`)
  - [ ] **badge gray-out 구현 책임 결정 (Critic Medium #6)**: 선택지 (a) `nova-metrics.sh --json`이 `badge_url` 필드 포함 (b) workflow가 `jq`로 shields.io URL 조합 (c) 정적 SVG commit. **권장 (a)** — script 단일 책임 + 환경 독립
  - [ ] **baselines JSON schema** (Phase 1 commit 대상) — 공개 필드 범위 명시
    - 포함: kpi 이름, pct 또는 raw, n, period, schema_version, badge_url(옵션)
    - **제외**: cwd_hash, session_id, raw events (Privacy 강제)
  - [ ] **mcp-server 하위 events.jsonl 처리 정책** (집계 포함 vs 제외 명시)
  - [ ] **Phase 2 인프라 설계 미리 명시** (재작업 비용 0):
    - jay-swk/nova-metrics repo 구조 (data/baselines, data/schema, web/astro, .github/workflows)
    - Astro + Observable Plot 빌드 진입점
    - GitHub Pages 배포 정책 (n<임계 시 컴포넌트 gray-out)
    - cross-repo 데이터 흐름 (raw GitHub URL fetch vs git submodule — 결정)
  - [ ] **Phase 2 진입 트리거 명시**: "각 KPI 분모가 임계값 도달 시 자동 알림 또는 사용자 결정"
  - [ ] **Phase 3 future hook**: opt-in 텔레메트리 명시만 (구현 0)

#### Phase 1 — 자기 측정 + 외부 가시성 (자동화 모델 재설계 후)

- [ ] `scripts/nova-metrics.sh`에 `--json` 출력 모드 추가
  - 기존 텍스트 경로 무변경 (회귀 0 보장)
  - 출력 형식: `[{"kpi":"process_consistency","pct":78,"n":41,"schema_version":2,"period":"2026-W18","badge_url":"https://img.shields.io/..."}, ...]`
  - n<임계 시 `pct: null`, `badge_url`은 gray + "n=N" 명시
- [ ] `scripts/publish-metrics.sh` **신규** — 사용자 로컬 주간 리츄얼 (Critical #1 해소)
  - 단계: nova-metrics.sh --json 실행 → privacy 검증(cwd_hash/session_id 등 식별 필드 strip) → docs/baselines/{YYYY-WNN}.json 생성 → 변화율 계산 (이전 주 baselines 존재 시) → README badge 영역 로컬 갱신 → git pull --rebase 사전 실행(실패 시 exit 2 + 사용자 안내) → git diff 출력 후 사용자 commit 안내
  - 실패 시 stderr 명시 (silent failure 차단)
- [ ] **세션 시작 리마인더 통합 (Critic Iter2 Medium 권고)**: `hooks/session-start.sh` 또는 `scripts/init-nova-state.sh`에 "최신 baselines 파일 날짜 4주 초과 시 리마인더 출력" 로직 추가 — publish-metrics.sh 미실행 의존성 제거. lean ≤1200자 예산 보호 (1줄 알림만)
- [ ] `.github/workflows/metrics-validation.yml` **신규** (cron 의존 제거)
  - 트리거: `pull_request` paths `docs/baselines/**.json` + `push` to main
  - 단계: baselines JSON schema 검증 (jq) → 금지 필드 검사(cwd_hash/session_id 등) 위배 시 `exit 1` → README badge 영역 정합성 확인 → 실패 시 PR 코멘트 또는 Issue 자동 생성
  - 빌드 환경: ubuntu-latest, jq 의존성
- [ ] `docs/baselines/.gitkeep` + `docs/baselines/schema.json` 신규 (JSON schema 정의)
- [ ] `README.md` + `README.ko.md`에 4 KPI badge 영역 (AUTO-GEN 마커 기반)
  - badge URL은 baselines JSON의 `badge_url` 필드 사용
  - n<임계 시 gray badge + "n=N" 명시
- [ ] `tests/test-scripts.sh` 회귀 가드 추가 (`nova-metrics.sh --json` 구조 검증, publish-metrics.sh privacy strip 검증, schema_version 분기 검증, fixture 기반 KPI 산출 검증)
- [ ] **fixture**: `tests/fixtures/events-sample.jsonl` 신규 — KPI 산출 단위 테스트용 (3 schema_version 혼재 + 다양한 event_type 포함)

#### Phase 2 — 시각화 (deferred until trigger)

- [ ] **트리거**: 각 KPI 분모 ≥ 10 또는 사용자 명시 결정
- [ ] `jay-swk/nova-metrics` repo 신규 생성
- [ ] Astro + Observable Plot 정적 빌드
- [ ] GitHub Pages 배포 (github.io URL)
- [ ] cross-repo 데이터 흐름 구현 (Phase 0 spec 결정 기반)
- [ ] `metrics.{nova-version}.json` 시계열 fetch + 컴포넌트별 gray-out UI

> Phase 2는 본 Plan에서 인프라 설계만 명시. 실 구현은 별도 Plan(`measurement-visualization.md`) 후속.

#### Phase 3 — Opt-in 텔레메트리 (future hook only)

- [ ] (구현 X) Plan에 명시만 — 외부 사용자 n>1 신호 시 별도 Plan

### 검증 기준

(상세는 `## Verification Hooks` 섹션 참조)

핵심 게이트:
1. Phase 0: `docs/measurement-spec.md`이 5 결정 + KPI 4종 + n 임계 + Phase 2 설계 모두 명시
2. Phase 1: GitHub Actions가 매주 자동 실행 → baselines JSON commit + README badge 갱신 + 실패 시 Issue
3. 회귀 0: tests/test-scripts.sh 538/538 (+신규 assert) 통과
4. nova-metrics.sh `--json` 신규 모드 + 기존 텍스트 모드 양쪽 검증

---

## Sprints (스프린트 분할)

수정/생성 파일 8+ 예상 → 3 sprint 분할.

### Sprint 1 — Phase 0 Spec

| 파일 | 동작 | 비고 |
|------|------|------|
| `docs/measurement-spec.md` | 신규 | 300~500줄. KPI 4종 + n 임계 + schema 분기 + baselines JSON schema + Phase 2 인프라 설계 |
| `tests/test-scripts.sh` | 보강 | spec 파일 존재 + 핵심 섹션 헤더 회귀 가드 (3~5 assert) |

**완료 조건**: spec 파일 + 회귀 가드 PASS. evaluator(Plan 검증 모드) 검토 PASS.

### Sprint 2 — Phase 1 nova-metrics.sh JSON 모드 + 회귀 가드

| 파일 | 동작 | 비고 |
|------|------|------|
| `scripts/nova-metrics.sh` | 보강 | `--json` 플래그 추가. 기존 텍스트 출력 경로 무변경 |
| `tests/test-scripts.sh` | 보강 | --json 출력 구조 검증 + 텍스트 모드 회귀 가드 (4~6 assert) |
| `scripts/_metrics-helpers.py` | 필요 시 보강 | JSON 직렬화 helper 추가 가능 |

**완료 조건**: nova-metrics.sh --json 동작 + 538/538 회귀 0. evaluator PASS.

### Sprint 3 — Phase 1 publish-metrics.sh + Validation Workflow + README badge

| 파일 | 동작 | 비고 |
|------|------|------|
| `scripts/publish-metrics.sh` | 신규 | 사용자 로컬 주간 리츄얼. nova-metrics.sh --json + privacy strip + baselines commit 안내 + Phase 1.5 delta 계산 |
| `.github/workflows/metrics-validation.yml` | 신규 | baselines JSON 변경 감지 → schema 검증 + 금지 필드 차단 + 검증 실패 시 PR 코멘트/Issue |
| `docs/baselines/.gitkeep` | 신규 | 디렉토리 보존 |
| `docs/baselines/schema.json` | 신규 | baselines JSON schema 정의 (필수/금지 필드) |
| `tests/fixtures/events-sample.jsonl` | 신규 | v1+v2 혼재 fixture (KPI 산출 단위 테스트용) |
| `README.md` | 보강 | AUTO-GEN 마커 + 4 KPI badge 영역 |
| `README.ko.md` | 보강 | 동일 |
| `scripts/release.sh` | 보강 | Step 2.5에 `.nova/` 실수 commit 차단 가드 추가 |
| `tests/test-scripts.sh` | 보강 | workflow YAML 유효성 + README badge 마커 + privacy strip + Phase 1.5 delta 회귀 가드 (8~10 assert) |
| (수동 1회) `docs/baselines/2026-W18.json` | 첫 회 publish-metrics.sh 실행 결과 commit | 실증 데이터 1건 확보 + workflow 동작 검증 |

**완료 조건**: publish-metrics.sh 1회 실행 → baselines JSON commit + README badge 영역 갱신 + metrics-validation.yml이 PR 검증 통과. 의도적 위배 fixture로 검증 실패 동작 1회 확인. evaluator PASS. 회귀 0.

### Sprint 4 (deferred) — Phase 2 nova-metrics repo 부트스트랩

진입 트리거: KPI 분모 ≥ 10 도달 또는 사용자 명시 결정. **본 Plan scope-out**.

---

## Risk Map

(risk-explorer 결과 그대로 — H 4 / M 4)

| 리스크 | 가능성 | 영향 | 완화 |
|--------|--------|------|------|
| **[메트릭 환각] KPI 4종 N/A 또는 통계적 무의미** — n=1 jury_verdict 하나로 "100%"를 대시보드에 노출 시 사용자 오인 | H | H | n 임계값 미달 시 gray-out 강제 (Phase 0 spec). 배지에 "n=N" 병기 강제 |
| **[schema drift] v1↔v2 같은 날 혼재** — 2026-04-29에 v1 209건 + v2 746건 교차. snapshot-baseline.sh가 v2를 0건으로 잘못 카운트한 의심 | H | H | Phase 0 spec에 schema_version별 집계 분기 명시. `select(.schema_version==2)` 필터 추가 또는 v1→v2 매핑 레이어 |
| **[n=1 dogfood 함정] 단일 session_id·단일 cwd_hash** — 3,063줄 전체가 동일. 외부 방문자가 다수 사용자 데이터로 착각 | H | H | 대시보드 상단 "n=1 단일 개발자 dogfood" 명시. unique_user_count(cwd_hash unique 수) KPI 옆 병기. Phase 3 이전까지 "개인 측정" 라벨 |
| **[KPI 3 dead metric] rule_evolution_rate grep 패턴 영구 불일치** — `^## .* — proposed`가 `rules-changelog.md` 실제 형식(`### [YYYY-MM-DD]`)과 불일치. 데이터 쌓아도 0/0 | H | M | Phase 0 spec에서 KPI 3 정의 재작성 (실제 파일 형식 매칭) 또는 `evolve_decision` 이벤트 기반으로 전면 교체 |
| **[Privacy] cwd_hash SHA-256 앞 8자리 브루트포스 가능** — 후보 경로 목록 브루트포스로 절대경로 복원. 공개 시 환경 프로파일링 위험 | M | H | baselines JSON에 cwd_hash 미포함. 추가 솔팅. Phase 0 spec에 "집계 JSON에서 cwd_hash 제거" 명시 |
| **[Actions silent failure] 주간 cron 실패 시 stale 배지** — ci.yml 실패 알림 채널 부재. jq/python3 미설치 등으로 실패해도 사용자 무인지 | M | M | workflow 실패 시 GitHub Issue 자동 생성. 배지에 "updated: {date}" 타임스탬프 병기. baselines commit 실패 시 `exit 1` 명시 |
| **[데이터 품질] events.jsonl 손상·truncation 무감지** — 쓰기 중 kill 시 incomplete JSON. _metrics-helpers.py가 묵묵히 무시. mcp-server 하위 별도 jsonl 범위 불명 | M | M | 집계 전 `jq -e '.' events.jsonl` 유효성 검사. 파싱 실패 줄 수 stderr 카운트. mcp-server 집계 포함 여부 Phase 0 spec 명시 |
| **[별도 repo 운영 부담] schema 마이그레이션 분리 비용** — events.jsonl v3 진화 시 nova/nova-metrics/Astro 3곳 동시 수정. Phase 1→2 전환 시 배지 URL 변경 시 nova README 재수정 역방향 의존 | M | M | nova-metrics에 schema_version 필수 어댑터 레이어. Phase 1→2 배지 URL 고정 전략(shields.io endpoint 유지) Phase 0 spec 결정. baselines JSON schema 자체에도 schema_version 필드 포함하여 v3 도입 시 과거 파일 호환 |
| **[Actions 데이터 접근 공백] (Critic Critical #1)** — `.nova/`가 `.gitignore`라 Actions checkout 후 events.jsonl 부재. **Resolved**: 자동화 모델 재설계로 Actions가 직접 측정하지 않음. 로컬 publish-metrics.sh + Actions는 검증 보조만 | H | H | **Resolved by design** — 본 Plan ## Solution / 데이터 흐름 결정 섹션 참조. Actions는 baselines JSON 검증만 (nova-metrics.sh를 직접 실행하지 않음) |
| **[baselines commit 충돌] (Critic High #3)** — workflow 또는 사용자가 동시 push 시 non-fast-forward. publish-metrics.sh는 사용자 로컬 단일 책임이라 충돌 가능성 자체 낮음 | L | M | publish-metrics.sh에 `git pull --rebase` 사전 실행. workflow는 push 권한 없음(검증만) → 충돌 원천 차단 |
| **[shields.io 의존] (Critic High #3)** — shields.io rate limit 또는 다운타임 시 badge 오류 이미지. README badge가 외부 endpoint 의존 | M | L | Phase 1.5 또는 Phase 2 전환 시 정적 SVG commit 옵션 검토. 현재 1인 트래픽이라 rate limit 위험 낮음. Phase 0 spec에 fallback 정책 명시 |
| **[events 실수 commit] (Critic High #3)** — `.gitignore` 삭제 또는 `git add -f` 실수로 .nova/ 전체 push. cwd_hash 브루트포스 + session_id로 환경 프로파일링 | L | H | (1) `.git/hooks/pre-commit` 또는 `metrics-validation.yml`에 `.nova/` 경로 push 차단 가드 추가. (2) Phase 0 spec에 "절대 commit 금지 파일" 명시 + release.sh Step 2.5 위생 게이트에 `.nova/` 차단 규칙 추가 |

---

## Unknowns

(risk-explorer 결과 그대로 — Phase 0 spec 작성 전 해결 필수)

- **Observable Plot의 시계열 표현과 n 임계값 UI 처리 실측 미확인** — Astro SSG + Observable Plot 조합에서 n=0 시 빌드 실패 vs 빈 플롯 렌더링 동작 미확인. Phase 2 인프라 설계 시 실측 필요.
- **baselines/{week}.json → GitHub Pages Astro 빌드 연결 방식 미결정** — nova-metrics가 별도 repo면 raw GitHub URL 하드코딩 vs git submodule. 이 경계가 Phase 0 spec에 없으면 Phase 1 데이터 포맷이 Phase 2에서 재작업.
- **events.jsonl이 nova-metrics repo에 복사되는지 여부 미결정** — cross-repo checkout(PAT/GitHub App) 필요. 원본 events 공개 vs 집계만 넘기기. Privacy 정책 분기점.
- **KPI 1, 2 분자 이벤트(plan_created, sprint_completed) 발화 조건 미검증** — 현재 plan_created 3건, sprint_completed 0건. 분모 0이 "이벤트 미발화 버그" vs "정상 미사용"인지 구분 필요. 대시보드 오픈 전 수동 재현 필수.
- **session_id 재사용 문제** — 3,063줄 전체가 단일 session_id "578ef3df4454". 세션별 갱신 설계라면 훅 버그. 의도된 재사용이라면 "세션 수" 기반 KPI 전부 틀어짐. **즉시 조사 필요**.

---

## Verification Hooks

> Sprint Contract 씨앗 — 이후 `/nova:design` 단계에서 구체화한다.

| # | 검증 항목 | 검증 방법 | 우선순위 |
|---|----------|----------|---------|
| 1 | `docs/measurement-spec.md` 존재 + 8 핵심 결정 사항 모두 명시 | grep으로 8 키워드 모두 검출: `KPI 4종`, `n 임계`, `schema_version 분기`, `baselines JSON schema`, `Phase 2 인프라 설계`, `Phase 2 진입 트리거`, `Phase 3 future hook`, `badge gray-out 책임` | Critical |
| 2 | KPI 3 재정의 + emit 지점 검증 (Critic Critical #2 fix) | **AND 조건**: spec에 "evolve_decision 이벤트 기반 재정의" 명시 **AND** Sprint 1에서 emit 지점 1개 이상 추가 구현 (record-event.sh 또는 evolve 관련 hook) **AND** 수동 재현으로 evolve_decision 이벤트 1건 이상 events.jsonl에 기록 확인 | Critical |
| 3 | schema_version 분기 처리 검증 (로컬) | `jq 'select(.schema_version==2)' .nova/events.jsonl \| wc -l` 결과가 spec 명시 v2 카운트와 일치 (로컬 환경 한정) | Critical |
| 3b | schema_version 분기 처리 검증 (CI 환경) | `tests/fixtures/events-sample.jsonl`에 v1+v2 혼재 fixture 사용 → tests/test-scripts.sh가 분기 로직 검증 | Critical |
| 4 | nova-metrics.sh --json 출력이 valid JSON + n<임계 처리 | `bash scripts/nova-metrics.sh --json --fixture tests/fixtures/events-sample.jsonl \| jq -e '. \| length >= 4'` exit 0. n<임계 시 `pct: null` + `badge_url`이 gray | Critical |
| 5 | nova-metrics.sh 텍스트 출력 회귀 0 | `bash scripts/nova-metrics.sh` 출력에 4 KPI 라인 모두 존재 (기존 동작 유지) | Critical |
| 6 | publish-metrics.sh 동작 검증 | `bash scripts/publish-metrics.sh --dry-run` 실행 → docs/baselines/{week}.json 후보 생성 + privacy strip 검증 + git diff 출력 | Critical |
| 7 | metrics-validation.yml 유효성 | `actionlint .github/workflows/metrics-validation.yml` 통과 또는 GitHub UI syntax check | Critical |
| 8 | Workflow 검증 실패 시 Issue/PR 코멘트 자동 생성 | `metrics-validation.yml`에 실패 시 `actions/github-script`로 issue/comment 생성 step 존재 + 의도적 위배 fixture로 수동 검증 1회 | Critical |
| 9 | n<임계 시 gray-out 구현 (책임 명확화 — Critic Medium #6 fix) | nova-metrics.sh --json이 `badge_url`에 shields.io gray URL 직접 생성. fixture 테스트로 n=1 시 badge_url 형식 검증 | Critical |
| 10 | Privacy: baselines JSON에 금지 필드 부재 | `jq '.[] \| has("cwd_hash")' docs/baselines/*.json` 모두 false. `has("session_id")` 모두 false. metrics-validation.yml이 자동 검증 | Critical |
| 11 | `.nova/` 실수 commit 차단 가드 | release.sh Step 2.5 또는 `.git/hooks/pre-commit` 또는 metrics-validation.yml에 `.nova/` 경로 push 시 fail 로직 존재 | Critical |
| 12 | tests/test-scripts.sh 회귀 0 | `bash tests/test-scripts.sh` 538/538 (또는 신규 assert 추가 후 새 카운트) PASS | Critical |
| 13 | session_id 재사용 문제 조사 결과 spec 반영 (Sprint 1 시작 전 필수) | spec에 "session_id 갱신 정책: {버그 수정 vs 의도된 재사용}" + 결론에 따른 hook 수정 또는 KPI 공식 조정 반영 | Critical |
| 14 | Phase 2 진입 트리거 명시 | spec에 "Phase 2 진입 조건: 각 KPI 분모 ≥ 10 또는 사용자 명시 결정" 문장 존재 | Critical |
| 15 | Phase 1.5 트렌드 표시 활성 조건 검증 | publish-metrics.sh가 baselines 파일 ≥2 도달 시 자동으로 delta 계산 + badge 영역에 변화율 추가 | Nice-to-have |

---

## Notes

### nova-landing(별도 repo) 연계

`jay-swk/nova-landing`(Next.js, v3.12 멈춤)과 `jay-swk/nova-metrics`(가칭, Astro)는 **분리 유지**가 권장된다.

- **nova-landing**: 마케팅·홈페이지·What's New (현재 release.published 자동 dispatch)
- **nova-metrics**: 측정 결과·시계열·KPI 시각화 (Phase 2 진입 시점에 부트스트랩)

두 repo 모두 jay-swk org. 미래에 통합 도메인(`nova.dev/metrics` 등)으로 합치는 것은 추가 작업으로 별도 결정.

### 메모리 정합 체크

- ✅ `feedback_evidence_first_identity` — 측정→입증→정체성. 본 Plan은 측정 closed loop 그 자체.
- ✅ `nova_spike_skill_deferred` — n>1 시점 재검토. Phase 2 트리거 = 데이터 임계.
- ✅ `feedback_evaluator_hallucination` — 측정값 그대로 신뢰 X. n=1 메트릭 환각 방지 가드 다중 (gray-out, n 명시, "Self-only" 라벨).
- ✅ `feedback_no_manual_setup` — Phase 1은 GitHub Actions 자동화. 사용자 수동 설정 0.
- ✅ `nova_universal_plugin` — Nova 본체 변경 최소 (nova-metrics.sh --json 추가만). 외부 사용자 환경 영향 0.

### release.sh 통합

본 Plan 완료 후 release 시점은 minor (`v5.24.0`) — 신규 기능(--json + workflow + spec).

`scripts/release.sh` Step 2.5 위생 게이트가 NOVA-STATE 신선도/review 흔적/audit-self를 검증하므로 추가 통합 불필요.
