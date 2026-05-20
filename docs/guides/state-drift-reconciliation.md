# State Drift Reconciliation 가이드

> Nova **상태 기둥** — NOVA-STATE.md prose ↔ git log ↔ registry 3-way 대조 엔진.

---

## TL;DR

NOVA-STATE.md에 "진행 중"이라고 적혀 있지만 이미 커밋된 작업이 `/nova:next`에서 다시 추천되는 문제를 해결한다. `reconcile-state.sh`가 세 소스를 대조해 실제로 완료됐거나 추적 불가한 항목을 분류한다.

```bash
# 현황 확인 (읽기 전용 — 파일 변경 없음)
bash scripts/reconcile-state.sh

# JSON 출력 (next.md, checkpoint 등 자동 호출용)
bash scripts/reconcile-state.sh --jsonl | jq .
```

---

## 왜 필요한가

NOVA-STATE.md 손편집 prose와 v3 work-item registry 사이에는 **계약이 없었다**. 어느 쪽이 status의 진실인지 충돌 규칙이 없어서, 완료된 작업이 prose에 "진행 중"으로 남아 `/nova:next`가 stale 추천을 냈다.

### 상태 진실원 계약

| 소스 | 역할 | 충돌 시 |
|------|------|---------|
| registry (`.nova/work-items`) | **status 단일 진실** | 이긴다 |
| git log | **완료 단일 진실** | 이긴다 |
| NOVA-STATE.md prose | 비공식 스냅샷 (Goal·관찰·서사) | **진다** |

---

## 절차

### 1. 현황 점검

```bash
bash scripts/reconcile-state.sh
```

출력 예시:
```
Nova State Reconcile — hybrid STATE · registry 13 WI · git 90d
⚠️ hybrid: STATE 본문이 v2 형식 — /nova:migrate-state로 완전 v3 권고

⚠️ 완료의심 — 확인 필요 (2)
  [explicit] WI-0013  registry=proposed ↔ 커밋 a1b2c3d Nova-WI:WI-0013
             → bash scripts/registry-write.sh transition WI-0013 done --evidence-commit=a1b2c3d
  [fuzzy]    prose L15 "gc-cost-jump --cron-window 진행 중" ↔ af5912f
             → 공유 토큰: gc-cost-jump, --cron-window

❓ 추적불가 — Nova가 상태를 알 수 없음 (1)
  prose L23: auth-refactor 작업 중

🟢 정상: 11
```

### 2. 문제 해결

**⚠️ [explicit] — registry=active/proposed인데 Nova-WI: trailer 있는 커밋 존재**

```bash
# 제시된 명령 그대로 실행
bash scripts/registry-write.sh transition WI-0013 done --evidence-commit=a1b2c3d
```

**⚠️ [explicit] — done인데 evidence_sha unreachable (squash/rebase 고아)**

```bash
# 최근 HEAD SHA로 재바인딩
bash scripts/registry-write.sh transition WI-0013 done --evidence-commit=$(git rev-parse HEAD)
```

**⚠️ [fuzzy] — prose와 커밋이 유사하나 확실하지 않음**

해당 prose 항목을 직접 확인한다:
- 실제로 완료됐으면 → registry transition 후 prose에서 항목 제거
- 아직 진행 중이면 → 무시 (다음 reconcile에서도 표시되지만 자동 전이 없음)
- WI 없는 작업이면 → work-item 등록: `bash scripts/registry-write.sh create ...`

**❓ 추적불가 — prose에만 있고 WI 없음, 일치 커밋 없음**

선택지:
1. WI 등록: `bash scripts/registry-write.sh create --title "..." --priority medium`
2. prose에서 삭제 (완료 또는 무효 항목)
3. 서사/관찰 메모라면 status 키워드 제거 (예: "진행 중" 삭제)

---

## FAIL 시 해결법

### reconcile 실행 오류 (exit 2)

| 오류 메시지 | 원인 | 해결 |
|-------------|------|------|
| `NOVA-STATE.md 없음` | STATE 파일 부재 | `/nova:setup` 실행 |
| `git 레포가 아님` | git 레포 밖 | 레포 루트에서 실행 |
| `jq 미설치` | jq 없음 | `brew install jq` |
| `python3 미설치` | python3 없음 | python3 설치 |

### STATE 클래스별 모드

| state_class | 의미 | 모드 |
|-------------|------|------|
| `v3` | schema_version=3 + registry 있음 | 3-way (prose↔git↔registry) |
| `hybrid` | registry 있음 + schema 2 | 3-way + migrate 권고 배너 |
| `v2-only` | registry 없음 | 2-way (prose↔git) + migrate 권고 |

### fuzzy 매칭 정확도 (캘리브레이션)

`⚠️ 완료의심`의 fuzzy 항목은 prose/WI와 git 커밋이 **distinctive token**(kebab-id·`--flag`·경로·버전·`WI-id`)을 공유할 때만 후보가 된다. 자연어 단어만 겹치는 것은 매칭하지 않아 한↔영·`feat/fix` prefix 노이즈에 둔감하다.

| 측정일 | 표본 | fuzzy 오탐 | 기준 |
|--------|------|-----------|------|
| 2026-05-20 | Nova 레포 `--since=30d` (147 커밋) | **0건** | ≤ 2건 (Sprint Contract S1-C7) |

오탐이 기준을 초과하면 매칭 임계를 distinctive token ≥ 2로 상향한다 (Design §Solution STEP 3).

---

## Cheatsheet

```bash
# 기본 실행 (사람용 리포트)
bash scripts/reconcile-state.sh

# 기계 판독 JSON
bash scripts/reconcile-state.sh --jsonl | jq .counts

# 특정 기간만 (30일)
bash scripts/reconcile-state.sh --since=30d

# state_class 확인
bash scripts/reconcile-state.sh --jsonl | jq -r .state_class

# 도움말
bash scripts/reconcile-state.sh -h

# clean 확인 (exit 0이면 drift 없음)
bash scripts/reconcile-state.sh --jsonl >/dev/null && echo "CLEAN"

# explicit 건수만 출력
bash scripts/reconcile-state.sh --jsonl | jq .counts.suspect_explicit
```

---

## 관련 문서

- [Design: state-drift-reconciliation.md](../designs/state-drift-reconciliation.md) — 알고리즘 상세
- [Plan: state-drift-reconciliation.md](../plans/state-drift-reconciliation.md) — 배경 + 3-스프린트 전략
- `scripts/registry-write.sh` — WI 전이 단일 쓰기 경로
- `scripts/check-state-drift.sh` — mtime 기반 drift 검증 (별도 역할)
- `scripts/registry-drift-check.sh` — registry 내부 18룰 검증 (별도 역할)
