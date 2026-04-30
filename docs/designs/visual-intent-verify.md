---
title: Visual Intent Verify (G1+G3 페어 게이트)
sprint: A2 (Design)
created: 2026-04-29
related:
  - docs/plans/visual-intent-verify.md
  - docs/guides/ui-quality-gate.md
  - scripts/capture-visual-intent.sh
  - scripts/visual-self-verify.sh
  - scripts/detect-ui-change.sh
---
# Visual Intent Verify (G1+G3 페어 게이트)
본 문서는 Sprint A2 기준의 구현 정본이다.
추측성 확장 없이 현재 코드 동작을 계약으로 명시한다.
---
## 1) Context
### 1.1 왜 이 게이트가 필요한가
Nova의 기본 검증은 코드/구조 중심이다.
UI는 "시각 의도"와 "실제 결과"의 불일치가 핵심 리스크인데,
텍스트 검증만으로는 이 불일치를 충분히 차단하기 어렵다.
G1은 시각 의도를 캡처한다.
G3는 구현 결과를 의도와 대조한다.
둘을 페어로 묶어야 완료 선언의 신뢰도가 올라간다.
근거:
- `scripts/capture-visual-intent.sh:2-4`
- `scripts/visual-self-verify.sh:2-11`
- `docs/guides/ui-quality-gate.md:12-14`
### 1.2 Sprint 분할 맥락
이 설계는 A2(verify) 스프린트 문서다.
전체 흐름은 A1/A2/A3로 분할되어 있다.
| Sprint | 핵심 | 결과 |
|---|---|---|
| A1 | G1 capture | intent.json v1.0 freeze |
| A2 | G3 verify | ready_for_judge + 폴백 체인 |
| A3 | 통합 가드 | 회귀 테스트/세션 동기화 |
근거:
- `docs/research/2026-04-29-ui-ux-gap-rescan.md:140-149`
- `tests/test-scripts.sh:1047-1074`
---
## 2) Problem
### 2.1 시각 검증 공백
UI 구현은 코드 정합성과 별개로 시각 의도 회귀가 발생한다.
예: 어휘 미준수, 밀도/위계 불일치, 토큰 일관성 이탈.
### 2.2 사용자 환경 편차
사용자마다 Playwright MCP 설치 여부가 다르다.
API 키 제공 여부도 다르다.
게이트가 특정 환경에서만 동작하면 범용성 목표를 깨뜨린다.
### 2.3 비용 상승
동일 UI 변경을 매번 재평가하면 비용이 누적된다.
캐시 기반 재검증 생략이 필요하다.
---
## 3) Solution — 폴백 체인 4단계
핵심 원칙:
- 가능한 한 자동 캡처를 우선한다.
- 불가능하면 사용자 제공으로 폴백한다.
- 스크린샷이 끝내 없으면 code-only로 진행하되 차단은 하지 않는다.
### 3.1 단계 정의
| 단계 | 키워드 | 진입 조건 | 결과 |
|---|---|---|---|
| 1 | `playwright-mcp` | auto 모드 + MCP 감지 | 자동 스크린샷 우선 |
| 2 | `user-manual` | interactive TTY + 사용자 경로 입력 | 수동 스크린샷 사용 |
| 3 | `code-only-fallback` | 스크린샷 미확보 | 코드 기반 분석 |
| 4 | degraded 보고 | 3단계 결과 | 차단 X, 사용자 안내 |
테스트 키워드:
- `playwright-mcp`
- `user-manual`
- `code-only-fallback`
코드 근거:
- 1단계: `visual-self-verify.sh:213-221`
- 2단계: `visual-self-verify.sh:224-248`
- 3단계: `visual-self-verify.sh:250-254`
- degraded 정책: `visual-self-verify.sh:280-285`
### 3.2 `provided` source 호환
스크립트는 `--screenshots` 입력 시 `provided`를 반환할 수 있다.
근거: `visual-self-verify.sh:202-210`.
운영 해석:
- `provided`는 사용자 제공 스크린샷 계열.
- 의미상 `user-manual`과 동치 그룹으로 취급한다.
- 핵심 폴백 체인 키워드는 `playwright-mcp | user-manual | code-only-fallback`.
### 3.3 Computer Use 제외
v1 범위에서는 Computer Use를 기본 체인에 넣지 않는다.
이유:
- 설치/세션 복잡도 증가.
- "모든 사용자 보장" 원칙 약화.
- 현재 가이드/스크립트의 기본 경로는 Playwright + 수동 + 코드 폴백.
참조:
- `docs/guides/ui-quality-gate.md:16-19`
- `docs/guides/ui-quality-gate.md:205-206`
---
## 4) Data Contract — intent.json v1.0
### 4.1 생성 위치
intent.json은 G1에서 freeze한다.
- quick/non-interactive: `capture-visual-intent.sh:176-238`, `249-262`
- interactive: `capture-visual-intent.sh:326-370`, `372-376`
### 4.2 필수 스키마 필드
| 필드 | 타입 | 설명 |
|---|---|---|
| `$schema` | string | JSON Schema URI |
| `version` | string | `"1.0"` 고정 |
| `meta` | object | slug/created_at/captured_by/plan_path |
| `vocabulary` | object | primary/fallback/raw_user_phrase |
| `scope` | object | included/excluded/scope_type 등 |
| `design_system` | object | mode/source/detected_tokens/user_decision |
| `references` | object | figma/screenshot/natural_language/wireframe/inspiration |
| `success_criteria` | array | 성공 조건 |
| `visual_checks` | array | 시각 검증 항목 |
실제 필드 구성 근거:
- `capture-visual-intent.sh:201-238`
- `capture-visual-intent.sh:339-370`
### 4.3 의미 규칙
1. `version`은 반드시 `"1.0"`이다.
2. `vocabulary.raw_user_phrase`는 사용자 원문 보존 필드다.
3. `captured_by`는 `quick | non-interactive | user` 중 하나다.
4. `scope.user_explicit`는 interactive 경로에서 `true`다.
G3의 최소 유효성 검증:
- `.version == "1.0" and .meta.slug and .vocabulary.primary`
- 근거: `visual-self-verify.sh:147-151`
### 4.4 스키마 예시 (축약)
```json
{
  "version": "1.0",
  "meta": {
    "slug": "profile-page",
    "captured_by": "user",
    "plan_path": "docs/plans/profile-page.md"
  },
  "vocabulary": {
    "primary": "shadcn",
    "raw_user_phrase": "최신 트렌드 느낌"
  },
  "scope": {
    "scope_type": "screen",
    "included": []
  },
  "design_system": {
    "mode": "use-existing"
  },
  "references": {
    "screenshot_paths": []
  },
  "success_criteria": [],
  "visual_checks": []
}
```
---
## 5) Output Contract — ready_for_judge JSON
`visual-self-verify.sh`의 표준 출력은 ready_for_judge JSON이다.
run/check/orchestrator는 이 결과를 Agent judge 입력으로 사용한다.
코드 근거:
- stdout: `visual-self-verify.sh:322-333`
- 파일 출력: `visual-self-verify.sh:346-357`
### 5.1 필드 정의
| 필드 | 타입 | 설명 |
|---|---|---|
| `ready_for_judge` | bool | judge 호출 준비 여부 |
| `intent_path` | string | intent.json 경로 |
| `screenshot_paths` | array | 캡처/제공 이미지 경로 |
| `screenshot_source` | enum | 캡처 출처 |
| `fallback_level` | number | 폴백 단계 |
| `evaluator_prompt` | string | judge 지시문 |
| `cache_hit` | bool | 캐시 적중 |
| `hash` | string | UI 변경 hash |
| `skipped` | bool | 스킵 여부 |
| `agent_model_hint` | enum | `default | opus` |
### 5.2 screenshot_source enum
실행 호환 값:
- `playwright-mcp`
- `provided`
- `user-manual`
- `code-only-fallback`
정책:
- `provided`는 사용자 제공 계열로 분류한다.
- 운영 체인 설명에서는 `user-manual` 계열로 묶어도 무방하다.
### 5.3 evaluator prompt 정책 포함 내용
prompt에는 반드시 아래가 들어간다.
- intent JSON 원문
- screenshot/code 분석 모드
- `raw_user_phrase` 인용
- verdict 기준 (critical/high/medium/degraded)
근거:
- `visual-self-verify.sh:260-301`
---
## 6) API 키 의존성 0
### 6.1 원칙
**API 키 의존성 0 — 모든 사용자 보장**
Anthropic API 키는 **NOT REQUIRED**.
키가 없어도 게이트는 동작해야 한다.
### 6.2 왜 키가 불필요한가
1. 스크립트는 외부 API를 직접 호출하지 않는다.
2. 평가는 Agent subagent로 위임된다.
3. Agent는 사용자 Claude Code 세션 모델을 사용한다.
코드/문서 근거:
- `visual-self-verify.sh:9-11`
- `visual-self-verify.sh:79-80`
- `run.md:254-255`, `run.md:276-282`
- `check.md:142`
정책 문구:
- `키 의존성 0`
- `키 불필요`
- `NOT REQUIRED`
---
## 7) Cache Strategy
### 7.1 hash 소스
G3는 `detect-ui-change.sh --post-impl`의 hash를 재사용한다.
근거:
- `visual-self-verify.sh:160-163`
- `detect-ui-change.sh:163-178`
### 7.2 캐시 hit 조건
1. `.nova/last-visual-audit.json` 존재
2. 현재 hash == 이전 hash
3. 이전 verdict == `pass`
조건 만족 시:
- `cache_hit:true`
- `ready_for_judge:false`
- `skip_reason:"cache hit (same change previously verified PASS)"`
근거:
- `visual-self-verify.sh:163-180`
### 7.3 저장 위치
- `.nova/last-visual-audit.json`
동일 변경 재검증을 줄여 사용자/시스템 비용을 절약한다.
---
## 8) Verdict 정책
판정 규칙은 evaluator prompt에 고정되어 있다.
근거: `visual-self-verify.sh:280-285`.
| 조건 | verdict | 차단 |
|---|---|---|
| critical mismatch 1+ | fail | 차단 |
| high mismatch 2+ | fail | 차단 |
| medium만 | pass (warning) | 통과 |
| code-only-fallback | degraded | 차단 X |
degraded는 실패가 아니라 "검증 신뢰도 저하 보고"다.
---
## 9) Sprint A2 산출물
A2 산출은 다음 4개 축으로 정의한다.
1. G3 정보 수집기:
- `scripts/visual-self-verify.sh`
2. 실행 커맨드 통합:
- `.claude/commands/run.md` Phase 5.5b (`224-289`)
- `.claude/commands/check.md` Phase 3.5 (`125-143`)
3. 오케스트레이터 통합:
- `.claude/skills/orchestrator/SKILL.md` Phase 5.5a/5.5b (`414-507`)
4. 회귀 검증 기준:
- `tests/test-scripts.sh` A2 통합 검증 (`1047-1074`)
---
## 10) 구현체 매핑
| 설계 항목 | 구현 위치 | 라인 근거 |
|---|---|---|
| intent 스키마 freeze | `scripts/capture-visual-intent.sh` | `188-238`, `326-370` |
| v1.0 검증 | `scripts/visual-self-verify.sh` | `147-151` |
| 폴백 체인 | `scripts/visual-self-verify.sh` | `202-254` |
| prompt 기반 판정 규칙 | `scripts/visual-self-verify.sh` | `280-285` |
| ready_for_judge 출력 | `scripts/visual-self-verify.sh` | `322-333` |
| cache hash 재사용 | `scripts/visual-self-verify.sh`, `scripts/detect-ui-change.sh` | `155-185`, `163-178` |
| run/check/orchestrator 호출 | `.claude/commands/*.md`, `orchestrator/SKILL.md` | 위 표 참조 |
이 매핑을 A2 정합성 검증의 기준으로 사용한다.
