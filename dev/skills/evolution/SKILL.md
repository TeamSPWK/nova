---
name: evolution
description: "Nova 자체를 진화시킬 때 사용한다. — MUST TRIGGER: /nova:evolve 호출, 외부 기술 동향을 Nova에 반영해야 할 때, Nova 메타-개선(규칙/스킬/훅 구조 변경) 작업."
description_en: "Use when evolving Nova itself. — MUST TRIGGER: /nova:evolve invocation, when external tech trends must be reflected into Nova, or Nova meta-improvement (rules/skills/hooks structural changes)."
user-invocable: false
---

# Nova Self-Evolution Pipeline

`/nova:evolve` 커맨드의 핵심 파이프라인을 정의한다.

## Pipeline Overview

```
Scanner → Filter → Proposal → [Builder → Gate Chain → Merge]
                                        (--apply/--auto만)
```

## Scanner 소스 상세

Scanner는 **WebSearch + GitHub Search API (`gh api`)** 두 채널을 병렬 사용한다. `gh api`는 star/topic 같은 정량 시그널을 수집하고, WebSearch는 changelog/블로그 같은 서술 정보를 수집한다.

### Anthropic 공식 (최고 우선순위, 임계값 면제)

WebSearch 키워드:
- `site:docs.anthropic.com Claude Code`
- `site:anthropic.com/blog`
- `Claude Code changelog latest`
- `Claude Code hooks MCP update`

`gh api` 쿼리:
```bash
gh api 'search/repositories?q=org:anthropics+claude-code&sort=updated&per_page=10'
gh api 'search/repositories?q=org:anthropics+language:TypeScript&sort=updated&per_page=10'
```

체크 포인트:
- Claude Code 새 버전/기능
- MCP 프로토콜 변경
- hooks API 변경
- 새로운 도구/권한 모델
- 플러그인 시스템 변경

### Claude Code 생태계

WebSearch 키워드:
- `Claude Code plugin community`
- `CLAUDE.md best practices 2026`
- `Claude Code custom agents`

`gh api` 쿼리:
```bash
gh api 'search/repositories?q=claude+code+skills+in:name,description&sort=stars&per_page=10'
gh api 'search/repositories?q=topic:claude-code&sort=stars&per_page=10'
gh api 'search/repositories?q=awesome-claude-code&sort=stars&per_page=10'
gh api 'search/repositories?q=claude+code+mcp+in:name,description&sort=stars&per_page=10'
```

체크 포인트:
- 인기 있는 플러그인 패턴
- CLAUDE.md 작성 최신 권장사항
- 에이전트 설계 패턴

### 하네스 도구 (오픈소스)

WebSearch 키워드:
- `aider changelog latest`
- `cursor rules update`
- `AI coding assistant comparison 2026`
- `LLM harness engineering`

`gh api` 쿼리 (2개 — 다양성 의무 충족 후 노이즈 회피):
```bash
gh api 'search/repositories?q=aider-chat+in:name,description&sort=stars&per_page=10'
gh api 'search/repositories?q=cursor+rules+in:name,description&sort=stars&per_page=10'
```

> **총 8개 쿼리** (Anthropic 2 + 생태계 4 + 하네스 2). cline/continue.dev/windsurf는 WebSearch 키워드로 커버. 추가 쿼리 필요 시 `--sources` 옵션으로 확장 가능.

체크 포인트:
- 다른 도구에서 검증된 패턴
- Nova에 없는 유용한 기능
- 품질 게이트 관련 새로운 접근법

### Baseline Fallback

WebSearch와 `gh api` 채널을 다음 기준으로 평가한다:

| 채널 결과 | 분류 |
|---|---|
| 정상 응답 + 결과 0건 | 0건 |
| HTTP 200 + 결과 ≥1건 | 정상 |
| HTTP 403 (rate-limit) | **실패** |
| HTTP 5xx / network timeout | **실패** |
| `gh: command not found` / 미인증 | **실패** |
| WebSearch 도구 호출 실패 | **실패** |

**Baseline fallback 트리거**: (WebSearch == 실패 OR WebSearch == 0건) **AND** (gh api 8개 쿼리 모두 실패 OR 모두 0건). 이 조건 충족 시 `dev/docs/evolve-baseline.md`에서 `nova_applied=false` 항목을 로드해 Phase 2 입력으로 전달. 보고서 헤더에 `⚠ Baseline fallback — Live scan failed (reason: {WebSearch={상태}, gh_api={실패 N건/0건 N건})` 명시.

부분 실패(WebSearch 정상 + gh api 일부만 실패)는 fallback 트리거 X — 사용 가능한 데이터로 계속 진행하되 Phase 1 출력에 skip 카운트 노출.

Baseline 갱신 책임은 [dev/docs/evolve-baseline.md](../../docs/evolve-baseline.md) 참조.

## Relevance Filter 상세

Filter는 **3단계 직렬**로 동작한다: ① 신호 강도 임계값 → ② Ledger 매칭(중복 흡수 차단) → ③ MUST/MUST NOT 조건.

### ① 신호 강도 임계값

| 조건 | 통과 기준 |
|---|---|
| GitHub 레포 | `stars ≥ 100` **OR** `updated_within_180d` |
| Anthropic 공식 (`docs.anthropic.com`, `github.com/anthropics/*`, `anthropic.com/blog`) | **임계값 면제** (무조건 통과) |
| `--min-stars N` 오버라이드 | N>0이면 임계값을 N으로 대체 |
| `--min-stars 0` | 임계값 비활성화 — **모든 GitHub 레포 통과** (노이즈 폭증 주의, 디버그/탐색용) |

낮은 임계값은 노이즈, 너무 높으면 신생 도구 누락 — 100은 시작점이며 측정 후 조정한다.

### ② Ledger 매칭 (중복 흡수 차단)

각 발견 항목에 대해 `dev/docs/proposals/_ABSORBED.md`를 조회:

1. `source_url` substring 매칭 (status≠deprecated 한정) → **이미 흡수** 표기 후 제안 제외
2. 미매칭 시 `title/description` 키워드 ↔ `pattern_slug` fuzzy 매칭(단어 단위) → **잠재 중복** 표기. 자동 폐기 X — Phase 3 제안서 항목으로 포함하되 `⚠ ledger 잠재 중복: {pattern_slug}` 주석을 제안서 헤더에 명시. 사용자는 다음 사이클에서 별도 응답할 필요 없으며, 제안서를 읽고 직접 채택/폐기 판단 (수락 시 일반 머지 흐름, 폐기 시 제안서 삭제).
3. 매칭 없음 → ③ MUST 조건으로 진행

### ③ MUST 조건 (하나라도 해당해야 통과)

1. Nova의 commands/, skills/, agents/, hooks/ 에 직접 영향
2. Generator-Evaluator 분리 패턴 강화 가능
3. 세션 간 맥락 보존 개선 가능
4. 검증 기준(5차원) 확장 가능
5. Claude Code 플러그인 호환성 영향

### MUST NOT 조건 (하나라도 해당하면 제외)

1. Nova 철학(하네스 엔지니어링)에 반하는 변경
2. Generator-Evaluator 분리를 약화하는 변경
3. 출처 URL이 없는 정보 기반 변경
4. 사용자 프로젝트의 `.claude/rules/` 우선순위를 침범하는 변경

## Autonomy Levels 상세

### patch (Full Auto)

변경 가능 범위:
- `docs/eval-checklist.md` — 체크리스트 항목 추가/수정
- `docs/nova-rules.md` — 규칙 문구 개선 (의미 변경 불가)
- `docs/templates/*.md` — 템플릿 보완
- `commands/*.md` — 오타 수정, 문구 개선 (로직 변경 불가)
- `README.md`, `README.ko.md` — 문서 개선

변경 불가:
- `hooks/*.sh` — 세션 훅은 patch로 변경 불가
- `skills/*/SKILL.md` — 스킬 로직 변경 불가
- `mcp-server/src/**` — 서버 코드 변경 불가

### minor (Semi Auto — PR)

변경 가능 범위:
- patch 범위 전체 +
- `hooks/*.sh` — 훅 로직 개선
- `commands/*.md` — 옵션 추가, 검증 기준 추가
- `skills/*/SKILL.md` — 스킬 로직 개선
- `docs/nova-rules.md` — 규칙 추가/변경 (session-start.sh 동기화 필수)

### major (Manual — 제안만)

- 새 커맨드 파일 생성
- 새 스킬 디렉토리 생성
- 기존 커맨드/스킬 삭제
- `mcp-server/src/**` 변경
- 호환성이 깨지는 모든 변경

## Gate Chain 실행 규칙

1. **Gate 1 (Tests)**: `bash tests/test-scripts.sh` 실행
   - FAIL 시 변경 전체를 `git restore .`으로 롤백
   - 롤백 후 해당 제안을 "Gate 1 FAIL"로 표기

2. **Gate 2 (Evaluator)**: `/nova:review --fast` 실행
   - FAIL 시 수정 1회 시도
   - 재시도 후에도 FAIL이면 롤백 + "Gate 2 FAIL" 표기

3. **Gate 3 (수준별 분기)**:
   - patch + `--auto`: 커밋 메시지 자동 생성, `git add` + `git commit`
   - minor + `--auto`: 브랜치 생성 + PR + **`_ABSORBED.md` ledger 행 append**
   - major: 제안서만 유지 (ledger 영향 없음 — 사용자 결재 후 머지 시 append)

### Ledger Append 규칙

minor 머지 또는 major 사용자 결재 직후:
```
| {pattern_slug} | {source_url} | v{current_version} | {nova_artifact_path} | active |
```
- `pattern_slug` — kebab-case, 외부 도구 일반명 (예: `aider-repo-map`, `cursor-rules-mdc`)
- `nova_artifact_path` — 흡수 결과물 경로 (예: `skills/new-skill/SKILL.md`)
- patch는 ledger 영향 없음 (문서 보정 수준이라 중복 제안 차단 가치 낮음)


## Phase 1: Behavior Learning (옵트인)

> 활성화: `/nova:evolve --from-observations`

사용자의 실제 행동 패턴에서 CPS Problem 초안을 제안한다. 외부 스캔(WebSearch) 없이 내부 관찰 데이터만 사용한다.

### 파이프라인

```
[1] analyze-observations.sh 호출
      ↓
[2] Top N 반복 패턴 추출 (--pattern 선택)
      ↓
[3] 패턴 → CPS Problem 초안 드래프트
      ↓
[4] 사용자 승인 요청 (자동 승격 금지)
      ↓
[5] 승인된 경우만 → Phase 3 Proposal 진입
```

### 실행 방법

```bash
# 도구 호출 빈도 분석 (기본)
bash scripts/analyze-observations.sh --top 10 --pattern tool-frequency

# 시퀀스 패턴 분석
bash scripts/analyze-observations.sh --top 5 --pattern sequence

# 반복 실패 패턴 분석
bash scripts/analyze-observations.sh --top 10 --pattern failures
```

### 자율 승격 금지 원칙

- analyze-observations.sh 결과는 **제안 재료**에 불과하다
- Nova 철학 "AI는 제안, 인간은 결정" — 사용자 명시적 승인 없이 어떤 규칙도 자동 추가하지 않는다
- 승인 전 CPS Problem 초안은 `docs/proposals/YYYY-MM-DD-from-observations.md`에 저장하고 대기한다

## Schedule 연동

`/schedule`로 cron 등록하여 자동 실행할 수 있다:

```
/schedule "Nova Self-Evolution 스캔" --cron "0 21 * * 1,3,5" --command "/nova:evolve --auto"
```

> 위 예시: 매주 월/수/금 06:00 KST (UTC 21:00)에 자동 스캔 + 자율 범위 적용
