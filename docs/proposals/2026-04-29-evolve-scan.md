# Evolution Scan Report (2026-04-29)

> 스캔 일시: 2026-04-29T10:00:00+09:00
> 소스: Anthropic 공식 (changelog), Claude Code 생태계, 하네스 도구, AI 엔지니어링 (arxiv/asdlc.io)
> 이전 스캔: 2026-04-23 (P1 marketplace validate 적용·M1/M2 보류), 2026-04-17 (Opus 4.7 반영)
> 발견: 약 18건 → 관련: 5건 (필터율: 72%)

---

## Scan Summary

| # | 항목 | 수준 | 자율 등급 | 출처 |
|---|------|------|----------|------|
| P1 | Evaluator 슬로건 — "false positive over false negative" 명문화 | patch | Full Auto | [asdlc.io Adversarial Code Review](https://asdlc.io/patterns/adversarial-code-review/) |
| P2 | `claude plugin prune` 사용자 안내 (README + nova-rules.md FAQ) | patch | Full Auto | [Claude Code v2.1.121](https://code.claude.com/docs/en/changelog) |
| P3 | PostToolUse `duration_ms` JSONL 관측성 통합 | patch | Full Auto | [Claude Code v2.1.119](https://code.claude.com/docs/en/changelog) |
| M1 | Evaluator 스킬에 "Self-Generated Test Cases" 패턴 추가 | minor | Semi Auto (PR) | [ReVeal arxiv 2506.11442](https://arxiv.org/html/2506.11442v1) |
| M2 | 새 Claude Code 훅 이벤트 활용 — PreCompact / CwdChanged / FileChanged | minor | Semi Auto (PR) — **Spike 우선** | [Claude Code v2.1.83 / v2.1.105](https://code.claude.com/docs/en/changelog) |

채택 보류: Cursor Composer 2 sub-agent 코디네이션, `type:"mcp_tool"` 훅 (M1 2026-04-23 보류 유지), 멀티에이전트 동시 출시 트렌드 — Nova 관점 신규성 부족하거나 이전 스캔에서 결론 남.

---

## patch (3건)

### P1. Evaluator 슬로건 — "false positive over false negative" 명문화

> 출처: [Adversarial Code Review pattern (asdlc.io)](https://asdlc.io/patterns/adversarial-code-review/)
> 수준: patch
> 자율 등급: Full Auto

#### 발견

asdlc.io Adversarial Code Review 패턴이 Critic Agent 행동 원칙을 한 줄로 압축한다:

> "Your job is to reject code that violates the Spec, even if it 'works.' Favor false positives over false negatives."

Builder/Generator 자가 검토는 "동일 컨텍스트 안에서 hallucinate correctness, double down on errors"하므로 Critic은 **별도 세션** 에서 실행하고, 의심스러우면 **PASS를 보류** 한다는 비대칭 보수성을 강제한다.

Nova 의 Evaluator 스킬(`skills/evaluator/SKILL.md`)은 이미 독립 서브에이전트로 분리되어 있고, "공식 문서 ≠ 실제 런타임", "Evaluator도 환각함" 메모리로 유사한 원칙을 운영 중이다. 그러나 **슬로건 형태로 명문화되어 있지 않아** Evaluator가 ambiguous 케이스에서 PASS로 흘러가는 사고가 반복(v5.18.3 부분 실기, 4회 릴리스 전 Evaluator 0회)된다.

#### Nova 적용 방안

`skills/evaluator/SKILL.md` 상단 Role 절에 한 줄 슬로건 추가:

```
> Job: Spec 위반을 거부하는 것. 'works'여도 거부. 의심스러우면 PASS 보류.
> Favor false positives over false negatives.
```

추가로 verdict 섹션에 `CONDITIONAL` 가이드 명문화:
- 증거 부족 → `CONDITIONAL` (PASS 아님)
- 외부 시스템 동작 미확인 → `CONDITIONAL` + Spike 권장
- "메인 컨텍스트 사실 검증 1회 후 사용자 보고" 메모리 원칙 SKILL에 인라인

#### 영향 범위

- `skills/evaluator/SKILL.md` (1파일)
- `tests/test-scripts.sh` 슬로건 키워드 회귀 가드 1줄 추가

#### 리스크

- 매우 낮음. 문구 추가만, 행동 변화는 운영자 해석 의존.
- 회귀 가드가 슬로건 한국어/영어 혼용을 잡지 못할 수 있음 → 한국어 키워드 1개 + 영어 키워드 1개 둘 다 assert.

---

### P2. `claude plugin prune` 사용자 안내

> 출처: [Claude Code v2.1.121 changelog](https://code.claude.com/docs/en/changelog)
> 수준: patch
> 자율 등급: Full Auto

#### 발견

Claude Code v2.1.121 에서 `claude plugin prune` 추가. orphaned auto-installed plugin dependencies 제거. `plugin uninstall --prune`은 cascade 제거.

#### Nova 적용 방안

Nova 사용자가 플러그인 업데이트/제거 시 의존성 누적을 정리할 수 있도록 단순 안내:

- `README.md` / `README.ko.md` Troubleshooting 절 또는 FAQ 절 1줄 추가
- `docs/nova-rules.md` 환경 안전(§5) 절에 "주기적 `claude plugin prune` 권장" 1줄

#### 영향 범위

- `README.md`, `README.ko.md`, `docs/nova-rules.md` (3파일, 각 1~2줄)

#### 리스크

- Claude Code 버전 의존성. 사용자 환경 v2.1.121 미만이면 명령 없음 → "Claude Code v2.1.121+" 단서 명기.
- 실제 동작 미실측. 단순 안내이므로 Nova 행동 변화 없음 — Spike 불필요.

---

### P3. PostToolUse `duration_ms` JSONL 관측성 통합

> 출처: [Claude Code v2.1.119 changelog](https://code.claude.com/docs/en/changelog)
> 수준: patch
> 자율 등급: Full Auto — **단, hook 실측 통과 후**

#### 발견

v2.1.119에서 PostToolUse / PostToolUseFailure 훅 입력에 `duration_ms` 필드 추가. 도구 실행 시간(권한 프롬프트, PreToolUse 훅 제외) 측정.

[memory: 하네스 엔지니어링 갭 분석](#) 에서 식별된 **관측성 갭** (JSONL append-only) 일부를 채울 수 있다. `.nova/events.jsonl`에 `duration_ms`를 기록하면 도구별 시간 통계, 슬로우 도구 식별, Evaluator 시간 가드(예: 30초 초과 시 경고) 가능.

#### Nova 적용 방안

`hooks/post-tool-use.sh` (없으면 신규) 또는 기존 PostToolUse 훅이 있으면 `duration_ms` 추출 후 `.nova/events.jsonl`에 1줄 append:

```jsonl
{"ts":"2026-04-29T10:00:00+09:00","event":"post_tool","tool":"Bash","duration_ms":1234}
```

`scripts/analyze-observations.sh` (`--from-observations` 모드)에 도구별 평균/p95 통계 1섹션 추가.

#### 영향 범위

- `hooks/post-tool-use.sh` (신규 또는 수정)
- `.claude-plugin/plugin.json` hooks 등록 (해당 시)
- `scripts/analyze-observations.sh` (있으면 수정, 없으면 신규)

#### 리스크 / 실측 필요

- **공식 문서 ≠ 실제 런타임 메모리 적용**. v5.18.3에서 PreToolUse `if` 필드 사건 학습. PostToolUse `duration_ms`도 stdin JSON 위치, 단위(ms vs us), session 재시작 후 등록 여부 등 실측 후 결정.
- Spike 절차: ① 가짜 PostToolUse 훅으로 stdin JSON 1회 기록 → ② 필드 존재/단위 확인 → ③ 본 제안 적용.
- JSONL 비대화 가능성. 기존 `.nova/events.jsonl` 회전 정책 확인 필요.

---

## minor (2건)

### M1. Evaluator 스킬에 "Self-Generated Test Cases" 패턴 추가

> 출처: [ReVeal: Self-Evolving Code Agents via Iterative Generation-Verification (arxiv 2506.11442)](https://arxiv.org/html/2506.11442v1)
> 수준: minor
> 자율 등급: Semi Auto (PR)

#### 발견

ReVeal은 Generator가 코드 생성 → **Verifier가 자체 테스트 케이스 구성 → 외부 도구(Python 인터프리터)로 검증** 을 인터리빙한다. 핵심 인사이트:

1. **Tool-Grounded Feedback** — 추상 평가보다 실행 가능한 검증이 풍부한 신호
2. **Self-Generated Test Cases** — 사전 테스트 슈트 의존 제거
3. **TA-PPO (Turn-Aware PPO)** — verification turn은 "골든 코드에서 통과하는 비율"로 보상 (생성기 보상 해킹 방지)

> "Verification turns receive rewards proportional to test case quality: the proportion of generated test cases that succeed when executed on the golden code."

Anthropic 자체 멀티에이전트 구조도 동일 방향 — Evaluator에 Playwright e2e 통합. ([startuphub.ai 인용](https://www.startuphub.ai/ai-news/artificial-intelligence/2026/anthropic-s-claude-masters-autonomous-coding))

#### Nova 적용 방안

Nova Evaluator 스킬은 현재 코드 변경 diff를 받아 적대적 리뷰만 수행. 여기에 "Self-Generated Test Cases" 절 추가:

- Evaluator가 변경 영역에 대해 **임시 검증 스크립트** 를 stdin/stdout 인터페이스로 즉석 생성 (예: bash 1줄, curl 헬스체크, grep -c assertion)
- 메인 코드베이스 또는 신뢰되는 골든 픽스처에서 실행 → 통과 확인 → 변경에 적용
- 통과 비율을 verdict 보강 근거로 기록

명시적 비목표:
- 단위 테스트 프레임워크 도입 X (Nova는 bash 기반 가드 위주)
- 강화학습 보상 구현 X (운영 패턴만 차용)

`skills/evaluator/SKILL.md` 에 "Self-Generated Test Cases (Optional)" 절 추가, 5~10줄 가이드 + 1 예시.

#### 영향 범위

- `skills/evaluator/SKILL.md` (1파일, 1섹션 추가)
- `commands/run.md`, `commands/check.md` 크로스 레퍼런스 1줄
- 회귀 가드 키워드 1개 추가

#### 리스크

- Evaluator가 "테스트 생성"에 시간을 과소비할 가능성. → Optional 절로 표시, "기존 픽스처 우선" 가이드.
- ReVeal은 RL 훈련 프레임워크. **운영 패턴만** 차용. RL/보상 도입은 별도 Plan 필요 (현재 보류).

---

### M2. 새 Claude Code 훅 이벤트 활용 — PreCompact / CwdChanged / FileChanged

> 출처: [Claude Code v2.1.83 (CwdChanged/FileChanged/TaskCreated)](https://code.claude.com/docs/en/changelog), [v2.1.105 (PreCompact 차단)](https://code.claude.com/docs/en/changelog)
> 수준: minor
> 자율 등급: Semi Auto (PR) — **Spike 우선**

#### 발견

v2.1.83 / v2.1.105 changelog가 4개 신규 훅 이벤트 추가:

| 훅 | 트리거 | Nova 활용 후보 |
|----|--------|----------------|
| `PreCompact` | 컨텍스트 자동 압축 직전. exit 2 또는 `{"decision":"block"}` 로 차단 가능 | NOVA-STATE.md 정리되지 않은 상태에서 압축 차단 |
| `CwdChanged` | 작업 디렉토리 변경 시 | worktree 진입 자동 감지 → worktree-setup 자동 트리거 |
| `FileChanged` | 파일 변경 시 (direnv 류 반응형 환경) | `.env` / `.nova/state.md` 변경 시 재로드 |
| `TaskCreated` | `TaskCreate` 호출 시 | orchestrator 통합 / `.nova/events.jsonl` 자동 기록 |

NOVA-STATE 갱신/정리 비대칭(v5.19.6에서 9 진입점 추가) 문제와 직접 연결 — `PreCompact` 가 "정리되지 않은 STATE 압축"을 사전 차단할 수 있는 **하드 게이트** 가 된다.

#### Nova 적용 방안

**Spike 1차** (별도 작업, 본 제안서 적용 전 필수):
1. 더미 훅 4개 등록 → 이벤트 트리거 시 stdin JSON 기록
2. 실제 페이로드, 차단 동작, 등록 후 재시작 필요 여부 확인 (v5.18.3 PreToolUse `if` 사건 동일 패턴)

**Spike 통과 후 적용**:
- `PreCompact`: NOVA-STATE.md 50줄 초과 시 차단 + 사용자에 트림 안내
- `CwdChanged`: worktree-setup 스킬 자동 호출
- `FileChanged`: `.env` 변경 시 NOVA-STATE Last Activity에 "환경 변경 감지" 1줄 추가
- `TaskCreated`: `.nova/events.jsonl`에 1줄 append

#### 영향 범위

- `hooks/pre-compact.sh`, `hooks/cwd-changed.sh`, `hooks/file-changed.sh`, `hooks/task-created.sh` (신규, 각 ~30줄)
- `.claude-plugin/plugin.json` hooks 등록
- `tests/test-scripts.sh` 훅 등록 회귀 가드
- `docs/nova-rules.md` §2 검증 + §5 환경안전 갱신

#### 리스크 / 실측 필수

- **메모리: "공식 문서 ≠ 실제 런타임" + "레퍼런스 먼저, 가설은 나중"** 두 원칙 모두 적용.
- v5.18.3 PreToolUse `if` 필드 사건 학습 — 새 훅 이벤트도 stdin JSON 구조, matcher 처리, 재시작 후 등록 여부 모두 실측 1회 필수.
- PreCompact 차단이 사용자의 정상적 압축 흐름을 방해할 위험 → 사용자 옵트인 (`.nova/config.yml` 플래그) 또는 50줄 임계값에서만 차단.
- CwdChanged 이벤트 빈도 과다 가능. 디바운스 또는 worktree-setup이 멱등인지 확인.

---

## major (0건)

이번 스캔에서는 호환성 깨지는 변경, 새 커맨드/스킬 추가, 아키텍처 전환에 해당하는 항목 없음.

---

## 채택 보류 (Out of Scope)

| 항목 | 사유 |
|------|------|
| Cursor Composer 2 sub-agent 코디네이션 모델 | Nova는 Claude Code 플러그인. Cursor 모델 직접 차용 불가, 패턴 차용은 ReVeal/Adversarial Code Review로 이미 흡수 |
| `type:"mcp_tool"` 훅 (Claude Code v2.1.118) | 2026-04-23 evolve M1에서 Semi Auto (PR) 보류. 후속 Spike 미실행. Nova 훅이 bash 기반이라 ROI 불명. |
| Anthropic Multi-Agent (Planner/Generator/Evaluator + Playwright) | Nova는 이미 Generator-Evaluator 분리. Playwright 통합은 ux-audit 별도 트랙. 신규성 없음. |
| 멀티에이전트 동시 출시 트렌드 (Feb 2026) | Nova orchestrator + agents/ 이미 존재. 시장 확인용 정보, 적용 액션 없음. |
| Cline / aider 기능 동향 | git-native CLI 워크플로 동향 — Nova는 plugin 형태로 유사 영역. 직접 차용 항목 없음. |

---

## 다음 행동

`--scan` 모드 종료. 사용자가 `/nova:evolve --apply` 또는 항목별 수동 채택 시:

- **P1, P2** (patch, 문서/문구만): release.sh로 일괄 patch 가능. 회귀 가드 추가 권장.
- **P3, M2** (hook 의존): Spike 1회 통과 후 진행 — v5.18.3 사건 학습.
- **M1** (Evaluator self-test): SKILL.md 1섹션 추가, PR로 진행.

NOVA-STATE.md Last Activity에 본 스캔 결과 기록 후 50줄 트림.

## Refs

- [Claude Code Changelog](https://code.claude.com/docs/en/changelog) — v2.1.83 / v2.1.105 / v2.1.117 / v2.1.118 / v2.1.119 / v2.1.121
- [ReVeal: Self-Evolving Code Agents (arxiv 2506.11442)](https://arxiv.org/html/2506.11442v1)
- [Adversarial Code Review pattern (asdlc.io)](https://asdlc.io/patterns/adversarial-code-review/)
- [Anthropic Multi-Agent (startuphub.ai)](https://www.startuphub.ai/ai-news/artificial-intelligence/2026/anthropic-s-claude-masters-autonomous-coding)
- 이전 Nova 스캔: `docs/proposals/2026-04-23-evolve-scan.md`, `2026-04-17-opus-4-7-evolution.md`
