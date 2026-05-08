# Evolution Scan: 2026-05-08

> 날짜: 2026-05-08
> 모드: --scan
> 출처: Anthropic 공식 changelog (CC v2.1.132~v2.1.133), Anthropic engineering 블로그

## Context

지난 스캔(2026-05-07)에서 v2.1.132까지 정리됐다. 그 후 v2.1.133이 새로 릴리스됐고, Anthropic이 발행한 Agent Skills/Context Engineering 가이드를 Nova 스킬 구조에 비춰 재검토했다. Nova 현재 상태(v5.30.1) 기준으로 흡수 가능한 항목을 정리한다.

> 본 스캔은 1차에서 Anthropic 공식에 편중됐다는 사용자 피드백 후 GitHub star 상위 awesome-list, Trail of Bits 보안 skills, Cursor/Cline/Aider 공식 베스트 프랙티스를 추가 스캔했다. **§4 외부 생태계 보강** 참조.

## 스캔 범위

| 소스 | 발견 | 관련 | 출처 |
|------|------|------|------|
| Anthropic 공식 changelog (v2.1.133) | 5건 | 2건 | https://code.claude.com/docs/en/changelog |
| Anthropic engineering 블로그 (Agent Skills, Context Engineering) | 2건 | 1건 | https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills |
| **awesome-claude-code / awesome-agent-skills (1000+ skills 카탈로그)** | 6건 | 1건 | https://github.com/VoltAgent/awesome-agent-skills |
| **Trail of Bits skills (17 보안 skills, 36k+ stars 생태계 인용)** | 4건 | 2건 | https://github.com/trailofbits/skills |
| **Cursor/Cline 공식 베스트 프랙티스** | 5건 | 1건 | https://cursor.com/blog/agent-best-practices |
| AI 엔지니어링 일반 | 2건 | 0건 | 일반 trend |

**관련성 필터**: Nova 4 Pillar(Structured/Consistent/X-Verification/Adaptive) 또는 commands/skills/agents/hooks/scripts 직접 영향 항목만 통과.

## Nova에 영향 없거나 이미 반영

| 변경 | Nova 상태 | 비고 |
|------|----------|------|
| `parentSettingsBehavior` admin-tier key (v2.1.133) | ⊘ 영향 없음 — Nova는 SDK managedSettings 미사용 | skip |
| Subagent skill discovery 버그 수정 (v2.1.133) | ⊘ 영향 없음 — Nova plugin skill은 정상 동작 중 (tests/test-scripts.sh 680/680) | acknowledge only |
| HTTP_PROXY/NO_PROXY MCP OAuth 수정 (v2.1.133) | ⊘ 영향 없음 — Nova 코드에 OAuth flow 없음 | skip |
| `Edit`/`Write` allow rule drive-root 매치 수정 (v2.1.133) | ⊘ 영향 없음 — Nova 권한은 plugin defaults 사용 | skip |
| `xhigh` effort level 자체 (v2.1.111) | ⏸ 2026-04-17 스캔에서 보류 — 별도 트랙 | 본 스캔은 effort 인지(observation)만 다룸 |

## 신규 관련 항목 (Nova에 흡수 가치 있음)

### [P-1] hooks 입력에 `effort.level` / `$CLAUDE_EFFORT` 캡처 — patch

#### 발견
- **CC v2.1.111 → v2.1.133**: hooks가 활성 effort level을 입력 JSON `effort.level` 필드와 `$CLAUDE_EFFORT` 환경변수로 받는다.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.133 entry)

#### Nova 적용 방안
`hooks/record-event.sh`가 PostToolUse·PreCompact 등에서 호출될 때 `$CLAUDE_EFFORT`를 옵셔널 nullable 필드로 jsonl payload에 추가. 분석(`scripts/analyze-observations.sh`)에서 effort 분포에 따른 패턴 신뢰도 가중치 검토 가능 (예: `xhigh`에서 reject가 잦으면 신뢰도 보정 약화).

- 변경 파일: `hooks/record-event.sh` 1곳, `docs/specs/events-schema.md`(있으면) 1곳
- 호환성: nullable 필드 추가 — 기존 분석 스크립트에 영향 없음

#### 영향 범위
- `hooks/record-event.sh` (env 캡처 1줄 추가)
- 회귀 가드: tests/test-scripts.sh — 신규 필드가 jq에서 `null` 허용 확인

#### 리스크
- effort 데이터가 사용자 작업 패턴 추론에 쓰일 경우 privacy 검토 필요. 현재 events.jsonl은 로컬 only이므로 낮음.

#### 자율 등급
**Full Auto** — 데이터 수집 추가만, 동작 로직 변경 없음.

---

### [P-2] `CLAUDE_CODE_SESSION_ID` 통합 — minor

#### 발견
- **CC v2.1.132**: Bash subprocess 환경에 `CLAUDE_CODE_SESSION_ID` 노출. hooks의 `session_id`와 동일 값.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.132 entry)

#### Nova 적용 방안
현재 `hooks/record-event.sh`는 `.nova/session.id`에 자체 hash 발급. CC가 노출하는 SESSION_ID를 우선 사용하면:
1. 같은 CC 세션에서 발생한 이벤트가 동일 ID로 묶여 멀티 세션 분석 정밀도 ↑.
2. CC transcript와 cross-reference 가능 (사용자가 추적 시).

구현 정책:
- `CLAUDE_CODE_SESSION_ID`가 있으면 그것을 우선, 없으면 기존 자체 발급 fallback (호환성 유지).
- `.nova/session.id` 파일은 fallback 경로로만 유지.

#### 영향 범위
- `hooks/record-event.sh` (Session ID 결정 블록 ~10줄 수정)
- 회귀 가드: tests/test-scripts.sh — env 미설정 시 기존 fallback 동작, env 설정 시 그 값 사용 두 케이스

#### 리스크
- CC SESSION_ID 길이/형식 변동 가능성 (현재 명시 형식 없음). 비어있거나 invalid 시 fallback 보장.

#### 자율 등급
**Semi Auto (PR)** — record-event.sh는 Sprint 1 핵심 인프라. 게이트 통과 후에도 사용자 리뷰 후 머지.

---

### [P-3] 장문 SKILL.md progressive disclosure 분리 검토 — minor

#### 발견
- **Anthropic Agent Skills 가이드 (2026)**: "When the `SKILL.md` file becomes unwieldy, split its content into separate files and reference them. If certain contexts are mutually exclusive or rarely used together, keeping the paths separate will reduce the token usage."
- 출처: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills

#### Nova 현재 상태
| Skill | 줄수 | 분리 후보 평가 |
|-------|------|-----------------|
| `orchestrator/SKILL.md` | 581 | ★★★ — task 매핑/agent 편성/폴백 절차/예시가 mutually exclusive 영역. references/templates 분리 가치 높음. |
| `deepplan/SKILL.md` | 465 | ★★ — Explorer/Synth/Critic/Refiner 4단 파이프라인 + 템플릿. 템플릿 부분 references/ 분리 가능. |
| `ux-audit/SKILL.md` | 417 | ★★ — 5인 평가자 페르소나 + WCAG 체크리스트. 페르소나 references/ 분리 가능. |
| `evaluator/SKILL.md` | 393 | ★ — 적대적 검증 핵심 절차. 분리 시 활성화 신호 약화 위험, 보류 권장. |
| 그 외 (jury 228, claude-md 321) | ≤330 | 현 수준 유지 |

#### Nova 적용 방안
가장 큰 `orchestrator/SKILL.md`(581줄)를 reference 패턴으로 분리하는 것을 우선 시도:
- `skills/orchestrator/SKILL.md` — 활성화 트리거 + 기본 워크플로우만 (목표 ≤300줄)
- `skills/orchestrator/references/templates.md` — 프롬프트 템플릿 묶음
- `skills/orchestrator/references/agent-mapping.md` — 복잡도 ↔ 에이전트 편성 규칙

deepplan/ux-audit는 orchestrator 결과 검증 후 후속 스프린트.

#### 영향 범위
- `skills/orchestrator/` 1개 디렉토리, 신규 파일 2개
- 회귀 가드: tests/test-scripts.sh — SKILL.md 본문에서 references/ 경로 명시 verify (grep), references/*.md 파일 존재 verify

#### 리스크
- **Skill 활성화 신뢰도 저하 가능성**: `description` frontmatter에서 트리거를 명확히 유지해야 함. 본문 분리는 활성화에 영향 없음(metadata 로드 단계는 frontmatter만 본다).
- **token 절감 효과 측정 필요**: 분리 전후 평균 컨텍스트 점유율 비교 (skills/*/SKILL.md 평균 줄수 추적).

#### 자율 등급
**Manual (제안만)** — orchestrator는 `/nova:auto` 핵심 스킬. 구조 변경은 사용자 결정 후 별도 스프린트.

---

## §4 외부 생태계 보강 (1차 스캔 누락)

### [P-4] `/nova:review` phased workflow 흡수 — minor

#### 발견
Trail of Bits `differential-review` skill은 PR/diff 리뷰를 **6개 phase로 명시 분리**:
```
Pre-Analysis → Phase 0: Triage → Phase 1: Code Analysis → Phase 2: Test Coverage
→ Phase 3: Blast Radius → Phase 4: Deep Context (HIGH RISK only) → Phase 5: Adversarial
→ Phase 6: Report
```
Red flag triggers를 정량/규칙으로 명시:
- "Removed code from 'security', 'CVE', or 'fix' commits"
- "Access control modifiers removed"
- "Validation removed without replacement"
- "External calls added without checks"
- "High blast radius (50+ callers) + HIGH risk change → 즉시 escalation"

출처: https://github.com/trailofbits/skills/blob/main/plugins/differential-review/skills/differential-review/SKILL.md

#### Nova 현재 상태
`commands/review.md`는 적대적 검증(Evaluator) + Severity matrix는 있으나:
- diff/PR 단위 phase 분리 없음
- blast radius 정량 트리거 없음
- git history regression 시그널(security/CVE/fix 커밋 회귀) 없음

#### Nova 적용 방안
review.md에 "PR/diff 모드"를 옵션으로 추가하고 Phase 0~6 구조를 흡수. 단 Nova는 review를 PR 전용이 아닌 일반 코드 리뷰로도 쓰기 때문에 **모드 분기**:
- 일반 모드(현재): 기존 Evaluator 적대적 검증
- diff 모드(신규): Phase 0~6 + blast radius 트리거

#### 영향 범위
- `commands/review.md` (~150줄 신규 섹션)
- `skills/evaluator/SKILL.md` (diff 모드 진입 룰 추가, 현재 393줄 → 분리 권장 P-3과 결합)
- 회귀 가드: tests/test-scripts.sh — review.md "Phase 3: Blast Radius" 키워드 등 grep

#### 리스크
- Nova의 단순성(Generator-Evaluator 분리) 철학과 6-phase가 충돌할 수 있음. **모드 분기로 옵트인**으로 두면 회피 가능.
- 50+ callers 정량 기준은 grep/ripgrep으로 측정. 동적 호출(reflection) 케이스 false negative.

#### 자율 등급
**Manual (제안만)** — review.md는 가장 무거운 커맨드. 별도 스프린트 + Plan 필수.

---

### [P-5] Generator에 TDD-first 시그널 강화 — patch

#### 발견
Cursor 공식 가이드(2026): "ask agents to write failing tests first, then implement code to pass them. Agents perform best when they have a clear target to iterate against."

Cline의 Plan/Act 분리, Aider의 test-driven 패턴 모두 동일 결론.

출처: https://cursor.com/blog/agent-best-practices

#### Nova 현재 상태
`/nova:run` Generator phase는 Spec 기반 구현이 기본. **failing test 우선** 시그널 명시 X. 사용자가 명시 요청해야 적용됨.

#### Nova 적용 방안
`commands/run.md` Generator 프롬프트 가이드에 1줄 추가:
> "복잡도가 보통 이상이고 검증 가능 단위가 명확하면 failing test 먼저 작성 후 구현 (TDD-first). Evaluator가 PASS/FAIL 즉시 판정 가능한 시그널을 강화한다."

#### 영향 범위
- `commands/run.md` (~5줄)
- 회귀 가드: tests/test-scripts.sh — TDD-first 키워드 grep

#### 리스크
- 단순(1~2 파일) 변경에서 TDD가 오히려 오버헤드. "복잡도 보통 이상" 조건으로 제한.

#### 자율 등급
**Full Auto** — 가이드 문구만 추가, 동작 변경 없음.

---

### [P-6] Evaluator FAIL 후 "Re-plan vs Patch" 결정 룰 — patch

#### 발견
Cursor 공식 가이드(2026): "When agents produce unsatisfactory results, instead of trying to fix it through follow-up prompts, **go back to the plan**. Revert changes, refine the plan with more specificity, and run again — this produces cleaner results than iterative fixes."

출처: https://cursor.com/blog/agent-best-practices

#### Nova 현재 상태
`/nova:run` Evaluator FAIL 후 처리는 "수정 시도 1회"가 기본. **언제 patch vs 언제 re-plan**인지 룰 명시 X. 메모리 `feedback_evaluator_rerun.md`(2회전 필수)와 결합 가능.

#### Nova 적용 방안
`skills/evaluator/SKILL.md` 또는 `commands/run.md`에 결정 룰:
| FAIL 패턴 | 권장 |
|----------|------|
| 단일 함수/파일 한정, Critical 1~2건 | Patch (1회전) |
| 다중 파일 영향, 설계 가정 위반 | Re-plan (Plan 문서 갱신 후 재구현) |
| Evaluator 동일 카테고리 2회 연속 FAIL | 강제 Re-plan (자동 분류) |

#### 영향 범위
- `skills/evaluator/SKILL.md` 또는 `commands/run.md` (~20줄)
- 회귀 가드: tests/test-scripts.sh — "Re-plan" 또는 "재계획" 키워드 grep

#### 리스크
- 자동 re-plan이 사용자 의도와 충돌 가능. **사용자 확인** 단계 유지(체크포인트 메모리 `feedback_sprint_checkpoint.md`와 일치).

#### 자율 등급
**Semi Auto (PR)** — Evaluator 동작 정책 변경. 사용자 리뷰 후 머지.

---

### [P-7] /nova:evolve 자체에 외부 생태계 스캔 강제 — patch (메타-evolve)

#### 발견
**본 스캔의 1차 결과가 Anthropic 공식에 편중됐다는 사용자 피드백.** 커맨드 정의에는 "하네스 도구", "Claude Code 생태계"가 명시되어 있으나 운영 시 changelog 위주로 흐르는 경향. evolve가 자기 진화 도구임에도 스캔 범위 자체가 self-bias 가능.

출처: 본 conversation 사용자 피드백 (2026-05-08)

#### Nova 적용 방안
`commands/evolve.md`의 "스캔 절차"에 **최소 소스 다양성 규칙** 추가:
> "Phase 1 스캔에서 Anthropic 공식 changelog 외에 최소 2개 외부 소스(GitHub awesome-list, 외부 코딩 에이전트 공식 가이드, 보안/품질 skills 컬렉션 중 택)를 의무 포함. 외부 소스 0건이면 보고서에 명시 'Limited scan — Anthropic-only' 경고."

#### 영향 범위
- `commands/evolve.md` (~10줄)
- 회귀 가드: tests/test-scripts.sh — "최소 소스 다양성" 또는 "Limited scan" 키워드 grep

#### 리스크
- 스캔 시간 증가(외부 도메인 추가 fetch). 적당한 trade-off.
- 외부 소스 노이즈 유입 가능 — 관련성 필터(§4 Pillar)가 그대로 작동하므로 위험 낮음.

#### 자율 등급
**Full Auto** — evolve 커맨드 자체 가이드라인 강화, 동작 즉시 변경 없음.

---

## 정리 (최종)

- **patch (4건)**: P-1 effort 캡처, P-5 TDD-first 시그널, P-6 Re-plan vs Patch 룰, P-7 evolve 소스 다양성
- **minor (3건)**: P-2 CC SESSION_ID 통합, P-3 SKILL.md 분리, P-4 review phased workflow
- **major (0건)**

### 우선 적용 추천 순서

1. **P-7 (patch, 메타-evolve)** — evolve 자체 개선. **최우선** — 다음 스캔의 self-bias 차단.
2. **P-1 (patch)** — Full Auto 가능. effort 데이터 축적 시작.
3. **P-5 (patch)** — Full Auto. Generator 프롬프트 1줄 강화.
4. **P-6 (patch)** — Semi Auto. Re-plan 룰은 사용자 합의 필요.
5. **P-2 (minor)** — record-event.sh 무게 있는 변경. PR 권장.
6. **P-4 (minor)** — review.md 대형 변경. Plan 필요.
7. **P-3 (minor)** — orchestrator SKILL.md 분리. Manual 결정.

### Out-of-scope (다음 스캔 후보)

- `xhigh` effort level 자체 노출 (M-1 보류 트랙)
- progressive disclosure 분리 후 token 절감 측정 framework
- evolve_decision 이벤트가 effort 분포와 어떻게 상관되는지 (P-1 데이터 축적 후 follow-up)
- Trail of Bits `audit-context-building` skill — `/nova:audit-self`에 흡수 가능성 (별도 스프린트)
- Cline `Plan/Act` 명시 분리 — Nova `/nova:plan` + `/nova:run`이 사실상 분리지만 강제력 비교 검토 필요
