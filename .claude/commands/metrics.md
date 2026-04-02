---
description: "현재 프로젝트의 Nova Engineering 도입 수준을 자동 측정한다."
---

현재 프로젝트의 Nova Engineering 도입 수준을 자동 측정한다.

# Role
너는 Nova Engineering 도입 수준 평가자다.
프로젝트 파일 구조, 문서, 설정을 점검하여 Nova 4대 Pillar별 점수를 산출한다.

# Execution

아래 17개 항목을 **하나씩 실제로 확인**한다. 추측하지 말고 파일/디렉토리 존재 여부를 직접 검사한다.

---

## 1단계: Structured (5점)

### S1 — CLAUDE.md 존재 및 필수 섹션 포함 (1pt)
- 프로젝트 루트에 `CLAUDE.md`가 존재하는지 확인한다.
- 다음 섹션이 포함되어야 한다: Language, Nova(또는 Engineering), Tech Stack, Conventions(또는 Git Convention), Human-AI(Boundary)
- 5개 중 4개 이상 있으면 1pt.

### S2 — Plan 문서 존재 (1pt)
- `docs/plans/` 디렉토리에 `.md` 파일이 1개 이상 있는지 확인한다.
- CPS 구조(Context, Problem, Solution) 키워드가 포함되어야 한다.

### S3 — Design 문서 존재 (1pt)
- `docs/designs/` 디렉토리에 `.md` 파일이 1개 이상 있는지 확인한다.
- CPS 구조 키워드가 포함되어야 한다.

### S4 — 린터/포매터 설정 존재 (1pt)
- 다음 중 1개 이상 존재하면 통과: `.eslintrc*`, `.prettierrc*`, `biome.json`, `.stylelintrc*`, `ruff.toml`, `pyproject.toml`(ruff/black 섹션), `.golangci.yml`, `deno.json`(lint 섹션)

### S5 — 최근 커밋 컨벤션 준수 (1pt)
- `git log --oneline -10`으로 최근 10개 커밋을 확인한다.
- 70% 이상(7개 이상)이 `feat:`, `fix:`, `update:`, `docs:`, `refactor:`, `chore:`, `security:`, `nova:` 접두사를 따르면 1pt.

---

## 2단계: Idempotent (4점)

### I1 — 템플릿 디렉토리 존재 (1pt)
- `docs/templates/` 디렉토리에 `.md` 파일이 1개 이상 있는지 확인한다.

### I2 — CLAUDE.md에 Tech Stack 정보 포함 (1pt)
- `CLAUDE.md`에 "Tech Stack", "기술 스택", 또는 동등한 섹션이 있는지 확인한다.

### I3 — 컨텍스트 체인 존재 (1pt)
- `docs/context-chain.md` 또는 유사한 컨텍스트 복원 문서가 존재하는지 확인한다.
- 또는 `.claude/` 내 메모리/컨텍스트 관련 파일이 존재하면 통과.

### I4 — 의사결정 기록 존재 (1pt)
- `docs/decisions/` 디렉토리에 `.md` 파일이 1개 이상 있는지 확인한다.

---

## 3단계: X-Verification (4점)

### X1 — 다관점 수집 커맨드 존재 (1pt)
- `.claude/commands/xv.md`가 존재하면 통과.

### X2 — 다관점 수집 결과 기록 존재 (1pt)
- `docs/verifications/` 디렉토리에 파일이 1개 이상 있는지 확인한다.

### X3 — 갭 체크 커맨드 존재 (1pt)
- `.claude/commands/gap.md`가 존재하면 통과.

### X4 — 최근 갭 체크 결과 존재 (1pt)
- `docs/gap-reports/` 또는 `docs/verifications/` 내 gap 관련 파일이 있는지 확인한다.

---

## 4단계: Harness (3점)

### H1 — CLAUDE.md에 자동 적용 규칙 존재 (1pt)
- `CLAUDE.md`에 "자동 적용 규칙" 또는 "Generator-Evaluator" 관련 섹션이 있는지 확인한다.
- 복잡도 판단, 독립 검증, 블로커 분류 중 2개 이상 존재하면 1pt.

### H2 — Sprint Contract 또는 검증 계약 존재 (1pt)
- `docs/designs/` 내 Design 문서에 "Sprint Contract" 또는 "검증 계약" 섹션이 있는지 확인한다.
- 1개 이상의 Design에 존재하면 1pt.

### H3 — Independent Verification 결과 존재 (1pt)
- `docs/verifications/` 내 검증 결과가 1개 이상 있고, 내용에 "Evaluator" 또는 "PASS/FAIL" 판정이 포함되어 있으면 1pt.

---

## Adaptive (4점)

> **Adaptive는 축적이 필요하다.** 프로젝트 초기(1~2세션)에 A2~A4가 0점인 것은 정상이다.
> 반복 패턴은 3~4세션 이상 진행된 후에야 의미 있게 감지된다.
> 초기 세션에서는 "Adaptive 영역은 프로젝트 진행에 따라 자연스럽게 채워집니다"로 안내한다.

### A1 — /propose 커맨드 사용 가능 (1pt)
- `.claude/commands/propose.md`가 존재하는지 확인한다.

### A2 — 규칙 변경 이력 존재 (1pt)
- `docs/rules-changelog.md`가 존재하고 내용이 있는지 확인한다.
- **초기 프로젝트 보정**: git log에서 커밋 수가 30개 미만이면, 이 항목을 "아직 측정 불가"로 표시하고 감점하지 않는다.

### A3 — 규칙 제안 템플릿 존재 (1pt)
- `docs/templates/rule-proposal.md`가 존재하는지 확인한다.

### A4 — 규칙 제안 기록 존재 (1pt)
- `docs/proposals/` 디렉토리에 `.md` 파일이 1개 이상 있는지 확인한다.
- **초기 프로젝트 보정**: git log에서 커밋 수가 30개 미만이면, 이 항목을 "아직 측정 불가"로 표시하고 감점하지 않는다.

### Adaptive 성숙도 표시

Adaptive 점수 출력 시 프로젝트 성숙도를 함께 표시한다:

```
  Adaptive:        ■□□□□  1/4  (커밋 15개 — 아직 초기 단계, A2·A4 측정 보류)
```

프로젝트가 충분히 진행된 후(커밋 30개+):
```
  Adaptive:        ■□□□□  1/4  (커밋 87개 — 규칙 제안·변경 이력 부재)
```

---

## 5단계: 결과 출력

모든 항목 점검 후 아래 형식으로 **한국어** 결과를 출력한다.

### 등급 기준
| 등급 | 점수 | 설명 |
|------|------|------|
| Level 5 | 20점 (또는 만점) | Nova 완전 적용 (Harness 포함) |
| Level 4 | 16~19점 | 높은 수준 |
| Level 3 | 11~15점 | 중간 |
| Level 2 | 6~10점 | 초기 |
| Level 1 | 0~5점 | 시작 단계 |

> **Adaptive 보정**: 초기 프로젝트(커밋 30개 미만)에서 "측정 보류"된 항목은 총점과 만점 모두에서 제외한다.
> 예: A2, A4가 보류되면 총점 X/18 기준으로 등급을 판정한다.

### 출력 형식

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Nova Metrics — 도입 수준 자동 측정
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Structured:      ■■■■□  4/5
  Idempotent:      ■■■□□  3/4
  X-Verification:  ■■□□□  2/4
  Harness:         ■■□□□  2/3
  Adaptive:        ■□□□□  1/4

  총점: 12/20 → Level 3 (중간)

━━━ 세부 항목 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✅ S1 CLAUDE.md 존재 및 필수 섹션 포함
  ✅ S2 Plan 문서 3개
  ❌ S3 Design 문서 없음
  ✅ S4 린터 설정 존재 (biome.json)
  ✅ S5 커밋 컨벤션 준수 (8/10)

  ✅ I1 템플릿 디렉토리 존재 (3개 파일)
  ✅ I2 Tech Stack 섹션 존재
  ❌ I3 컨텍스트 체인 없음
  ✅ I4 의사결정 기록 2개

  ✅ X1 다관점 수집 커맨드 존재
  ❌ X2 다관점 수집 결과 없음
  ✅ X3 갭 체크 커맨드 존재
  ❌ X4 갭 체크 결과 없음

  ✅ A1 /propose 커맨드 존재
  ❌ A2 규칙 변경 이력 없음
  ❌ A3 규칙 제안 템플릿 없음
  ✅ A4 규칙 제안 1개

━━━ 개선 추천 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  점수가 낮은 Pillar 순으로 최대 3개 개선 사항을 추천한다.
  각 추천에는 실행 가능한 커맨드나 구체적 행동을 포함한다.

  예시:
  1. /design 실행하여 기술 설계 문서 작성 (S3 해소)
  2. /xv "주요 설계 질문" 실행하여 다관점 수집 시작 (X2 해소)
  3. /propose 실행하여 규칙 제안 프로세스 시작 (A2, A4 해소)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 점수바 생성 규칙
- 획득 점수만큼 `■`, 나머지는 `□`
- 예: 3/5이면 `■■■□□`

# Notes
- 파일이 존재하지만 내용이 비어있으면 미통과로 판정한다.
- 각 항목은 0 또는 1의 이진 점수다 (부분 점수 없음).
- 실제 파일을 읽어서 확인한다. 단순 디렉토리 존재만으로 통과시키지 않는다.
- 개선 추천은 점수가 가장 낮은 Pillar부터 제시한다.
- 동점이면 S → I → X → A 순으로 우선한다.

# Input
$ARGUMENTS
