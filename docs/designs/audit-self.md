# [Design] /nova:audit-self — Nova 자기 보안 진단

> Nova Engineering — CPS Framework
> 작성일: 2026-04-29
> 작성자: Nova Design
> Plan: docs/plans/audit-self.md (Critic R2 PASS)

---

## Context (설계 배경)

### Plan 요약

방안 B 채택 — `commands/audit-self.md` 진입점 + 외부 `docs/security-rules.md` 룰셋 + `security-engineer → evaluator` 직렬 검증 + 메인 컨텍스트 사실 검증 회로. v5.22.0 minor 1회 릴리스. Sprint 0(Prerequisite, 0.5d) → Sprint 1(5파일 핵심) → Sprint 2(4파일 회귀·동기화).

### 설계 원칙

1. **선언적 룰셋** — 룰을 `docs/security-rules.md`로 외부화. 룰 변경이 git diff로 1:1 추적 가능.
2. **메타-루프 가드 분리** — 검사자(security-engineer) 자기 정의는 `exclusion_list`에서 명시 제외. 텍스트 매칭이 아닌 **마크다운 H2 헤더 + 라인 항목** 구조적 매칭.
3. **메인 사실 검증 회로** — security-engineer 결과 → evaluator 직렬 검증 → 메인이 보고된 `{파일}:{라인}` 각 항목에 `grep -n {Rule_pattern} {file}` 1회 실측. 매칭 실패 시 환각 경보.
4. **부분 실행 지원** — `--category {plugin|hooks|agents|skills|commands}` 로 토큰 압박 완화.
5. **자동 차단 도입 X** — v5.22.0은 정보성 권고만. release.sh 자동 호출은 6개월 운영 후 patch에서 검토.
6. **Known Gap 명시 선언** — 정적 분석 한계·공급망 무결성·v5.23.0 분리 항목을 문서에 의무 표기.

---

## Problem (설계 과제)

### 기술적 과제 목록

| # | 과제 | 복잡도 | 의존성 |
|---|------|--------|--------|
| T1 | 30~50 보안 룰셋의 스키마 정의 + 5 카테고리별 분류 + Known Gap 매핑 | High | ECC 102룰 분류 (Sprint 0 Prerequisite) |
| T2 | exclusion_list 구조적 매칭 (마크다운 H2 + awk 패턴 정합) | Medium | commands/audit-self.md 헤더 정규화 |
| T3 | security-engineer → evaluator 직렬 호출 — security-engineer가 Edit/Write/Bash 불가하므로 결과 핸드오프 포맷 정의 필수 | Medium | agents/security-engineer.md, skills/evaluator/SKILL.md |
| T4 | 메인 사실 검증의 grep 패턴 자동 추출 — 룰의 `condition` 필드를 grep 가능 정규식으로 변환 | High | docs/security-rules.md 룰 스키마 |
| T5 | session-start.sh lean ≤1200(soft) + standard/strict ≤2500(hard) 양쪽 만족하며 1줄 카탈로그 추가 | Low | hooks/session-start.sh 현재 텍스트 길이 측정 |
| T6 | tests/test-audit-self.sh 회귀 가드 — 룰 스키마 7 필드 검증 + 5 카테고리 누락 감지 + 룰 ID 중복 감지 | Medium | docs/security-rules.md |
| T7 | audit_self_verdict 이벤트 스키마 (record-event.sh schema v2 호환) | Low | hooks/record-event.sh extra payload 규약 |
| T8 | 부분 실행 `--category` 인수 파싱 — Phase 1 스캔이 카테고리별 Glob 분기 | Medium | commands/audit-self.md Phase 1 |

### 기존 시스템과의 접점

- **agents/security-engineer.md**: tools `Read, Glob, Grep` (Edit/Write/Bash disallowed). 결과는 마크다운 리포트로만 반환. audit-self는 이를 spawn하고 결과를 메인 컨텍스트에서 파싱.
- **skills/evaluator/SKILL.md**: Layer 1~3 적대적 검증. audit-self는 Layer 1(존재) + Layer 2(정합성)만 사용. Layer 3(동작)은 정적 분석 한계로 적용 불가 — Known Gap 명시.
- **skills/jury/SKILL.md**: v5.22.0에서는 호출 안 함. `--jury` 플래그는 placeholder만 (출력에 "v5.23.0 예정" 안내).
- **hooks/session-start.sh**: NOVA_PROFILE별 카탈로그 텍스트 분기. lean에 `/nova:audit-self` 1줄, standard/strict는 2~3줄(설명 포함).
- **hooks/record-event.sh**: schema v2 호환. extra payload 권장 필드(tool/duration_ms/pattern_id/decision)에 audit-self 전용 필드 추가 — `verdict`, `critical_count`, `warning_count`, `info_count`.
- **tests/test-scripts.sh**: EXPECTED_COMMANDS 배열에 `"audit-self"` 추가 — 자동 검증.

---

## Solution (설계 상세)

### 아키텍처

```
사용자: /nova:audit-self [--category X] [--jury (placeholder)]
   │
   ├─ Phase 0: 인수 파싱 + scan_targets/exclusion_list 로드
   │   ├─ scan_targets: 5 카테고리 파일 Glob 결과
   │   └─ exclusion_list: agents/security-engineer.md (메타-루프 가드)
   │
   ├─ Phase 1: 룰셋 로드 + 카테고리 스캔
   │   ├─ docs/security-rules.md → 룰 스키마 파싱 (7 필드)
   │   └─ --category 지정 시 해당 카테고리 룰만 활성
   │
   ├─ Phase 2: security-engineer 서브에이전트 spawn (Read/Glob/Grep)
   │   ├─ 입력: scan_targets, exclusion_list, 활성 룰
   │   └─ 출력: 마크다운 리포트 (Critical/Warning/Info 분류)
   │
   ├─ Phase 3: evaluator 직렬 호출 (Plan 검증 모드 변형)
   │   ├─ 입력: security-engineer 리포트
   │   └─ 출력: PASS/FAIL + 잔존 이슈 검증
   │
   ├─ Phase 4: 메인 사실 검증
   │   └─ 보고된 {파일}:{라인} 각각 grep -n {Rule_pattern} {file}
   │       └─ 매칭 실패 ≥1 시 환각 경보 + 사용자 보고
   │
   ├─ Phase 5: 결과 정리 + 권장 행동
   │   ├─ 카테고리별 섹션 + Risk Map 테이블 + 결과 해석 가이드
   │   └─ Critical 발견 시: "수동 검토 후 fix 또는 PASS 결정" 권고
   │
   └─ Phase 6: 관찰성 훅
       └─ bash hooks/record-event.sh audit_self_verdict {...}
```

### 데이터 모델 / API 설계 / 핵심 로직

#### 1. `commands/audit-self.md` 구조

```markdown
---
description: Nova 플러그인 자기 코드(plugin.json/hooks/agents/skills/commands)에 대한 정적 보안 진단을 수행한다. ECC AgentShield 영감, 5 카테고리 30~50 룰셋, security-engineer → evaluator 직렬 검증, 메인 사실 검증 회로.
---

# /nova:audit-self

Nova 자기 보안 진단 — 정적 분석 기반.

## 사용법

/nova:audit-self                      # 전체 5 카테고리 스캔
/nova:audit-self --category hooks     # 단일 카테고리만
/nova:audit-self --jury               # (v5.23.0 예정) Red/Blue/Auditor 다관점

## 비용

평균 1회 실행 ~30K 토큰 (룰셋 50개 + 검사 대상 ~6900줄). `--category` 옵션으로 ~6K 토큰까지 축소.

## scan_targets

(Phase 1 스캔 대상 — Glob 패턴)

- .claude-plugin/plugin.json
- hooks/*.sh
- agents/*.md
- skills/*/SKILL.md
- commands/*.md

## exclusion_list

(검사자/검사 대상 분리 원칙 — 메타-루프 가드)

- agents/security-engineer.md  ← 검사자 자기 정의 제외 (R1 완화)

## Phase 1: 카테고리 스캔
... (룰셋 로드 + Glob 매칭)

## Phase 2: security-engineer 호출
... (서브에이전트 spawn — Task tool, Read/Glob/Grep만)

## Phase 3: evaluator 직렬 검증
... (Plan 검증 모드 변형)

## Phase 4: 메인 사실 검증
보고된 {파일}:{라인} 각각에 대해:
  bash -c "grep -n '{Rule.condition}' {file}" → 매칭 확인
매칭 실패 1건 이상 시 → 환각 경보 + 사용자 보고

## Phase 5: 출력 포맷

### 보안 진단 결과 — {timestamp}

[검사 대상] 5 카테고리, {N}개 파일, {M}줄
[룰셋] docs/security-rules.md v{version}, {활성 룰 수}/{전체 룰 수}
[제외] agents/security-engineer.md (메타-루프 가드)

#### Category: plugin
| Rule ID | Severity | 파일:라인 | 설명 | 수정 |
|---------|----------|-----------|------|------|

(나머지 4 카테고리 동일)

#### Risk Map (요약)
| 등급 | 카운트 |
|------|--------|
| Critical | N |
| Warning | M |
| Info | K |

#### 결과 해석 가이드

- **Critical 발견 시**: 즉시 commit 차단 권고 (자동 차단 X). 사용자 검토 후 (a) fix 또는 (b) `--skip-audit` 명시 + NOVA-STATE.md "Skip Reason" 기록.
- **Warning 발견 시**: NOVA-STATE.md "Known Risks" 행 추가 권고. 다음 sprint 정리.
- **Info 발견 시**: 정보성 — 별도 행동 불필요.

## Phase 6: 관찰성

bash hooks/record-event.sh audit_self_verdict "$(jq -cn ...)"

## Known Gap (v5.22.0)

- 정적 분석만 수행 — 런타임 권한 상승, 동적 hooks 체인, MCP 네트워크 호출은 e2e CI로 별도 검증
- 공급망 무결성 (룰 파일 변조) 미커버 — v5.23.0 검토
- --jury Red/Blue/Auditor 다관점 — placeholder만, v5.23.0 구현
```

#### 2. `docs/security-rules.md` 구조

```markdown
---
version: 1.0.0
nova_compat: ">=5.22.0"
last_review_commit: <commit_hash>
---

# Nova Self-Audit Rules

## Source Mapping (ECC AgentShield 102룰 분류 — Sprint 0 결과)

| ECC Rule ID | Nova 적용 | 사유 |
|-------------|-----------|------|
| ECC-001 | (a) Static OK | hooks injection 정적 패턴 매칭 가능 |
| ECC-002 | (b) Dynamic Required | 런타임 권한 escalation — Known Gap |
| ECC-003 | (c) Identity Conflict | Nova 응집형 정체성과 충돌 — 채택 제외 |
... (102행)

요약: (a) Static OK = N개, (b) Dynamic = M개, (c) Identity = K개. (a) ≥30 충족.

## Known Gap (v5.22.0 범위 외)

- 동적 분석: 런타임 권한 상승, 세션 오염, MCP 네트워크 호출
- 공급망 무결성: 룰 파일 변조 검증 (v5.23.0 검토)

## Category: plugin

### Rule R-PLUGIN-001
- **id**: R-PLUGIN-001
- **category**: plugin
- **severity**: Critical
- **condition**: `grep -E '"(api_key|secret|token)"\s*:\s*"[^"]+"' .claude-plugin/plugin.json`
- **normal_example**: `"description": "..."` (시크릿 없음)
- **risk_example**: `"api_key": "sk-..."`  (인라인 시크릿)
- **mitigation**: 시크릿은 환경변수 또는 .env 파일로 외부화

### Rule R-PLUGIN-002
... (총 6~10개)

## Category: hooks

### Rule R-HOOKS-001
- **id**: R-HOOKS-001
- **category**: hooks
- **severity**: Critical
- **condition**: `grep -E 'eval\s+["$]' hooks/*.sh`
- **normal_example**: `cmd="grep pattern file"; bash -c "$cmd"` (정적 문자열)
- **risk_example**: `eval "$USER_INPUT"` (사용자 입력 eval)
- **mitigation**: eval 제거, 명시적 명령 분기 사용

... (각 카테고리 6~10 룰 = 총 30~50)

## Category: agents
... 6~10 룰

## Category: skills
... 6~10 룰

## Category: commands
... 6~10 룰
```

#### 3. `agents/security-engineer.md` 자기 코드 감사 모드 (본문 추가)

기존 본문 끝에 새 섹션:

```markdown
# Nova 자기 코드 감사 모드 (self-audit)

`/nova:audit-self` 호출 시 다음 규약을 적용한다 (메타-루프 가드):

- **검사자/검사 대상 분리 원칙**: 검사 대상에서 `agents/security-engineer.md` 자체를 명시 제외 (R1 완화)
- **룰셋 외부 참조**: 인라인 룰 작성 금지 — `docs/security-rules.md` 룰만 적용
- **출력 포맷**: 카테고리별 섹션 + Risk Map 테이블 (자유 형식 금지)
- **결과 핸드오프**: evaluator 직렬 검증 + 메인 사실 검증 회로 통과 후에만 사용자 보고
- **Known Gap 의무 명시**: 정적 분석으로 검증 불가능한 룰은 출력에 "Dynamic Required" 마킹
```

#### 4. `hooks/session-start.sh` 카탈로그 갱신

기존 커맨드 카탈로그 배열에 추가:

```bash
# lean profile 카탈로그 (≤1200자)
... existing commands ...
"/nova:audit-self"   # ← 1줄 추가 (자기 보안 진단)

# standard/strict profile (≤2500자)
"/nova:audit-self  Nova 자기 보안 진단 (5 카테고리 30~50룰, 정적 분석)"  # ← 설명 포함 1줄
```

#### 5. `tests/test-audit-self.sh` 회귀 가드

```bash
#!/usr/bin/env bash
# Nova /nova:audit-self 회귀 가드 (Sprint 2.1)
set -e

RULES="docs/security-rules.md"
CMD="commands/audit-self.md"

# T1: 룰 스키마 7 필드 모두 존재
for rule_id in $(grep "^### Rule " "$RULES" | sed 's/^### Rule //' | awk '{print $1}'); do
  for field in id category severity condition normal_example risk_example mitigation; do
    grep -A 20 "^### Rule $rule_id" "$RULES" | grep -q "^- \*\*$field\*\*:" \
      || { echo "FAIL: $rule_id missing $field"; exit 1; }
  done
done

# T2: 5 카테고리 누락 감지
for cat in plugin hooks agents skills commands; do
  grep -q "^## Category: $cat$" "$RULES" \
    || { echo "FAIL: category $cat missing"; exit 1; }
done

# T3: 룰 ID 중복 감지
DUPLICATES=$(grep "^### Rule " "$RULES" | sort | uniq -d)
[[ -z "$DUPLICATES" ]] || { echo "FAIL: duplicate rule IDs: $DUPLICATES"; exit 1; }

# T4: 룰 30개 이상
COUNT=$(grep -c "^### Rule " "$RULES")
[[ "$COUNT" -ge 30 ]] || { echo "FAIL: rule count $COUNT < 30"; exit 1; }

# T5: 헤더 version 필드
grep -q "^version:" "$RULES" || { echo "FAIL: version missing"; exit 1; }

# T6: commands/audit-self.md exclusion_list에 security-engineer.md
awk '/^## exclusion_list/,/^## /' "$CMD" | grep -q "agents/security-engineer.md" \
  || { echo "FAIL: exclusion_list missing security-engineer.md (메타-루프 가드)"; exit 1; }

# T7: scan_targets 헤더 H2
grep -q "^## scan_targets$" "$CMD" || { echo "FAIL: scan_targets H2 missing"; exit 1; }

# T8: --category 옵션 정의
grep -q -- "--category" "$CMD" || { echo "FAIL: --category option missing"; exit 1; }

# T9: 결과 해석 가이드 섹션
grep -q "결과 해석 가이드\|Critical 발견 시" "$CMD" \
  || { echo "FAIL: 결과 해석 가이드 missing"; exit 1; }

echo "PASS: test-audit-self ($COUNT rules, all 5 categories)"
```

#### 6. `hooks/record-event.sh` audit_self_verdict 이벤트 (Sprint 2.5 선택)

기존 schema v2 호환. extra payload에 audit-self 전용 필드:

```bash
bash hooks/record-event.sh audit_self_verdict "$(jq -cn \
  --arg v "$VERDICT" \
  --argjson c "$CRITICAL" \
  --argjson w "$WARNING" \
  --argjson i "$INFO" \
  --arg cat "${CATEGORY:-all}" \
  '{verdict:$v, critical_count:$c, warning_count:$w, info_count:$i, category:$cat}')" 2>/dev/null || true
```

이벤트 타입 신규 추가 — record-event.sh 자체는 수정 불요 (extra JSON만 다름).

### 데이터 계약 (Data Contract)

#### Rule 스키마 (docs/security-rules.md `### Rule <ID>` 블록)

| 필드 | 타입 | 단위/포맷 | 검증 규칙 | 예시 |
|------|------|-----------|-----------|------|
| `id` | string | `R-{CATEGORY}-{NNN}` | 정규식 `^R-(PLUGIN\|HOOKS\|AGENTS\|SKILLS\|COMMANDS)-\d{3}$` | `R-HOOKS-001` |
| `category` | enum | `plugin\|hooks\|agents\|skills\|commands` | 5종 중 정확히 1개 | `hooks` |
| `severity` | enum | `Critical\|Warning\|Info` | 3단 분류만 허용 | `Critical` |
| `condition` | string | bash 1-liner (grep/awk/find) | 종료 코드 0 = 위반 발견. **정규식은 grep 가능 ERE** | `grep -E 'eval\s+["$]' hooks/*.sh` |
| `normal_example` | string | 코드 스니펫 | 룰을 통과하는 정상 케이스 | `cmd="grep p f"; bash -c "$cmd"` |
| `risk_example` | string | 코드 스니펫 | 룰에 걸리는 위험 케이스 | `eval "$USER_INPUT"` |
| `mitigation` | string | 자유 텍스트 | 1~3 문장 권장 | `eval 제거, 명시적 명령 분기 사용` |

#### audit-self 출력 포맷 (Phase 5)

| 필드 | 타입 | 형식 |
|------|------|------|
| 카테고리 섹션 헤더 | markdown H4 | `#### Category: {name}` |
| 위반 항목 행 | markdown table | `\| {rule_id} \| {severity} \| {file}:{line} \| {desc} \| {mitigation} \|` |
| Risk Map 요약 | markdown table | Critical/Warning/Info 카운트 |
| timestamp | ISO 8601 UTC | `2026-04-29T01:30:00Z` |
| version | semver | `docs/security-rules.md` 헤더 그대로 |

#### audit_self_verdict 이벤트 스키마 (record-event.sh extra)

| 필드 | 타입 | 단위/포맷 | 비고 |
|------|------|-----------|------|
| `verdict` | enum | `PASS\|FAIL\|SKIPPED` | PASS = Critical 0, FAIL = Critical ≥1, SKIPPED = `--skip-audit` |
| `critical_count` | integer | 정수 ≥0 | Critical 위반 룰 매칭 수 |
| `warning_count` | integer | 정수 ≥0 | Warning 위반 |
| `info_count` | integer | 정수 ≥0 | Info 위반 |
| `category` | string | `all\|plugin\|hooks\|agents\|skills\|commands` | `--category` 지정값 또는 `all` |

> 이벤트는 schema v2의 `extra` 필드로 들어간다. record-event.sh privacy filter가 자동 redact 처리. 별도 변경 없음.

### 에러 처리

| 에러 | 발생 조건 | 처리 |
|------|-----------|------|
| `docs/security-rules.md` 부재 | Sprint 1.2 미완 또는 사용자 삭제 | 즉시 종료, exit 1, 메시지 "룰셋 파일 없음 — Sprint 1 미완 또는 파일 삭제 의심" |
| `--category` 잘못된 값 | 5종 외 입력 | 종료, exit 1, 사용 가능 카테고리 5종 출력 |
| security-engineer spawn 실패 | Task tool 오류 | 메인 컨텍스트가 실패 캐치, "Phase 2 실패 — 1회 재시도 후 사용자 보고" |
| evaluator 직렬 호출 실패 | skills/evaluator 미동작 | Phase 3 skip + 출력에 ⚠️ 마커 "Phase 3 미실행 — security-engineer 단독 결과" |
| 메인 사실 검증 grep 매칭 실패 (≥1건) | 환각 가능성 | 출력에 "⚠️ Evaluator 환각 경보: {N}건 매칭 실패" + 해당 항목은 "검증 불가" 마킹 |
| `--jury` 호출 (v5.22.0) | placeholder | 종료 X, "v5.23.0 예정" 메시지 출력 후 단일 모드 진행 |
| record-event.sh 실패 | jq 미설치 등 | safe-default — 파이프라인 영향 없음 (record-event.sh가 자체 처리) |
| 토큰 한계 초과 | 검사 대상 너무 큼 | `--category` 옵션 권고 메시지 출력 후 진행 (실패 X — Phase 1이 Glob만 로드) |

---

## Sprint Contract (스프린트별 검증 계약)

> Plan의 Verification Hooks V1~V15와 정합. Generator는 구현 전 본 계약을 읽고 따른다. Evaluator는 본 계약으로 PASS/FAIL 판정.

| Sprint | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|--------|-----------|-----------|-----------|----------|
| **0.1** | ECC 102룰 3분류 (Source Mapping 표) — (a) Static OK / (b) Dynamic / (c) Identity | docs/security-rules.md 헤더 grep | `grep -q "^## Source Mapping" docs/security-rules.md && [ $(awk '/^## Source Mapping/,/^## /' docs/security-rules.md \| grep -c "^\| ECC-") -ge 100 ]` | Critical |
| **0.2** | (a) 분류 흡수 → Nova 룰 ≥30 보장 | 룰 카운트 (Source Mapping 표는 카테고리 그룹 단위 압축이므로 룰 카운트로 환산 검증) | `[ $(grep -c "^### Rule " docs/security-rules.md) -ge 30 ]` | Critical |
| **0.3** | proposals/2026-04-29-ecc-adversarial-gap.md §P1-1에 분류 결과 링크 | proposal grep | `grep -q "audit-self" docs/proposals/2026-04-29-ecc-adversarial-gap.md` | High |
| **1.1** | commands/audit-self.md 신규 + frontmatter description + scan_targets H2 + exclusion_list H2 | 헤더 grep | `grep -q "^description:" commands/audit-self.md && grep -q "^## scan_targets$" commands/audit-self.md && grep -q "^## exclusion_list$" commands/audit-self.md` | Critical |
| **1.2** | docs/security-rules.md 신규 + 5 카테고리 + 룰 ≥30 | grep + count | `for c in plugin hooks agents skills commands; do grep -q "^## Category: $c$" docs/security-rules.md \|\| exit 1; done && [ $(grep -c "^### Rule " docs/security-rules.md) -ge 30 ]` | Critical |
| **1.3** | agents/security-engineer.md self-audit 섹션 + commands/audit-self.md exclusion_list 메타-루프 가드 | 두 파일 동시 검증 | `grep -q "메타-루프\|self-audit" agents/security-engineer.md && awk '/^## exclusion_list/,/^---$/' commands/audit-self.md \| grep -q "agents/security-engineer.md"` | Critical |
| **1.4** | hooks/session-start.sh `/nova:audit-self` 카탈로그 + lean ≤1200(soft) AND hard ≤2500 양쪽 | 3 프로파일 wc -c | `lean=$(NOVA_PROFILE=lean bash hooks/session-start.sh \| jq -r '.hookSpecificOutput.additionalContext' \| wc -c); std=$(NOVA_PROFILE=standard bash hooks/session-start.sh \| jq -r '.hookSpecificOutput.additionalContext' \| wc -c); strict=$(NOVA_PROFILE=strict bash hooks/session-start.sh \| jq -r '.hookSpecificOutput.additionalContext' \| wc -c); [ $lean -le 1200 ] && [ $std -le 2500 ] && [ $strict -le 2500 ]` | Critical |
| **1.5** | tests/test-scripts.sh EXPECTED_COMMANDS에 `audit-self` + 회귀 PASS | grep 컨텍스트 + 전체 테스트 | `grep -A 5 "EXPECTED_COMMANDS=(" tests/test-scripts.sh \| grep -q audit-self && bash tests/test-scripts.sh` | Critical |
| **2.1** | tests/test-audit-self.sh 신규 회귀 가드 PASS (T1~T9) | 회귀 실행 | `bash tests/test-audit-self.sh` exit 0 | Critical |
| **2.2** | docs/nova-rules.md audit-self 1줄 + 메타-루프 가드 1줄 | grep | `[ $(grep -c "audit-self\|메타-루프" docs/nova-rules.md) -ge 2 ]` | High |
| **2.3** | commands/review.md 보안 스코프 → audit-self 우선 안내 | grep | `grep -q "audit-self" commands/review.md` | High |
| **2.4** | commands/next.md 워크플로우에 audit-self 추가 | grep | `grep -q "audit-self" commands/next.md` | High |
| **2.5** | (선택) hooks/record-event.sh audit_self_verdict 호출 통합 | grep | `grep -q "audit_self_verdict" hooks/record-event.sh \|\| grep -q "audit_self_verdict" commands/audit-self.md` | Nice-to-have |
| **2.6** | commands/audit-self.md "결과 해석 가이드" + Critical 권장 행동 | grep | `grep -q "결과 해석 가이드\|Critical 발견 시" commands/audit-self.md` | High |
| **2.7** | commands/audit-self.md `--category` 옵션 + 토큰 추정 | grep | `grep -q -- "--category" commands/audit-self.md && grep -q "토큰\|tokens" commands/audit-self.md` | High |
| **2.8** | docs/security-rules.md 헤더 version + Known Gap 섹션 | grep | `grep -q "^version:" docs/security-rules.md && grep -q "Known Gap\|공급망" docs/security-rules.md` | Critical |
| **2.9** | Evaluator 독립 서브에이전트 PASS — Sprint 0+1+2 + V1~V15 모두 | spawn evaluator | (메인이 Agent 도구로 evaluator skill 호출 후 verdict 확인) | Critical |

### Sprint Contract 작성 원칙 준수 검증

- [x] 구현 전 정의 — 본 Design은 commands/audit-self.md 작성 전 작성됨
- [x] 테스트 가능 — 모든 Done 조건이 grep/wc -c/test exit code로 자동 검증
- [x] 검증 명령 명시 — 17건 모두 실행 가능한 bash one-liner 포함
- [x] Evaluator 수정 요청 가능 — 2.9가 별도 Evaluator 라운드로 분리
- [x] "사용자가 쓸 수 있다" 기준 — 1.4 (session-start 카탈로그 노출), 2.6 (결과 해석 가이드), 2.7 (--category 옵션) 모두 사용자 노출 검증

---

## 관통 검증 조건 (End-to-End)

> "저장됨" ≠ "사용 가능함". 룰셋 정의 → 사용자 명령 → 실제 위반 탐지 → 결과 보고 흐름이 관통하는지 검증.

| # | 시작점 (사용자 행동) | 종착점 (결과 확인) | 우선순위 |
|---|---------------------|-------------------|---------|
| E1 | 사용자가 `/nova:audit-self` 입력 | session-start 카탈로그에 `audit-self` 표시 + 명령 입력 시 commands/audit-self.md 로드 | Critical |
| E2 | `/nova:audit-self --category hooks` 실행 | Phase 1이 hooks/*.sh 만 Glob 로드 + 다른 4 카테고리 룰 비활성 | Critical |
| E3 | hooks/test-injection.sh에 의도적으로 `eval "$USER_INPUT"` 삽입 후 audit-self 실행 | 출력 Risk Map에 Critical 1건 + 카테고리 hooks 섹션에 R-HOOKS-001 행 + 파일:라인 정확 | Critical |
| E4 | audit-self가 보고한 `{파일}:{라인}` 항목을 메인이 grep -n으로 1회 검증 | 매칭 성공 → 정상 사용자 보고 / 매칭 실패 → "⚠️ Evaluator 환각 경보" 출력 | Critical |
| E5 | audit-self 종료 후 `.nova/events.jsonl` 확인 | `audit_self_verdict` 이벤트 1행 + verdict/카운트 필드 정확 (Sprint 2.5 선택, Nice-to-have) | High |
| E6 | docs/security-rules.md 룰 스키마 필드 1개 의도적 누락 후 `bash tests/test-audit-self.sh` | 회귀 가드 FAIL + 누락 필드 메시지 출력 | Critical |
| E7 | `/nova:audit-self` 실행 시 메타-루프 가드 동작 확인 — agents/security-engineer.md를 검사하지 않음 | 출력에 "[제외] agents/security-engineer.md (메타-루프 가드)" 명시 + 해당 파일 위반 0건 | Critical |
| E8 | NOVA_PROFILE 3종 모두 session-start 출력 측정 | lean ≤1200, standard ≤2500, strict ≤2500 모두 만족 | Critical |
| E9 | 사용자가 `/nova:audit-self --jury` 입력 | "v5.23.0 예정" 메시지 출력 후 단일 모드 진행 (placeholder 동작) | High |

---

## 평가 기준 (Evaluation Criteria)

### 기능
- 모든 Sprint Contract Done 조건 (17건) PASS
- 5 카테고리 30~50 룰셋 모두 동작 — 룰별 condition grep이 실제 매칭
- 메타-루프 가드 — security-engineer.md 검사 제외 동작 확인
- 메인 사실 검증 회로 — 매칭 실패 시 환각 경보 출력 확인

### 설계 품질
- 룰 외부화 (docs/security-rules.md) — git diff로 룰 변경 1:1 추적 가능
- exclusion_list 구조적 매칭 — 마크다운 H2 헤더 + awk 패턴 정합
- 부분 실행 (`--category`) — 토큰 압박 완화 (~30K → ~6K)
- v5.22.0 범위 외 항목 모두 Known Gap 명시 (정적 분석 한계, 공급망, --jury)

### 단순성
- 단일 커맨드 진입점 — `/nova:audit-self` 1개
- 5 카테고리 + 7 필드 룰 스키마 — 사용자 학습 곡선 최소화
- 자동 차단 도입 X — 정보성 권고만, 사용자 결정권 보장
- 신규 에이전트 추가 X — 기존 security-engineer 재사용

---

## 역방향 검증 체크리스트

> Plan의 Problem 7 영역 + Risk Map R1~R11 + Verification Hooks V1~V15가 본 Design에 모두 반영되었는지 확인.

### Plan Problem MECE 7+2 영역

- [x] P1 검사 대상 부재 → Phase 1 + scan_targets 5 카테고리 정의
- [x] P2 검사 신뢰도 부재 → Phase 3 evaluator 직렬 + Phase 4 메인 사실 검증 회로
- [x] P3 메타-루프 자가 합리화 → exclusion_list 구조적 매칭 (T2)
- [x] P4 룰셋 자기 검증 부재 → tests/test-audit-self.sh T1~T9 회귀 가드
- [x] P5 정적 분석 한계 → Known Gap 명시 + `--mode static` 어휘 도입
- [x] P6 release 통합 미정의 → 자동 차단 도입 X (v5.22.0), 6개월 후 patch 검토 명시
- [x] P7 유지보수 절차 부재 → docs/security-rules.md 헤더 version + nova_compat 필드
- [x] P8 인시던트 대응 흐름 부재 → "결과 해석 가이드" 섹션 + Critical 권장 행동
- [x] P9 검사 도구 자체의 무결성 → Known Gap 명시 (v5.22.0 범위 외) + last_review_commit 필드

### Risk Map R1~R11

- [x] R1 메타-루프 자가 합리화 → exclusion_list 구조적 매칭
- [x] R2 False Negative → Known Gap "Dynamic Required" 마킹
- [x] R3 False Positive → Critical/Warning/Info 3단 분류 + 룰별 normal_example 강제 필드
- [x] R4 룰셋 자기 검증 부재 → tests/test-audit-self.sh T1~T9
- [x] R5 Evaluator 환각 → Phase 4 메인 사실 검증 회로 + 환각 경보 출력
- [x] R6 release.sh 통합 함정 → v5.22.0은 수동 호출만 (자동 차단 X)
- [x] R7 룰셋 유지보수 → 헤더 version + nova_compat
- [x] R8 session-start lean 1200자 → 1.4가 lean ≤1200 + std/strict ≤2500 양쪽 검증
- [x] R9 토큰 압박 → `--category` 옵션 + Phase 1 Glob만 (조건부 Read)
- [x] R10 룰 파일 공급망 무결성 → Known Gap 명시 + last_review_commit
- [x] R11 인시던트 대응 흐름 → "결과 해석 가이드" + Critical 권장 행동

### Verification Hooks V1~V15

- [x] V1 commands/audit-self.md 존재 → 1.1 Done
- [x] V2 5 카테고리 → 1.2 Done
- [x] V3 룰 ≥30 → 1.2 Done + Sprint 0.2
- [x] V4 메타-루프 가드 구조적 매칭 → 1.3 Done (awk 패턴)
- [x] V5 EXPECTED_COMMANDS 동기화 → 1.5 Done
- [x] V6 session-start 양쪽 검증 → 1.4 Done (3 프로파일)
- [x] V7 전체 회귀 → 1.5 Done
- [x] V8 test-audit-self.sh → 2.1 Done
- [x] V9 docs/nova-rules.md 1줄 → 2.2 Done
- [x] V10 review.md/next.md 크로스 레퍼런스 → 2.3, 2.4 Done
- [x] V11 Evaluator PASS + 메인 사실 검증 → 2.9 Done + Phase 4
- [x] V12 FP rate 측정 → "결과 해석 가이드" 섹션에 측정 절차 명시
- [x] V13 audit_self_verdict 이벤트 → 2.5 Done (선택)
- [x] V14 토큰 추정 + --category → 2.7 Done
- [x] V15 결과 해석 가이드 + Critical 권장 → 2.6 Done

### 누락 엣지 케이스 점검

- [x] 사용자 .claude/rules/ 충돌 — Plan/Design 모두 미언급. **추가 메모**: Nova 룰셋(docs/security-rules.md)과 사용자 룰(.claude/rules/)은 우선순위 명시 필요. v5.22.0은 Nova 룰만 로드 (사용자 룰 통합은 v5.23.0+ Known Gap)
- [x] 다국어 룰셋 — 모든 룰 condition은 ASCII 정규식만 (한글 매칭은 grep -P 또는 별도 처리). docs/security-rules.md에 명시
- [x] 외부 PR 기여자 룰 추가 — release.sh가 docs/security-rules.md diff 검토 의무 (v5.23.0 검토 명시)
- [x] 회귀 가드 자기 적용 — tests/test-audit-self.sh 자체는 tests/test-scripts.sh가 호출 (자동 회귀 통합)
