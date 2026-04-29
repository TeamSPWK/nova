# Measurement Closed-Loop — 주간 리츄얼 가이드

> Nova Engineering — measurement-closed-loop Phase 0+1 사용자 가이드
> 대상: Nova repo 컨트리뷰터 / dogfood self-metrics 운영자
> Spec: `docs/measurement-spec.md` · Design: `docs/designs/measurement-closed-loop.md`

---

## TL;DR

```bash
bash scripts/publish-metrics.sh --dry-run   # 미리보기
bash scripts/publish-metrics.sh             # 실행 (baselines + README 갱신)
git add docs/baselines/<period>.json README.md README.ko.md
git commit -m "metrics(<period>): 주간 baselines 갱신"
git push
```

주 1회. 실행 후 안내되는 commit 명령을 따라가면 끝. **`.nova/` 디렉토리는 절대 commit하지 마세요** (privacy 4중 가드가 차단).

---

## 1. 무엇을 측정하나

| KPI | 분자 | 분모 | n_threshold |
|-----|------|------|-------------|
| `process_consistency` | sprint 전 plan_created가 있는 sprint | sprint_completed (planned_files≥3) | 10 |
| `gap_detection_rate` | FAIL 후 PASS resolution 도달 | evaluator_verdict FAIL | 10 |
| `rule_evolution_rate` | accepted decision | evolve_decision 이벤트 | 10 |
| `multi_perspective_impact` | direction 변경된 jury | jury_verdict | 5 |

분모 < n_threshold = **insufficient gray-out**. 100% 신뢰가 무의미한 표본은 정직하게 회색으로 노출합니다.

---

## 2. 언제 실행하나

- **주 1회** (월요일 권장 — ISO 주차 시작에 맞음)
- 4주+ 미실행 시 `session-start.sh`가 자동 알림: `⚠️ baselines XX일 미갱신 — bash scripts/publish-metrics.sh 권장`
- 신규 사용자(파일 0건)는 알림 미출력 — 부담 X

cron / GitHub Actions로 자동 실행하지 **않습니다** (Critic Critical #1 결정). 사용자 명시 결정만 측정 사이클을 시작합니다.

---

## 3. 첫 실행 절차

### 3.1 미리보기 (--dry-run)

```bash
bash scripts/publish-metrics.sh --dry-run
```

출력에 다음이 보이면 정상:
- `Would write: docs/baselines/YYYY-WNN.json`
- 4 KPI 객체 (kpi/label/pct/n/n_threshold/status/delta_pct/badge_url)

### 3.2 실 실행

```bash
bash scripts/publish-metrics.sh
```

순서대로 처리됩니다:
1. KPI 산출 (`nova-metrics.sh --json`)
2. Privacy 재검증 (cwd_hash/session_id strip 확인)
3. period 산출 (UTC ISO 주차)
4. 이전 baselines 비교 → `delta_pct` 계산 (있을 때만)
5. `docs/baselines/YYYY-WNN.json` 작성
6. `README.md` + `README.ko.md` AUTO-GEN 마커 영역 갱신
7. `git pull --rebase`
8. commit 안내 출력

### 3.3 commit + push

스크립트 끝에서 안내되는 명령을 그대로 실행:

```bash
git add docs/baselines/<period>.json README.md README.ko.md
git commit -m "metrics(<period>): 주간 baselines 갱신"
git push
```

push 직후 GitHub Actions(`metrics-validation.yml`)가 자동 검증합니다.

---

## 4. 출력 해석

### 4.1 baselines JSON 한 KPI 객체

```jsonc
{
  "kpi": "process_consistency",
  "label": "Process Consistency",
  "pct": 78,                  // 0~100 정수 또는 null (insufficient)
  "n": 41,                    // 분모 이벤트 수
  "n_threshold": 10,
  "status": "sufficient",     // sufficient | insufficient
  "delta_pct": 5,             // 전주 대비 %p 변화 (첫 주는 null)
  "badge_url": "https://img.shields.io/badge/process_consistency-78%25-yellow"
}
```

### 4.2 Badge 색상

| 상태 | 색상 |
|------|------|
| `n < n_threshold` | **lightgrey** (insufficient — 부끄러움 X, 정직 신호) |
| pct ≥ 80 | green |
| 60 ≤ pct < 80 | yellow |
| pct < 60 | red |

### 4.3 delta_pct

- 첫 주: `null`
- 이전 baselines가 있어도 한쪽이 null이면: `null`
- 단위는 **%p** (percentage point)이지 % 아님. "78 → 83"이면 `delta_pct = 5`

---

## 5. GitHub Actions 검증 FAIL 시 해결

`.github/workflows/metrics-validation.yml`이 PR/push에 자동 실행. FAIL 시 PR 코멘트 자동 생성.

| FAIL 단계 | 원인 | 해결 |
|----------|------|------|
| **Schema validation** | baselines JSON 필드 누락/형식 오류 | `docs/measurement-spec.md` §4 schema 확인. publish-metrics.sh 재실행 권장 |
| **Forbidden fields check** | `cwd_hash` / `session_id` / `events` / `extra` 노출 | publish-metrics.sh strip 가드 우회 의심. spec §4 금지 필드 확인 |
| **README badge marker integrity** | `<!-- nova-metrics:badges:start/end -->` 마커 부재 | README.md / README.ko.md에 마커 복원. publish-metrics.sh가 마커 사이만 교체 |
| **`.nova/` leak check** | `.nova/` 파일이 PR diff에 포함 | `git rm --cached .nova/<파일>` 후 force push. 절대 commit 금지 |

---

## 6. Privacy 4중 가드

```
1. .gitignore         → .nova/ 디렉토리 (events.jsonl, session.id, cache 모두 차단)
2. nova-metrics.sh    → KPI 산출 시 cwd_hash/session_id strip
3. publish-metrics.sh → 출력 직전 jq로 has("cwd_hash"|"session_id") 재검증
4. metrics-validation.yml → PR diff에서 .nova/ 또는 금지 필드 차단
5. release.sh Step 2.5 → .nova/ staged 시 fail-closed exit 2
```

위반 가능성을 의심한다면 즉시 중단 후 알리세요. **단 한 줄도 commit되면 안 됩니다.**

---

## 7. 테스트 / 디버깅

### 7.1 fixture로 dry-run

```bash
# n=12, 모든 KPI sufficient + 100% green
bash scripts/publish-metrics.sh --dry-run \
  --fixture tests/fixtures/events-sufficient.jsonl --since all

# n=1, 모든 KPI insufficient + gray
bash scripts/publish-metrics.sh --dry-run \
  --fixture tests/fixtures/events-low-n.jsonl --since all
```

### 7.2 Privacy 가드 검증

```bash
# 의도적 cwd_hash 주입 → exit 3 + FATAL 메시지 확인
NOVA_TEST_INJECT_CWD_HASH=1 bash scripts/publish-metrics.sh --dry-run \
  --fixture tests/fixtures/events-sufficient.jsonl --since all
echo "exit=$?"  # → 3
```

### 7.3 회귀 테스트

```bash
bash tests/test-scripts.sh   # R1~R22 measurement-closed-loop 22 assert 포함
```

---

## 8. Phase 2 진입 트리거

본 가이드는 Phase 0+1 (로컬 publish + Actions 검증) 운영을 다룹니다. **Phase 2(Astro+Plot 시계열 시각화)는 별도 시점 결정**:

| 조건 | 의미 |
|------|------|
| Sprint 3 완료 (v5.24.0) | ✅ |
| 4주 누적 baselines | 진행 중 |
| **KPI 4 중 2개 이상 분모 ≥ 10** | 트리거 |

도달 시:
1. `docs/measurement-spec.md` §7 (Phase 2 인프라 설계) 검토
2. 별도 Design 문서 `measurement-visualization.md` 작성
3. `jay-swk/nova-metrics` repo 부트스트랩

조급해할 필요 없습니다 — 데이터가 부족할 때 시각화는 거짓 신호를 만듭니다.

---

## 9. 부정직성 거부 — gray-out은 자랑

- n=2에서 "78% Process Consistency" 표시는 **금지** — 메모리 `feedback_evidence_first_identity` 위반.
- gray badge는 약점이 아닙니다. **"우리는 거짓말하지 않습니다"** 신호입니다.
- 외부 방문자가 README에서 4 gray badge를 봐도 부끄러움 X. n 누적 후 자동으로 색상이 살아납니다.
- 측정 정체성("self-only metrics")을 어휘로 강요하지 마세요. 데이터가 충분해진 뒤 후험적으로 정체성을 승격합니다.

---

## 10. Cheatsheet

```bash
# 주간 실행
bash scripts/publish-metrics.sh

# 미리보기
bash scripts/publish-metrics.sh --dry-run

# 임의 fixture로 dry-run
bash scripts/publish-metrics.sh --dry-run --fixture <path> --since all

# Privacy 가드 검증
NOVA_TEST_INJECT_CWD_HASH=1 bash scripts/publish-metrics.sh --dry-run \
  --fixture tests/fixtures/events-sufficient.jsonl --since all   # exit 3 기대

# 회귀 테스트
bash tests/test-scripts.sh

# Phase 2 진입 자가 점검
jq '[.kpis[] | select(.status == "sufficient")] | length' docs/baselines/*.json | sort -u
# 출력에 2 이상이 있으면 Phase 2 진입 검토
```

---

## 메모리 정합

| 메모리 | 적용 |
|--------|------|
| `feedback_no_manual_setup` | publish-metrics.sh 1회 명시 실행 외 모든 단계 자동 |
| `feedback_evidence_first_identity` | n<임계 gray-out 강제. 정체성 어휘 후험 승격 |
| `feedback_release_sh_staging_trap` | publish-metrics와 release.sh 분리. baselines는 별도 commit |
| `feedback_fixture_no_git_init` | Phase 2는 raw URL fetch (submodule 거부) |
