# Evolution Scan: 2026-06-01

> 모드: `--scan` (제안만 생성, 구현/머지 없음)
> 현재 버전: v5.50.0
> 스캐너: 4-category 병렬 (WebSearch + `gh api`) → synthesis(ledger 대조 + MUST 필터 + 분류) → **출처 적대 검증**
> Fallback: Not used (live scan 전 채널 정상)

## Context

ultracode 병렬 워크플로우로 Anthropic 공식 / Claude Code 생태계 / 하네스 도구 / AI 엔지니어링 4개 카테고리를 동시 스캔했다.
4/4 스캐너 정상(WebSearch 정상 + `gh api` 8/8 쿼리 성공, fail 0), 총 41건 발견 → 신호 통과 40건 → ledger 차단 3건 → MUST 통과 9건.

이번 사이클의 차별점: synthesis 통과 9건의 **출처 URL을 전수 적대 검증**했다. 그 결과 Anthropic 기능 5종·GitHub 레포 2건은 견고했으나, AI 엔지니어링 카테고리의 **arxiv 인용 3건이 모두 오인용/불일치/맥락차이**로 드러났다. 아래 "출처 검증 결과"에 명시한다.

## 스캔 범위

| 카테고리 | WebSearch | gh api | 발견 |
|---|---|---|---|
| Anthropic 공식 | 정상 | 2/2 | 10 |
| Claude Code 생태계 | 정상 | 4/4 | 12 |
| 하네스 도구 | 정상 | 2/2 | 9 |
| AI 엔지니어링 | 정상 | n/a | 10 |
| **외부 소스 다양성** | **OK** (ecosystem·harness·ai-eng 3카테고리 통과) | | |

## Nova에 이미 반영됐거나 갭 아님 (ledger 차단 / 잠재 중복)

| 발견 | ledger pattern_slug | 상태 |
|---|---|---|
| CC 2.1.152 SessionStart `reloadSkills:true` + 세션 타이틀 | `anthropic-session-start-reload-skills` | v5.49.0 흡수 |
| CC 2.1.139 stdio MCP에 `CLAUDE_PROJECT_DIR` 노출 | `anthropic-mcp-claude-project-dir` | v5.49.0 흡수 |
| Continuous-Claude-v3 ledger/handoff 세션 상태 | `external-context-chain-comparison` | v5.49.0 흡수 |
| anthropics/claude-plugins-official 디렉토리 등재 | (5/27 P-4 재확인) | 미적용 major — 사용자 결정 대기 |
| MCP Elicitation 대화형 입력 채널 | (5/27 P-2 재확인) | 미적용 major — 사용자 결정 대기 |

---

## 출처 검증 결과 (적대 검증, 이번 사이클 신규)

| 제안 | 출처 | 검증 | 판정 |
|---|---|---|---|
| P-1 | CC CHANGELOG v2.1.152 `disallowed-tools` | ✅ 원문 라인 확인 | 견고 |
| P-2 | CC CHANGELOG v2.1.133 `$CLAUDE_EFFORT`/`effort.level` | ✅ 원문 라인 확인 (synth는 "2.1.128~136"으로 모호 → **v2.1.133**로 보정) | 견고 |
| P-3 | CC CHANGELOG v2.1.152 `MessageDisplay` hook | ✅ 원문 라인 확인 | 견고 |
| P-4 | Cursor `.mdc` 스코핑 블로그 | ⚠ 블로그 1차 출처 미정밀검증(일반 주장, awesome-cursorrules 실재) | 합리적 |
| P-5 | github.com/anthropics/claude-code-security-review | ✅ 4,896 stars, 2026-02 활성 | 견고 |
| P-6 | arxiv 2509.11068 | ⚠ **맥락 차이** — 실제 논문은 "모델 진위 감사(deterministic replicability)"지 게이트 경제성이 아님. "검증<생성 12×" 수치는 사실이나 일반 명제로만 인용 가능 | 조건부 |
| P-7 | arxiv 2503.16416 | ❌ **출처 불일치** — 실제 제목 "Survey on Evaluation of LLM-based Agents". metacognition 논문 아님 → **인용 교체 필요** | 출처 무효 (제안 아이디어는 유효) |
| P-8 | arxiv 2602.03053 (MAS-ProVe) | ❌ **결론 상반** — 논문 실제 결론은 "process-level 검증이 일관된 개선 없음 + 고분산". synth가 정반대로 인용 → **근거 무효** | 폐기 권고 |
| P-9 | github.com/pdavis68/RepoMapper | ✅ 173 stars, 2025-12 활성 | 견고 |

> 교훈: WebSearch-only 카테고리(ai-eng)의 학술 인용은 환각/오인용 위험이 높다. **출처 전수 검증을 evolve Phase 2.5로 상시화**할 가치가 확인됨(아래 P-10으로 자기제안).

---

## 신규 관련 항목

### [P-1] command/skill frontmatter `disallowed-tools`로 Evaluator 경로 read-only 강제 — minor

#### 발견
- 출처: https://code.claude.com/docs/en/changelog (v2.1.152, **원문 검증됨**)
- CC 2.1.152부터 스킬·슬래시 커맨드 frontmatter에서 `disallowed-tools`로 모델 접근 도구를 선언적으로 제거 가능. Roo Code도 모드별 `groups` 키로 동일 패턴(read-only 모드는 쓰기 불가) 강제.

#### Nova 현재 상태
`agents/qa-engineer.md`는 이미 `disallowedTools: Edit, Write, NotebookEdit` 보유. 그러나 (1) `skills/evaluator/SKILL.md`, (2) `commands/review.md`·`commands/check.md` frontmatter에는 도구 제한이 없다.

#### Nova 적용 방안
Evaluator 경로 전체를 frontmatter 레벨에서 read-only로 묶어 "적대적 검증자가 자기가 평가하는 코드를 수정"하는 독립성 위반을 **프롬프트가 아닌 도구 권한**으로 차단. MEMORY `feedback_skill_contract_enforcement`("soft 문구는 실제 세션에서 스킵됨, 프롬프트+훅+테스트 3중 방어")와 정합 — frontmatter 권한 차단이 4번째 방어층.

#### 영향 범위
`skills/evaluator/SKILL.md`, `commands/review.md`, `commands/check.md` frontmatter. 동작 변경 없이 권한만 좁힘 → 회귀 위험 낮음. test-scripts.sh 동기화 회귀 가드 추가.

#### 리스크
Evaluator가 검증 중 임시 수정으로 재현 테스트하던 패턴이 있으면 차단됨. 적용 전 evaluator 워크플로가 순수 read-only인지 확인 필요. CC 2.1.152+ 버전 의존 → 구버전 graceful degradation 확인.

#### 자율 등급
Semi Auto (PR)

---

### [P-2] effort-aware gate intensity — `$CLAUDE_EFFORT`로 게이트 강도 자동 조절 — minor

#### 발견
- 출처: https://code.claude.com/docs/en/changelog (v2.1.133, **원문 검증됨**)
- CC 2.1.133부터 훅이 `effort.level` JSON 입력 + `$CLAUDE_EFFORT` 환경변수로 현재 effort를 인식. Opus 4.8은 high effort 기본 + `/effort xhigh` 지원.

#### Nova 현재 상태
`hooks/`에 effort 참조 전무. release.sh는 review 강도를 변경 수준(patch=`--fast`/minor=기본/major=`--strict`)으로만 매핑한다 — effort 축 없음.

#### Nova 적용 방안
`session-start.sh`/`pre-commit-reminder.sh`가 `$CLAUDE_EFFORT`를 읽어 게이트 강도 매핑에 effort 축 추가. xhigh 세션이면 `--strict` 권고, low면 `--fast` 허용. `docs/nova-rules.md`에 "effort-aware gate intensity" 규칙 1줄 + session-start.sh 동기화. **이 세션 자체가 ultracode/xhigh 사례** — dogfooding 검증 가능.

#### 영향 범위
`hooks/session-start.sh` effort 감지 분기, `docs/nova-rules.md`. 옵션 추가 성격 → 기존 동작 호환.

#### 리스크
effort API 미주입 환경 → fallback(미감지=기존 동작) 필수. 잘못 매핑 시 게이트 약화 위험 → "낮은 effort에서도 **최소 게이트 보장** 하한" 명시 필요(MUST NOT: Generator-Evaluator 약화 근접 주의).

#### 자율 등급
Semi Auto (PR)

---

### [P-3] `MessageDisplay` 훅으로 게이트 상태 배지 출력단 주입 (PoC) — major

#### 발견
- 출처: https://docs.anthropic.com/en/docs/claude-code/hooks , CC CHANGELOG v2.1.152 (**원문 검증됨**)
- CC 2.1.152에 어시스턴트 메시지 표시 텍스트를 변환/숨김하는 `MessageDisplay` 훅 이벤트 신설.

#### Nova 현재 상태
Nova는 입력단(session-start additionalContext)·이벤트단(pre-commit-reminder)으로만 게이트 신호를 낸다. 출력단 확장점 미탐색. session-nametag(v5.50.0)가 "색상은 hook 제어 불가"로 범위 제외했던 한계의 일부를 표시단 훅이 보완할 가능성.

#### Nova 적용 방안
Evaluator 미통과/미커밋 상태 배지를 어시스턴트 응답 표시단에 일관 주입. `hooks/hooks.json`에 이벤트 등록 + 신규 `hooks/message-display-*.sh`. **PoC로만**, 항상-on 금지.

#### 영향 범위
`hooks/hooks.json`, 신규 hook 스크립트. CC 2.1.152+ 의존 → 호환성 가드 필수.

#### 리스크
출력 변환은 가독성/노이즈 트레이드오프가 크고 API 안정성 미검증. 과도 주입 시 token-tax/노이즈 역효과. **major — 사용자 결정 대기.**

#### 자율 등급
Manual (제안만)

---

### [P-4] always-on 규칙 token-tax 스코핑 — session-start 주입분 핵심/상황별 분리 — minor

#### 발견
- 출처: https://thepromptshelf.dev/blog/cursorrules-vs-mdc-format-guide-2026/ (블로그, ⚠ 1차 미검증)
- Cursor 2026은 `.cursor/rules/`를 Always Apply / Auto Attached(globs) / Agent Requested(description) / Manual 4모드로 스코핑하고, always-apply 규칙은 매 요청 토큰을 먹어 200단어 미만 권장(token tax). awesome-cursorrules 39.8k stars로 스코핑 생태계 정착.

#### Nova 현재 상태
`session-start.sh`는 "매 세션 자동 주입되는 유일한 전역 규칙"(약 290줄)이라 동일 token-tax 문제. nova-rules는 이미 on-demand 로드 섹션 보유.

#### Nova 적용 방안
session-start 주입분을 "항상 필요한 핵심 게이트"와 "상황별(커맨드/파일타입 트리거 시 로드)"로 명시 분리. always-on 토큰 예산 축소.

#### 영향 범위
`hooks/session-start.sh` additionalContext 구조, `docs/nova-rules.md` 로드 정책. test-scripts.sh 동기화 재통과 필수.

#### 리스크
핵심 게이트를 상황별로 내리면 주입 누락 → 게이트 약화 위험. "무엇이 always-on이어야 하는가" 경계가 핵심. 보수적 분류 필수(MUST NOT 근접).

#### 자율 등급
Semi Auto (PR)

---

### [P-5] 공식 security-review 룰셋과 audit-self 대조·보강 — minor

#### 발견
- 출처: https://github.com/anthropics/claude-code-security-review (**4,896 stars, 2026-02 활성 검증됨**)
- 공식 보안 플러그인이 편집/diff/커밋을 실시간 모니터링해 SQLi·커맨드 인젝션·XSS·하드코딩 시크릿 등 고위험 패턴을 자동 플래그.

#### Nova 현재 상태
`dev/commands/audit-self.md`(30+ 룰셋, 5 카테고리, security-engineer→evaluator 직렬) 보유.

#### Nova 적용 방안
공식 플러그인의 카테고리/패턴을 audit-self 룰셋과 1:1 대조해 누락 패턴(특히 diff 단위 실시간 검사 관점) 보강. nova-rules §17 Hook Safety와 연계.

#### 영향 범위
`dev/commands/audit-self.md` 룰셋, 관련 design 문서.

#### 리스크
공식 플러그인은 범용 코드 대상, audit-self는 Nova 자기 코드 대상 → 적용 범위 상이. 무분별 복제 시 false positive 증가 → 관련성 필터 후 흡수.

#### 자율 등급
Semi Auto (PR)

---

### [P-6] 검증 경제성 근거 보강 — "검증<생성 비용" 1단락 — patch ⚠ 출처 맥락 차이

#### 발견
- 출처: https://arxiv.org/abs/2509.11068 "Tractable Asymmetric Verification for LLMs via Deterministic Replicability"
- ⚠ **검증 결과**: 논문 실제 맥락은 "한 에이전트가 다른 에이전트 출력의 모델 진위를 감사"(deterministic replicability). "targeted verification이 full regeneration보다 12×+ 빠르다"는 수치는 사실이나, Nova가 인용하려는 "매 커밋 게이트 경제성"과는 결이 다름.

#### Nova 적용 방안
"검증은 생성보다 저비용" **일반 명제**로만 인용. nova-rules §2/§3에 1단락 추가하되, 직접 적용("모든 검증이 싸다")으로 과대 일반화 금지. Nova 게이트가 실제로 결정론적(tsc/lint/test)인 범위에 한정 인용.

#### 영향 범위
`docs/nova-rules.md` 근거 인용 1단락. 로직 변경 없음.

#### 리스크
근거 보강일 뿐 강제력 변화 없음. 출처 맥락 차이를 각주로 명시하지 않으면 오인용 재생산.

#### 자율 등급
Full Auto (단, 출처 맥락 각주 필수)

---

### [P-7] evolve 메타-평가 루프 — "흡수 변경이 게이트 통과율을 개선했는가" 측정 — minor ❌ 인용 교체 필요

#### 발견
- 출처: ~~https://arxiv.org/abs/2503.16416~~ → ❌ **출처 불일치** (실제 제목 "Survey on Evaluation of LLM-based Agents", metacognition 논문 아님). **인용 교체 또는 출처 없이 Nova 내부 Known Gap 근거로 전환 필요.**
- 제안 아이디어 자체는 출처와 독립적으로 유효 (Nova 자체 Known Gap).

#### Nova 현재 상태
Nova Adaptive(`/evolve`)는 "동향 흡수"는 하지만 "흡수한 변경이 실제 게이트 통과율/회귀 가드 효과를 개선했는가"를 측정하지 않는다(Known Gap, MEMORY `project_evolve_github_actions`·measurement 계열과 연결).

#### Nova 적용 방안
`measurement-closed-loop`(publish-metrics.sh)와 연계해 evolve 사이클 전후 게이트 메트릭 비교 스텝을 evolve.md에 추가.

#### 영향 범위
`dev/commands/evolve.md`, `dev/docs/evolve-baseline.md`, publish-metrics 연계.

#### 리스크
메트릭 인과 귀인 어려움(흡수 외 변수 다수) → 추세 신호로만. 측정 오버헤드가 evolve 사이클을 무겁게 할 수 있음. **출처를 교체하지 않으면 환각 인용으로 신뢰성 훼손.**

#### 자율 등급
Semi Auto (PR) — 단, 출처 교체 선행 조건

---

### [P-8] ~~MAS-ProVe 이중 검증축~~ — **폐기 권고** ❌ 출처 결론 상반

#### 발견
- 출처: https://arxiv.org/abs/2602.03053 "MAS-ProVe: Understanding the Process Verification of Multi-Agent Systems"
- ❌ **검증 결과**: 논문 실제 결론은 *"process-level verification does not consistently improve performance and frequently exhibits high variance"* — synth가 "이중 granularity 검증이 품질 유의미 향상"으로 **정반대 인용**.

#### 판정
근거가 뒤집혔으므로 **본 제안은 폐기**. 다만 논문의 진짜 결론("프로세스 검증은 무조건 좋지 않다, 고분산")은 오히려 Nova에 **반대 방향 시사점**을 준다 — iteration-level 검증축을 무분별 추가하면 분산만 키울 수 있으니, **고복잡도 한정 선택 적용** 원칙(이미 Nova가 보수적)이 학술적으로 지지됨. 즉 "검증축을 늘리자"가 아니라 "현 보수적 게이팅이 옳다"는 근거로 재해석.

#### 자율 등급
폐기 (제안 채택 X, 재해석만 기록)

---

### [P-9] Aider Repo Map — tree-sitter 랭킹 기반 컨텍스트 압축 맵 — major

#### 발견
- 출처: https://github.com/pdavis68/RepoMapper (**173 stars, 2025-12 활성 검증됨**)
- tree-sitter로 심볼/시그니처 추출 + 그래프 랭킹으로 LLM 컨텍스트에 핵심만 압축 주입(Aider Repo Map 독립 추출).

#### Nova 현재 상태
`/scan`(skills/scan)은 코드베이스를 브리핑하지만 랭킹 기반 압축 맵 없음.

#### Nova 적용 방안
대형 레포에서 Generator/Evaluator 주입 컨텍스트를 토큰 효율화. PoC로 `/scan` 출력에 랭킹 맵 옵션 추가 검토.

#### 영향 범위
`skills/scan`, 신규 repo-map 스크립트(tree-sitter 의존). **외부 패키지 도입 → 사용자 승인 필요.**

#### 리스크
tree-sitter 신규 의존성(설치/언어 커버리지 부담). Nova 경량 hook 철학과 무게 트레이드오프. 작은 레포엔 과함 → 대형 레포 한정 가치. **major — 사용자 결정 대기.**

#### 자율 등급
Manual (제안만)

---

### [P-10] (자기제안) evolve 출처 진위 1차 대조 + 직전 비채택 중복 차단 — minor

> **→ 축소 채택 완료 (v5.51.0)**: 원안 "Phase 2.5 전수 적대 검증 상시화"는 과잉으로 판정되어, **별도 Phase 신설 없이** 고위험 출처(WebSearch-only 학술/블로그) 한정 1차 대조 + MUST NOT 규칙 + Ledger 직전 비채택 매칭으로 흡수됨. 구현: `dev/commands/evolve.md`·`dev/skills/evolution/SKILL.md`·`tests/test-scripts.sh`(가드 4). Gate 1 PASS(1085/1085) + 독립 Evaluator PASS(6/6).

#### 발견
- 출처: 본 스캔 사이클 자체 (ai-eng arxiv 인용 3/3 오류 발견)
- WebSearch-only 카테고리의 학술 인용은 환각/오인용/결론왜곡 위험이 높다는 것이 이번 사이클에서 실증됨.

#### Nova 적용 방안
evolve 파이프라인에 **Phase 2.5: Source Verification**을 명시 추가 — synthesis 통과 항목의 source_url을 WebFetch/`gh api`로 전수 검증하고, 미검증·불일치·결론상반 항목을 제안서 헤더에 강제 표기. `skills/evolution/SKILL.md`·`dev/commands/evolve.md`에 절차 추가.

#### 영향 범위
`dev/commands/evolve.md`(Phase 추가), `dev/skills/evolution/SKILL.md`. evolve 자기 신뢰성 강화.

#### 리스크
검증 호출 증가로 스캔 시간/토큰 증가 → ai-eng·블로그 등 "고위험 출처"만 의무화하고 Anthropic 공식·고star GitHub는 경량 확인으로 차등. 본 제안이 채택되면 ledger `evolve-source-verification`으로 등재.

#### 자율 등급
Semi Auto (PR)

---

## 독립 검증 결과 (2단계 적대 검증, 2026-06-01)

제안서(Generator 산출물)를 **코드 사실 검증 → 적대적 채택 심사** 2단계로 독립 검증했다(12 에이전트). 결과: **출처 URL은 견고했으나 "Nova 현재 상태" 사실 주장 다수가 코드 현실과 어긋났다.** Generator-Evaluator 분리의 가치를 다시 증명 — synthesis는 grep을 주장했으나 실제 레이어·경로·키 표기를 틀렸다.

| # | 검증 후 권고 | 핵심 근거 (코드 확인) |
|---|---|---|
| P-1 | **adopt-with-revision** | ❌ **잘못된 레이어**: read-only는 커맨드/스킬이 아니라 **에이전트** 레벨 강제. qa-engineer/architect/refiner/security-engineer 4개 에이전트가 **이미** `disallowedTools` 운영 중. ❌ **키 오류**: 제안은 kebab `disallowed-tools`인데 코드/CC enforce 키는 camelCase `disallowedTools`(nova-rules.md:316) — 글자대로 구현 시 silent-fail. ✅ 3중 방어(프롬프트+disallowedTools+PreToolUse `pre-edit-check.sh`) 이미 거의 완성. → 실질 신규 갭 ≈ 0, 먼저 갭 확인 필요 |
| P-2 | **defer** | ❌ **거짓 전제**: "release.sh가 review 강도 매핑" — release.sh엔 없음(scripts/release.sh), 매핑은 CLAUDE.md:110 **산문에만** 존재. ✅ 더 단순한 자산 `NOVA_PROFILE=lean\|standard\|strict`(session-start.sh:31) 이미 존재. ⚠ low effort→--fast 자동 약화는 Generator-Evaluator 최강 기둥 역행. effort 캡처(생산자)도 미착륙 |
| P-3 | **defer** | ⚠ 색상: session-nametag allowlist가 CSI/OSC 거부(session-nametag.md:42) → 배지 색상 가치 무너질 수 있음. ⚠ **기존 채널 중복**: stop-event.sh:50·audit-teammates.sh:44가 이미 `NOVA_DESKTOP_NOTIFY`로 commit_blocked·evaluator FAIL emit. 출력단 변환 blast radius 최대. 제안자도 major/제안만 |
| P-5 | **defer (본체) + patch (부산물)** | ❌ **스코프 불일치**: 공식 플러그인=application 취약점(SQLi/XSS), audit-self=Nova 메타파일 정적위생 — 교집합 거의 없음. audit-self는 dev/ 전용(사용자 전달 0). ✅ **실제 갭 발견**: `docs/security-rules.md` 헤더 "33 룰" vs 실제 **30개**(문서 오류) + §17↔audit-self 크로스레퍼런스 부재 → patch로 즉시 처리 가능 |
| P-9 | **drop** | ❌ **중복 기각**: 동일 아이디어(tree-sitter+그래프 랭킹)가 직전 사이클 2026-05-27:218에서 graphify(54k stars)로 **이미 비채택**(의존성 무게). evolve 중복 필터 누락 신호. ❌ **경로 오류**: 대상 `skills/scan/SKILL.md` **존재 안 함** — 실제는 `commands/scan.md`. scan.md:105 "브리핑 간결하게"는 의도적 경계 |
| P-10 | **adopt-with-revision** | ✅ 문제의식 정당(3주장 모두 코드 확인). ⚠ **"전수"는 과잉** — 실패는 ai-eng(WebSearch-only) 단일 영역 집중, 나머지 출처는 clean. 자기 완화책과도 모순. → 별도 Phase 신설 대신 **SKILL.md MUST NOT 한 줄**("WebSearch-only 학술/블로그 단독 근거 금지, 고위험 출처만 WebFetch 대조") + 중복 필터에 직전 비채택 항목 매칭으로 축소 |

> P-4(블로그)·P-6/P-7/P-8(arxiv 결함)은 1차 스캔에서 이미 신중/조건부/폐기 판정 → 재검증 대상 제외.

### 검증이 발견한 "진짜 수확" (제안서 본체보다 가치 높음)

스캔 제안 9건 중 **지금 구현할 신규 기능은 사실상 없다**(이미 구현/거짓 전제/중복/스코프 불일치). 대신 검증이 부수적으로 드러낸 실제 고칠거리:

1. **evolve 파이프라인 갭 2건** (이번 사이클이 직접 입증):
   - WebSearch-only 학술/블로그 인용 환각 (P-6/7/8 = arxiv 3/3 결함)
   - 중복 필터가 직전 비채택 항목(graphify)을 못 잡고 RepoMapper로 재제출(P-9)
2. **문서 드리프트**:
   - `docs/security-rules.md` "33 룰" → 실제 30 (오기)
   - `CLAUDE.md:110` release.sh review 강도 매핑 = 코드에 없는 산문-only 거짓 전제 (별도 확인 필요)
   - nova-rules §17 ↔ audit-self 크로스레퍼런스 부재

## 요약 (검증 후 최종)

| # | 제안 | 수준 | 1차 출처 | 검증 후 권고 |
|---|---|---|---|---|
| P-1 | disallowed-tools read-only | minor | ✅ | adopt-with-revision (에이전트 레벨·camelCase·갭 먼저) |
| P-2 | effort-aware gate | minor | ✅ | **defer** (거짓 전제, NOVA_PROFILE 자산) |
| P-3 | MessageDisplay 배지 PoC | major | ✅ | **defer** (색상 거부·채널 중복) |
| P-4 | always-on token-tax 스코핑 | minor | ⚠ | 신중 검토 |
| P-5 | security-review 룰셋 대조 | minor | ✅ | **defer** 본체 / **patch** 부산물(33→30·크로스레퍼런스) |
| P-6 | 검증 경제성 근거 | patch | ⚠ | 각주 조건부 |
| P-7 | evolve 메타-평가 루프 | minor | ❌ | 인용 교체 후 |
| P-8 | MAS-ProVe 이중 검증축 | — | ❌ | **폐기** |
| P-9 | Aider Repo Map | major | ✅ | **drop** (중복 기각·경로 오류) |
| P-10 | evolve 출처 검증 (자기제안) | minor | ✅ | **adopt (축소)** — MUST NOT 규칙 + 중복 필터 |

> `--scan` 모드 종료. 구현/머지 없음. 검증 결과 **P-10 축소판(+중복 필터) minor 1건**이 즉시 채택 1순위.
> Ledger: `dev/docs/proposals/_ABSORBED.md` (채택·머지 시 자동 append).
