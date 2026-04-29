# Adversarial Gap Analysis: Nova vs everything-claude-code (2026-04-29)

> 분석 일시: 2026-04-29T11:30:00+09:00
> 대상: [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) (이하 ECC)
> 메서드: 5기둥별 적대적 평가 — Nova가 ECC 대비 **명백히 부족한** 영역만 갭으로 인정. ECC 흡수가 Nova 정체성을 훼손하면 채택 제외.
> 근거: 실증(GitHub API + raw fetch + repo dirs) + 사용자 LiveWiki 요약 + 메모리 `project_nova_competitive_analysis_2026_04_23.md` (5일 전, 일부 갱신)

---

## Executive Summary

**ECC 실측 (2026-04-29):** 169K stars (5일에 +5K), 48 agents, 183 skills, 79 commands, 14 MCP servers, 997+ tests, 102 보안 룰, 6개 하네스 어댑터(.codex/.cursor/.gemini/.opencode/.trae/.kiro) + AGENTS.md 단일 파일.

**Nova 실측 (2026-04-29, v5.19.5 HEAD):** ~7 agents, ~15 skills, ~12 commands, 491 tests, Claude Code 단독.

**적대적 평가 결과:** Nova가 ECC 대비 **명백한 갭** 9건. P0 3건은 Nova 5기둥 응집형 정체성과 충돌하지 않으면서 즉시 흡수 가능. P1 3건은 보안/관측성 보강. P2 3건은 정체성 결정이 필요한 영역.

**핵심 인사이트:** ECC는 **카탈로그형 만능팩**, Nova는 **방법론 응집형**. 따라서 "183 skills 차용" 같은 양적 추격은 정체성 훼손 — 채택 제외. 대신 ECC가 발견한 **메커니즘** (컨텍스트 로스트 진단 카탈로그, instinct 신뢰도 점수, AgentShield 자기 보안 진단)을 Nova 5기둥 안에서 재해석한다.

---

## 5기둥 매핑표

| 기둥 | ECC 강점 | Nova 현황 | Gap 등급 |
|------|----------|-----------|----------|
| 환경 (Environment) | 6 하네스 어댑터, AGENTS.md 단일, MCP 정량 룰 (10 server / 80 tool), 비용 settings 가이드 | Claude Code 단일, worktree-setup, MCP 룰 없음, 비용 가이드 없음 | **P0** (비용·MCP), P2 (cross-harness) |
| 맥락 (Context) | Strategic Compact 스킬, /clear vs /compact 명시 가이드, autocompact 50% override, **컨텍스트 로스트 4원인 진단 모델** | NOVA-STATE 50줄 룰, context-chain 스킬, PreCompact 검토 중 | **P0** (전부) |
| 품질 (Quality) | 102 보안 룰 + AgentShield 적대적 (red/blue/auditor) 자기 진단, 997 tests, 1282 security tests | 491 tests, evaluator + jury + ux-audit, 자기 보안 진단 부재 | **P1** (자기 보안 진단) |
| 협업 (Collaboration) | 48 agents + 183 skills + 79 commands 카탈로그형 | ~7/15/12 응집형 | **— 정체성 결정** (양적 추격 X) |
| 진화 (Evolution) | Continuous Learning V2: instinct + confidence (0.3~0.9) + /evolve 자동 승격 + export/import | /nova:evolve 외부 스캔 + --from-observations + analyze-observations.sh | **P1** (신뢰도 점수), P2 (export/import) |

---

## P0 Gaps (즉시 채택 권장 — 정체성 충돌 없음)

### P0-1. 컨텍스트 로스트 4원인 진단 카탈로그

> 출처: 사용자 LiveWiki 요약 (영상 02:12 기준) + ECC Strategic Compact 스킬 존재
> 영향: docs/nova-rules.md §2 (검증·하드 게이트) 근처에 신규 §2.5 또는 별도 docs/context-rot-diagnosis.md
> 자율 등급: Full Auto (patch~minor)

**발견.** ECC는 "컨텍스트 로스트(=Claude가 점진적으로 멍청해짐)" 를 4가지 구조적 원인으로 분류한다:

1. **어텐션 희석 (Attention Dilution)** — 긴 컨텍스트에서 정보 상실
2. **명령 충돌 (Instruction Conflict)** — 지시문 모순
3. **토큰 예산 압박 (Token Budget Pressure)** — 시작부터 토큰 잠식
4. **관련성 미스매치 (Relevance Mismatch)** — 불필요한 파일 로드

권장 임계값: 단일 파일 2K~3K 토큰 초과 시 점검 신호.

**Nova 갭.** Nova는 NOVA-STATE 50줄 룰 + context-chain SKILL로 **STATE 방어**는 한다. 그러나 컨텍스트 로스트 자체에 대한 **진단 어휘가 없다**. 사용자가 "Claude가 멍청해진 것 같다"고 보고하면 Nova는 분류·대응 절차가 없다.

**Nova 적용 방안.** `docs/nova-rules.md` 또는 신규 `docs/context-rot-diagnosis.md`에 4원인 카탈로그 + 각 원인별 1차 대응 (Nova 자산 기준):

| 원인 | 진단 신호 | Nova 1차 대응 |
|------|-----------|----------------|
| 어텐션 희석 | 같은 지시 반복, 최근 변경 무시 | `/clear` + NOVA-STATE 압축 재로드 |
| 명령 충돌 | CLAUDE.md vs session-start vs 사용자 지시 모순 | `/nova:check` 정합성 검증 |
| 토큰 예산 압박 | 응답 갑자기 짧아짐, 계획 단계 생략 | session-start lean profile, MCP 비활성화 |
| 관련성 미스매치 | 부적절한 파일 인용, 잘못된 경로 | Explore 서브에이전트로 폭 분리 |

**비용.** 문서 1개 + nova-rules.md 1줄 추가. 회귀 가드 1개. patch 1건.

**리스크.** 진단 모델이 검증되지 않음 (LiveWiki 인용). 그러나 어휘 도입 자체가 가치이므로 P0 유지.

---

### P0-2. 비용 최적화 settings 가이드

> 출처: ECC `settings.json` 패턴 + 사용자 LiveWiki 요약 (영상 04:33~05:53)
> 영향: 신규 `docs/cost-optimization.md` + `docs/nova-rules.md` §5 환경안전 1줄
> 자율 등급: Full Auto (patch)

**발견.** ECC는 `settings.json` 3개 키로 **80% 누적 절감** 주장:

```json
{
  "model": "sonnet",
  "env": {
    "MAX_THINKING_TOKENS": "10000",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "50"
  }
}
```

사용자 요약은 추가로 `sub_agent_model: haiku` 도 제시 (실제 ECC settings.json에는 미확인 — 동영상 시점 차이 가능).

**Nova 갭.** Nova는 evaluator + jury + ux-audit + orchestrator 모두 **서브에이전트 다중 spawn**. 사용자가 Opus 4.7 default + 모든 서브에이전트도 Opus면 비용이 폭발적이다. Nova는 **모델 선택 가이드가 0줄**.

**Nova 적용 방안.** 신규 `docs/cost-optimization.md`:

1. **메인 vs 서브에이전트 분리.** 메인 = Opus 4.7 (의사결정), 서브에이전트 = Haiku 4.5 (검색/실행). evaluator는 Sonnet 4.6 (적대적 보수성).
2. **MAX_THINKING_TOKENS 가이드.** Nova 기본 10K 권장, 복잡도 8+에서만 31999.
3. **AUTOCOMPACT 가이드.** `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50`으로 자동 압축 임계 낮춤 (NOVA-STATE 50줄 룰과 정합).
4. **비용 추정 표.** Nova 풀사이클 (`/nova:auto` 1회) 기준 모델 조합별 예상 비용.

**비용.** 문서 1개. 수동 개입 없음.

**리스크.** "80% 절감"은 ECC 자체 측정. Nova 워크로드와 다를 수 있음 — Nova 추정치는 별도 표기.

---

### P0-3. Strategic Compact 스킬 + /clear vs /compact 가이드

> 출처: ECC Strategic Compact 스킬 + 사용자 LiveWiki 요약 (영상 05:57~06:24)
> 영향: 신규 `skills/nova:strategic-compact/SKILL.md` + `docs/nova-rules.md` §1 보강
> 자율 등급: Semi Auto (PR, minor)

**발견.** ECC는 두 명령어를 **다른 시점**에 사용하라고 명시한다:

- `/clear` — 무관한 작업 사이 컨텍스트 즉시 비움
- `/compact` — 마일스톤 사이 컨텍스트 요약 압축
- **구현 도중 `/compact` 금지** — Strategic Compact 스킬이 적절한 시점만 제안

**Nova 갭.** Nova는 NOVA-STATE 트림 룰만 가짐. Claude Code 자체의 `/clear` `/compact` 사용 시점은 **0줄**. 사용자가 잘못된 시점에 압축하면 Nova의 응집형 정체성이 한순간에 무너진다 (Plan 단계 중 압축 → CPS 컨텍스트 손실).

**Nova 적용 방안.** 신규 `skills/strategic-compact/SKILL.md` (Nova 어휘로):

```
MUST TRIGGER:
- /nova:plan / /nova:design 완료 직후 → /compact 권장 (마일스톤)
- 에이전트 spawn 직전 토큰 사용량 70% 초과 → /compact 또는 /clear
- 무관한 작업 전환 → /clear

MUST NOT TRIGGER:
- 구현 sprint 도중 (Generator 컨텍스트 살아있어야 함)
- Evaluator 검증 직전 (Adversarial = 같은 컨텍스트 재현 필요)
```

NOVA-STATE 자가 트림 룰과 결합 — STATE는 50줄 트림 + 세션 자체는 strategic compact.

**비용.** 스킬 1개 + nova-rules.md 1줄. 회귀 가드 키워드 1개. minor 1건.

**리스크.** ECC Strategic Compact 스킬 본문 미확보 (404). 사용자 요약 + 일반 패턴으로 추론. Spike 불필요 (Nova 자체 룰 도입).

---

## P1 Gaps (중기 채택)

### P1-1. AgentShield 영감 — Nova 자기 보안 진단

> 출처: ECC AgentShield (`npx ECC Agent Shield Scan`, 102 룰, 5 카테고리, --opus 3에이전트)
> 영향: 신규 `commands/nova:audit-self.md` + `agents/security-engineer.md` 활용
> 자율 등급: Semi Auto (PR, minor)

**발견.** AgentShield는 Claude Code 설정 자체의 보안 취약점을 검사:

- CLAUDE.md, settings.json, MCP 설정, hooks, agent definitions → 5 카테고리
- 102 정적 분석 룰
- `--opus` 플래그 시 Red Team / Blue Team / Auditor 3에이전트 적대적 검증

**Nova 갭.** Nova는 `agents/security-engineer.md`를 **사용자 코드**에 적용하는 데 쓴다. **Nova 자기 자신의** session-start.sh / hooks / agents / skills / settings 보안 진단은 0줄. v5.18.3 PreToolUse `if` 사건처럼 hooks 자체가 공격 표면이 될 수 있다.

**Nova 적용 방안.** 신규 `/nova:audit-self` 커맨드:

1. `security-engineer` 에이전트가 5 카테고리 스캔:
   - `.claude-plugin/plugin.json` 시크릿 노출
   - `hooks/*.sh` injection 취약점
   - `agents/*.md` tools 권한 과다
   - `skills/*/SKILL.md` 외부 호출 의도 충돌
   - `commands/*.md` Bash 권한
2. evaluator 적대적 검증 (보수적 보고)
3. (옵션) `--jury` 플래그로 다관점 (Red/Blue/Auditor)

**비용.** 커맨드 1개 + 자체 보안 룰셋 (~30~50개로 시작). 회귀 가드.

**리스크.** Nova 응집형 정체성과 정합 — 5기둥 중 품질의 자기 적용. 채택 권장.

---

### P1-2. MCP 정량 가이드 (10 / 80 룰)

> 출처: ECC 가이드 + 사용자 LiveWiki 요약 (영상 06:37~06:57)
> 영향: `docs/nova-rules.md` §5 환경안전에 1줄
> 자율 등급: Full Auto (patch)

**발견.** "프로젝트당 MCP 10개 미만, active tools 80개 미만 — 200K 컨텍스트 창이 70K 이하로 줄지 않게."

**Nova 갭.** Nova는 MCP 정량 룰 0줄. 본 세션도 MCP 도구가 ~80+개 표시됨 — ECC 룰에 따르면 이미 임계.

**Nova 적용 방안.** `docs/nova-rules.md` §5에 1줄 추가:

> "MCP 서버 ≤10개, 활성 도구 ≤80개 권장. 초과 시 컨텍스트 압박 (출처: ECC 측정)."

session-start.sh가 본 세션 MCP 카운트 출력 (선택, lean 프로파일 제외).

**비용.** 1줄 + (선택) hook 1줄. patch 1건.

**리스크.** 룰만 도입. 강제 게이트는 별도 결정.

---

### P1-3. Instinct 신뢰도 점수 (0.3~0.9)

> 출처: ECC Continuous Learning V2 + 사용자 LiveWiki 요약 (영상 07:31~07:45)
> 영향: `scripts/analyze-observations.sh` + `.nova/events.jsonl` 스키마 확장
> 자율 등급: Semi Auto (PR, minor)

**발견.** ECC는 도구 호출 전후 100% 관측 → instinct 단위 학습 → **0.3~0.9 신뢰도 점수** → 3개 이상 모이면 `/evolve`로 skill 자동 승격.

**Nova 갭.** Nova는 메모리 분석에서 이미 P0로 인정 (메모리 `project_nova_competitive_analysis_2026_04_23.md` §3). `/nova:evolve --from-observations`은 있지만 신뢰도 점수 없음 — 모든 패턴이 동등 가중.

**Nova 적용 방안.**

1. `.nova/events.jsonl` 스키마에 `confidence: 0.0~1.0` 추가 — 패턴 발생 빈도 + 사용자 명시적 채택률 함수.
2. `analyze-observations.sh` 출력에 신뢰도 정렬 + 0.7 미만 자동 제외.
3. `/nova:evolve --from-observations` 가 신뢰도 표시.
4. **자동 승격 금지 원칙 유지** — 신뢰도 0.9여도 사용자 승인 (메모리 "Adaptive 기둥 — 자동 승격 금지" 원칙).

**비용.** 스키마 + 스크립트 1개 + 회귀 가드. minor 1건.

**리스크.** 신뢰도 산출 공식이 자의적. 초기엔 빈도 기반 단순 공식 → 사용 경험으로 보정.

---

## P2 Gaps (정체성 결정 필요)

### P2-1. Cross-harness AGENTS.md 어댑터

> 출처: ECC AGENTS.md + 6 어댑터 디렉토리 + 사용자 LiveWiki 요약 (영상 04:19)
> 영향: 신규 어댑터 디렉토리 (Tier 4 deferred 상태)
> 자율 등급: Manual (제안만)

**현황.** NOVA-STATE Known Risks/Gaps에 "Tier 4 — Cross-harness — Claude Code 안정화까지 보류" 명시. 메모리에서도 "Nova 정체성 결정"으로 분류.

**판단 권장.** 보류 유지. ECC는 카탈로그형이므로 6 하네스 흡수가 자연스럽지만 Nova는 Claude Code 응집형 — Cross-harness 진출 시 5기둥 일관성 유지가 어렵다. 단, 사용자가 cursor/codex 환경 사용 시작하면 재평가.

---

### P2-2. Instinct export/import (회사 컨벤션 공유)

> 출처: ECC `/instinct-export` `/instinct-import`
> 영향: 신규 커맨드 2개 + .nova/instincts.yml 포맷 정의
> 자율 등급: Manual (P1-3 채택 후 결정)

**판단 권장.** P1-3 (신뢰도 점수) 채택 후 6개월 운영하며 공유 수요 검증 후 결정.

---

### P2-3. Red/Blue/Auditor 3에이전트 적대적 검증

> 출처: AgentShield --opus 모드
> 영향: P1-1 채택 시 `--jury` 플래그로 자연 통합
> 자율 등급: P1-1에 흡수 (별도 항목 아님)

---

## 채택 제외 (Nova 정체성 보호)

| 항목 | 사유 |
|------|------|
| 183 스킬 양적 추격 | Nova 응집형 정체성 훼손. 메서드론 압축 > 카탈로그 확장 |
| 79 commands 양적 추격 | 동일 |
| `/evolve` **자동** 승격 | "사용자 승인 필수" 메모리 원칙. P1-3에서 신뢰도 점수만 차용, 자동 승격 X |
| Continuous Learning V2 PreToolUse 100% 관측 | Nova 관측성 갭은 인정 (메모리 `project_nova_harness_gaps_analysis_2026_04_19`)하나 100% 관측은 비용·프라이버시 문제. P3 (PostToolUse `duration_ms`) + P1-3로 대체 |
| ECC 동영상 마케팅 패턴 (10M 트윗 뷰) | Nova는 방법론. 마케팅 추격 X |

---

## Nova 우위 (적대적 평가에서도 살아남는 것)

ECC가 흡수할 수 없는 Nova 자산:

1. **CPS Context-Problem-Solution** Plan/Design 게이트 — ECC는 `/plan`만 있고 CPS 프레임워크 없음
2. **NOVA-STATE 50줄 자가 트림 + 9 진입점 동기화** (v5.19.6) — ECC는 STATE 단일 진입
3. **Evaluator 독립 서브에이전트 (창 분리) + 메인 컨텍스트 사실 검증 1회 후 보고** — ECC는 인라인
4. **5기둥 응집형 — 메서드론 자체가 가치** — ECC는 만능팩
5. **release.sh 통합 체인 + version bump 자동화** — ECC는 수동
6. **multi-AI `/nova:ask` (Claude+GPT+Gemini)** + jury 다관점 — ECC는 단일 AI
7. **Hard Gate 차단 메커니즘** (v5.18.3 PreToolUse exit 2) — ECC는 권고형

---

## 채택 추천 우선순위

| 우선 | 제안 | 분류 | Spike | 비용 |
|------|------|------|-------|------|
| 1 | P0-1 컨텍스트 로스트 진단 카탈로그 | patch | 불필요 | 1 doc + 1줄 |
| 2 | P0-2 비용 최적화 settings 가이드 | patch | 불필요 | 1 doc |
| 3 | P0-3 Strategic Compact 스킬 | minor | 불필요 | 1 skill + 1줄 |
| 4 | P1-2 MCP 10/80 룰 | patch | 불필요 | 1줄 |
| 5 | P1-1 Nova 자기 보안 진단 (`/nova:audit-self`) | minor | 룰셋 정의 | 1 cmd + ~50 룰 |
| 6 | P1-3 Instinct 신뢰도 점수 | minor | 산출 공식 | 1 script + 회귀 |
| 7~9 | P2 (cross-harness, export/import, 3에이전트) | major | 정체성 결정 | 보류 |

---

## 다음 행동 권장

이 보고서가 다루는 작업은 복잡도 8+ (Nova 자가 규칙 §1 — Plan→Design→스프린트). 단일 evolve scan으로 끝나지 않는다.

**권장 절차:**

1. 사용자가 본 보고서에서 **채택할 P0/P1 항목 선택** (1~6번 중)
2. 선택된 항목에 대해 `/nova:deepplan` (4단 파이프라인)으로 Plan 작성
3. 스프린트 분해 → release.sh patch~minor 분할 릴리스
4. 메모리 업데이트: `project_nova_competitive_analysis_2026_04_23.md` 를 본 보고서로 supersede

**P2 (Cross-harness, instinct export/import)는 보류 유지** — 메모리 원칙 (Tier 4 정체성 결정).

## Refs

- [ECC repository](https://github.com/affaan-m/everything-claude-code) — 169K stars, 48/183/79/14, 997+ tests
- [ECC AGENTS.md](https://github.com/affaan-m/everything-claude-code/blob/main/AGENTS.md) — 6 하네스 어댑터 단일 파일
- 사용자 제공 LiveWiki 요약 — heajames.com/팁스 PDF 가이드 출처
- Nova 메모리: `project_nova_competitive_analysis_2026_04_23.md` (5일 전, 본 보고서로 supersede 후보)
- Nova 메모리: `project_nova_harness_gaps_analysis_2026_04_19.md` (관측성 갭 — P1-3 연계)
- Nova 메모리: `project_nova_spike_skill_deferred_2026_04_21.md` (Pre-Plan 스파이크 보류 — 본 P0/P1 일부 적용 시 재고려)
- 본 보고서와 함께 생성된 evolve 스캔: `docs/proposals/2026-04-29-evolve-scan.md`
