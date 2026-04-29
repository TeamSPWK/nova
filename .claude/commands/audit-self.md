---
description: Nova 플러그인 자기 코드(plugin.json/hooks/agents/skills/commands)에 대한 정적 보안 진단을 수행한다. 30+ 룰셋 5 카테고리, security-engineer → evaluator 직렬 검증, 메인 사실 검증 회로. ECC AgentShield 영감.
---

# /nova:audit-self

Nova 플러그인 자기 보안 진단 — 정적 분석 기반.

## 사용법

```
/nova:audit-self                      # 전체 5 카테고리 스캔 (~30K 토큰)
/nova:audit-self --category hooks     # 단일 카테고리만 (~6K 토큰)
/nova:audit-self --jury               # Red/Blue/Auditor 3에이전트 적대적 검증 (~50K 토큰, v5.23.0+)
```

## 비용

평균 1회 실행 ~30K 토큰 — 룰셋 30+ 룰 + 검사 대상 ~6900줄. `--category {plugin|hooks|agents|skills|commands}` 옵션으로 ~6K 토큰까지 축소 가능. 자주 호출 시 카테고리 분할 권장.

## scan_targets

Phase 1 스캔 대상 — Glob 패턴으로 로드한 후 룰별 condition이 매칭되는 파일만 조건부 Read.

- `.claude-plugin/plugin.json` — 플러그인 매니페스트
- `hooks/*.sh` — 훅 셸 스크립트
- `agents/*.md` — 에이전트 정의
- `skills/*/SKILL.md` — 스킬 정의
- `commands/*.md` — 슬래시커맨드 정의

## exclusion_list

검사자/검사 대상 분리 원칙 — **메타-루프 가드** (R1 완화). 검사자(security-engineer)가 자기 정의를 검사하면 자가 합리화 편향이 발생하므로 명시 제외한다.

- `agents/security-engineer.md`  ← 검사자 자기 정의
- `commands/audit-self.md`       ← audit-self 커맨드 자기 정의 (메타 루프 회피)
- `docs/security-rules.md`        ← 룰셋 자체 (R10 공급망 무결성은 별도 처리, v5.23.0)

> 메타 노트: 검사자/검사 대상 분리 원칙이 깨지면 결과 무효. v5.23.0의 `--jury` Red/Blue/Auditor 위임으로 자기 검사를 외부화 예정.

---

## Phase 1: 카테고리 스캔 (룰셋 로드 + 파일 Glob)

1. `docs/security-rules.md` 로드 → 룰 스키마 파싱 (7 필드 — id/category/severity/condition/normal_example/risk_example/mitigation)
2. `--category {X}` 지정 시 해당 카테고리 룰만 활성. 미지정 시 전체 활성
3. scan_targets Glob 결과 수집 → exclusion_list 항목 제거
4. 각 룰의 `condition` 1-liner를 활성 파일에 적용 (Read 도구로 조건부 로드)

## Phase 2: security-engineer 호출

`Agent` 도구로 `nova:security-engineer` 서브에이전트를 spawn (Read/Glob/Grep만 — Edit/Write/Bash disallowed).

전달 컨텍스트:

```
mode: self-audit
scan_targets: <Phase 1 결과>
exclusion_list: <exclusion_list 항목>
active_rules: <카테고리 필터 적용된 룰 목록>
rules_doc: docs/security-rules.md
```

서브에이전트는 `agents/security-engineer.md` 의 "Nova 자기 코드 감사 모드" 섹션 규약을 따라 마크다운 리포트를 반환한다 (Critical/Warning/Info 분류).

## Phase 2.5: --jury 분기 (v5.23.0+, ECC §P2-3 흡수)

`--jury` 플래그가 지정된 경우, Phase 2의 단일 security-engineer 결과를 **3 페르소나 적대적 검증**으로 보강한다. `skills/jury/SKILL.md` 모드 3 (보안 진단) 호출.

전달 컨텍스트:

```
mode: audit
target: nova-self-codebase
rules_doc: docs/security-rules.md
scan_targets: <Phase 1 결과>
exclusion_list: <exclusion_list 항목>
security_engineer_report: <Phase 2 결과>
```

jury 스킬은 다음 3 서브에이전트를 독립 spawn한다 — Generator-Evaluator 분리 (§2):

| 페르소나 | 역할 | 출력 |
|----------|------|------|
| **Red (공격자)** | 룰셋 약점·우회 케이스 발굴 — false negative 5개 이내 | 우회 시나리오 + 룰 보강 권고 |
| **Blue (방어자)** | Phase 2 보고된 위반 검증 — false positive 강등 권고 | KEEP/DEMOTE/DROP 판정 |
| **Auditor (중재자)** | Red+Blue+원본 보고 통합 → 최종 분류 | Critical/Warning/Info 최종 표 |

**합의 프로토콜** (`skills/jury/SKILL.md` 모드 3):

| Red | Blue | Auditor 최종 |
|-----|------|-------------|
| PASS | PASS | **PASS** — 진단 종결 |
| PASS | CONDITIONAL | **PASS with demotion** — Blue 권고 반영 |
| FAIL | PASS | **CONDITIONAL** — Red 발견 룰 보강 백로그 추가 |
| FAIL | CONDITIONAL | **FAIL** — 즉시 검토 |

**비용 가산**: 단일 모드 ~30K → `--jury` 모드 ~50K 토큰 (3 페르소나 + Auditor 통합).

**Phase 4 환각 회로 강화**: Auditor 결과의 모든 `{file:line}` 항목에 메인 컨텍스트가 grep 사실 검증 — Red가 제안한 우회 케이스 (실제 파일에 없을 수 있음)는 "Red 추론" 마커로 분리 표시.

**관찰성**: jury 스킬이 `jury_verdict` 이벤트 기록 (mode=audit 필드). audit-self가 추가로 `audit_self_verdict`를 기록하여 dual log.

## Phase 3: evaluator 직렬 검증

`evaluator` 스킬을 Plan 검증 모드 변형으로 호출 (Layer 1 존재 + Layer 2 정합성만, Layer 3 동작은 정적 분석 한계로 적용 불가 — Known Gap 마킹).

전달 컨텍스트:

```
target: audit-report
report: <Phase 2 결과>
rules_doc: docs/security-rules.md
```

evaluator는 다음을 검증:
1. 보고된 위반 항목의 Rule ID가 docs/security-rules.md에 실재하는가
2. severity 분류가 룰 정의와 일치하는가
3. file:line 참조가 형식적으로 유효한가 (실제 매칭은 Phase 4)

## Phase 4: 메인 사실 검증 (환각 방지 회로)

> 메모리 원칙 `feedback_evaluator_hallucination` — Evaluator도 환각함. 메인 컨텍스트가 grep으로 사실 검증 1회 후 사용자 보고.

각 보고된 `{file}:{line}` 항목에 대해:

```bash
grep -n "{Rule.condition_pattern}" {file}
```

- **매칭 성공**: 정상 — 사용자 보고로 진행
- **매칭 실패 (≥1건)**: 환각 가능성 — 출력에 `⚠️ Evaluator 환각 경보: {N}건 매칭 실패` 명시. 해당 항목은 "검증 불가" 마킹. 최종 판정은 사용자 수동 결정에 위임.

## Phase 5: 결과 정리 + 출력

### 보안 진단 결과 — {ISO 8601 timestamp}

```
[검사 대상] 5 카테고리, {N}개 파일, ~{M}줄
[룰셋]      docs/security-rules.md v{version}, {활성 룰}/{전체 룰}
[제외]      agents/security-engineer.md, commands/audit-self.md, docs/security-rules.md (메타-루프 가드)
[모드]      static (정적 분석만 — Dynamic은 Known Gap)
```

#### Category: plugin

| Rule ID | Severity | 파일:라인 | 설명 | 수정 |
|---------|----------|-----------|------|------|
| R-PLUGIN-XXX | Critical | path:42 | ... | ... |

(나머지 4 카테고리 동일)

#### Risk Map (요약)

| 등급 | 카운트 |
|------|--------|
| Critical | N |
| Warning | M |
| Info | K |

#### 결과 해석 가이드

**Critical 발견 시**:
- 즉시 commit 차단 권고 (자동 차단 X — v5.22.0은 정보성 권고만)
- 사용자 검토 후 (a) fix 또는 (b) `--skip-audit` 명시 사용 + NOVA-STATE.md `Known Risks` 행 추가
- v5.23.0+ 에서 release.sh 자동 차단 게이트 검토

**Warning 발견 시**:
- NOVA-STATE.md `Known Risks` 행 추가 권고
- 다음 sprint에서 정리

**Info 발견 시**:
- 정보성 — 별도 행동 불필요. 코드 품질 개선 후보

**False Positive 의심 시**:
- 룰별 `normal_example` 와 비교
- FP rate 측정 — 분모(CRITICAL/WARNING 보고 수) / 분자(사용자 검토 후 "실제 문제 아님") = FP rate
- NOVA-STATE.md `Last Activity` 에 `audit-self FP rate {percent}% (분자 N / 분모 M)` 1줄 기록 권장

## Phase 6: 관찰성 훅

> 아래 스니펫은 LLM 지시문이다 — Phase 5 완료 후 변수 (`VERDICT`, `CRITICAL`, `WARNING`, `INFO`, `CATEGORY`) 를 Phase 5 결과에서 채워 호출한다. 변수 미초기화 상태로 직접 실행 금지.

```bash
# Phase 5 결과를 다음 변수에 할당한 뒤 호출:
#   VERDICT=PASS|FAIL|SKIPPED
#   CRITICAL=<int>  WARNING=<int>  INFO=<int>
#   CATEGORY=all|plugin|hooks|agents|skills|commands

bash hooks/record-event.sh audit_self_verdict "$(jq -cn \
  --arg v "$VERDICT" \
  --argjson c "$CRITICAL" \
  --argjson w "$WARNING" \
  --argjson i "$INFO" \
  --arg cat "${CATEGORY:-all}" \
  '{verdict:$v, critical_count:$c, warning_count:$w, info_count:$i, category:$cat}')" 2>/dev/null || true
```

이벤트 스키마 — `audit_self_verdict`:

| 필드 | 타입 | 형식 |
|------|------|------|
| `verdict` | enum | `PASS` (Critical 0) / `FAIL` (Critical ≥1) / `SKIPPED` (--skip-audit) |
| `critical_count` | integer | Critical 위반 룰 매칭 수 |
| `warning_count` | integer | Warning 위반 |
| `info_count` | integer | Info 위반 |
| `category` | string | `all` 또는 단일 카테고리명 |

Safe-default — 기록 실패 시 파이프라인 영향 없음.

---

## Known Gap (v5.23.0)

| 영역 | 사유 | 차후 |
|------|------|------|
| 동적 분석 (런타임 권한, 세션 오염, MCP 네트워크) | 정적 분석 한계 | e2e CI로 별도 검증 |
| 공급망 무결성 (룰 파일 변조 탐지) | 범위 외 | v5.24.0+ 검토 |
| Cross-harness 보안 (cursor/codex/gemini) | Tier 4 deferred | Claude Code 안정화 후 |
| 사용자 `.claude/rules/` 통합 | Nova 룰셋 우선 | v5.24.0+ Known Gap |
| Auditor 신뢰도 측정 | jury 모드 3 첫 운영 | v5.24.0+ baseline 측정 후 결정 |

---

## 에러 처리

| 에러 | 처리 |
|------|------|
| `docs/security-rules.md` 부재 | 즉시 종료, 메시지 "룰셋 파일 없음 — Sprint 1 미완 또는 파일 삭제 의심" |
| `--category` 잘못된 값 | 종료, 사용 가능 카테고리 5종 출력 |
| security-engineer spawn 실패 | 1회 재시도 후 사용자 보고 |
| evaluator 직렬 호출 실패 | Phase 3 skip + 출력에 ⚠️ 마커 "Phase 3 미실행 — security-engineer 단독 결과" |
| Phase 4 grep 매칭 실패 ≥1 | "⚠️ Evaluator 환각 경보" 출력 + 해당 항목 "검증 불가" 마킹 |
| `--jury` 호출 시 jury 스킬 모드 3 미정의 | skills/jury/SKILL.md 무결성 의심 — 단일 모드 fallback + 사용자 보고 |
| 토큰 한계 초과 | `--category` 옵션 권고 메시지 출력 후 진행 |

---

## NOVA-STATE.md 갱신

audit-self 종료 시:

- `Last Activity` 1줄 추가: `/nova:audit-self → {verdict} — Critical {C} Warning {W} Info {I} | {ISO 8601}`
- Critical 발견 시 `Known Risks` 행 자동 추가 (Critical 1건당 1행, 사용자 검토 의무)
- 50줄 초과 시 가장 오래된 항목부터 트림 (skills/context-chain/SKILL.md 룰)

---

## 관련 커맨드

- `/nova:review` — 일반 코드 리뷰 (사용자 코드 대상). 보안 스코프는 `/nova:audit-self` 우선
- `/nova:check` — 설계-구현 정합성. audit-self는 보안 정합성 전담
- `/nova:next` — Nova 운영 워크플로우. 릴리스 직전 audit-self 권장

# Input

$ARGUMENTS
