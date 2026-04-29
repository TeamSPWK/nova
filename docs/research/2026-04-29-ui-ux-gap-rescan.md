---
name: UI/UX 갭 재조사 — 사용자 직감 + 3축 실측
description: 폐기된 3 proposal을 백지화하고 사용자 needs(시각 의도 캡처/자가 검증 부재) 기준으로 재조사. Nova 본체/외부 생태계/경쟁 프레임워크 3축 데이터 + 갭 정의 + 근본 해결 설계.
type: research
date: 2026-04-29
status: pending-decision
supersedes:
  - docs/proposals/archive/2026-04-18-design-system-evaluator.md
  - docs/proposals/archive/2026-04-18-ui-build-command.md
  - docs/proposals/archive/2026-04-18-figma-skills-cooperation.md
---

# UI/UX 갭 재조사 (2026-04-29)

> 폐기된 3 proposal은 갭 정의가 부정확하거나(design-system-evaluator는 Generator 아닌 Evaluator), 사용자 결정으로 보류(ui-build-command). 백지에서 사용자 직감 + 3축 실측으로 재정의.

---

## Context — 사용자가 식별한 진짜 갭

| 사용자 응답 | 추출 신호 |
|------------|---------|
| (a) "에이전트가 완료라는데 오류/요청 미처리 흔적" | 자가 검증 게이트 부재 — 완료 선언 자격 없음에도 선언 |
| (b) "디자인 시스템 있으면 좋다 (일관성)" | DS 활용은 사용자 결정 사항. Nova는 묻고 강제만 |
| (c) "Nova 워크플로우 따르는데 UI/UX 누락. 계획·설계만으로 UI 구현" | plan/design에 시각 의도 슬롯 없음 |
| (d) ★ "디자인을 물어보는 시점이 없다" | 시각 의도 캡처 게이트 자체가 없음 — 가장 강한 통찰 |

**한 줄 요약**: 에이전트가 시각 의도를 묻지도 않고, 시각 검증 없이 "완료" 선언.

---

## Problem — 3축 실측 결과

### 축 2: Nova 본체 트리거 매트릭스 (직접 grep+read)

| 게이트 | /nova:auto | /nova:plan | /nova:design | /nova:run | /nova:check | /nova:next |
|--------|-----------|------------|--------------|-----------|-------------|-----------|
| **G1 시각 의도 캡처** | "UI 가능성: Yes/No" 1줄 표시만 (분기 X) | ❌ — CPS 텍스트만 | ❌ — Architect가 "디자인 토큰" 알아서 채움. 사용자에게 묻지 않음 | ❌ | ❌ | ❌ |
| **G2 중간 시각 검증** | ❌ | — | — | --strict에 playwright 옵션만 (컴포넌트 단위 X) | ❌ | ❌ |
| **G3 자가 검증 자동 트리거** | ✅ Phase 5.5 ux-audit Lite (코드 분석) + critical 차단 | — | — | ❌ | ❌ | 추천 안내만 (강제 X) |
| **G3 시각(스크린샷) 검증** | ❌ — Lite는 코드만 본다 | — | — | ❌ | ❌ | ❌ |

**기존 인프라**: `scripts/detect-ui-change.sh`, `scripts/detect-design-system.sh`는 이미 존재. 단 orchestrator(/nova:auto)에서만 사용. 다른 커맨드들은 이용 안 함.

**핵심 발견**: 사용자가 `/nova:plan + /nova:design + /nova:run`을 직접 호출하면 **G1/G2/G3 어느 게이트도 작동하지 않는다**. /nova:auto만이 G3-Lite(코드 분석)을 가짐. 시각(스크린샷) 검증은 어디에도 없음.

### 축 1: 외부 생태계 SOTA (2026-04)

| 패턴 | 제품/연구 | URL |
|------|---------|------|
| VLM-Judge as completion judge | AAAI 2026 paper "Are We Done Yet?" — 73% 분류 정확도, +27% 평균 성공률, +61% Claude 3.5 Sonnet 재시도 | arxiv.org/html/2511.20067 |
| ProofShot — 시각 증거 강제 산출 | Open-source CLI, agent-agnostic | github.com/AmElmo/proofshot |
| Playwright MCP + 스크린샷 iteration | Anthropic 공식 권장 ("include screenshots/expected outputs so Claude can check itself") | claude.com/plugins/playwright |
| Figma Code Connect intent contract | Figma 공식 — 컴포넌트 코드↔Figma 결합 | figma.com/blog/introducing-figma-mcp-server/ |

**Ecosystem 갭** (어느 SOTA도 안 채움):
- 비-Figma 사용자용 사전 시각 의도 캡처 — Figma 전제 없는 곳에 SOTA 부재
- VLM-judge를 **차단 게이트**로 쓰는 제품 부재 (Cursor도 "investigation tool, not completion gate" 명시)
- 의도 vs 출력 시맨틱 diff (Percy류는 이전 상태 diff만, 의도 diff 부재)
- UI 파일 변경 시 PostToolUse 자동 시각 검증 (린트/테스트는 있지만 시각은 없음)

### 축 3: 경쟁 프레임워크 분석

| 프레임워크 | G1 시각 의도 | G2 중간 검증 | G3 자가 차단 게이트 | 철학 |
|-----------|------------|-------------|--------------------|------|
| ECC | No | Partial (e2e-testing 스킬) | No | 시각=테스트 부산물 |
| **superpowers** | **Yes** — visual-companion 브레인스토밍에서 wireframe HTML 렌더 | No | No | 아이디어 단계만 |
| paperclip | No | No | No | 거버넌스 레이어 |
| Claude Code (공식) | No | Partial (Playwright MCP 수동) | No | Tool-provider |
| Cursor | No | Partial | Partial (인간 리뷰) | 도구이지 게이트 아님 |
| Cline | No | Yes (Computer Use) | Partial (반응적) | Reactive 디버깅 |
| **Devin** | Partial | Yes (desktop QA) | **Yes** (가장 근접 — "QA its PR") | 시각 추론 약점 인정 |

**Key Insight**: 
- G1 — superpowers만 유일 (브레인스토밍에서만)
- G2 — 다수 프레임워크에 있으나 모두 opt-in 도구. 강제 게이트 X.
- G3 — Devin만 가장 근접. 다른 모두는 반응적 도구.

→ **G1+G3 페어 강제 게이트는 어느 프레임워크도 안 한다.** 부분 부품은 흩어져 있지만 페어로 닫힌 루프를 강제하는 곳 없음. **Nova first-mover 가능 영역.**

---

## Solution — 3개 게이트 근본 설계

### 설계 원칙

1. **새 커맨드 추가 X** — 기존 plan/design/run/auto 워크플로우에 게이트 끼워넣음. 사용자가 이미 쓰는 흐름에서 작동.
2. **G1+G3 페어 우선** — 의도 캡처(G1)만으로는 무의미(검증 없음). 자가 검증(G3)만으로는 무의미(의도 없음). 페어로 닫힌 루프.
3. **기존 인프라 재활용** — detect-ui-change.sh, detect-design-system.sh, ux-audit, orchestrator Phase 5.5 — 새 인프라 최소.
4. **임시 패치 X** — Always-On 게이트로 워크플로우 자체에 박는다. 사용자가 명시 호출 안 해도 작동.
5. **픽셀 완벽 약속 X** — Devin 교훈: "모델은 픽셀 시각 추론 약함". 의도 회귀 검증으로 프레임.

### G1 — Visual Intent Capture in Plan/Design

**무엇**: UI 작업 감지 시 plan.md/design.md가 사용자에게 시각 의도를 묻고 freeze.

**어떻게**:
- plan.md Execution 단계에 추가 — `bash scripts/detect-ui-change.sh --planning` 호출
- `likely_ui == true`면 추가 슬롯 발화:
  - 디자인 시스템 사용 의도? (자동 감지 결과 보여주고 Yes/No/만들기)
  - 시각 입력 형태? (Figma URL / 스크린샷 / 마크다운 wireframe / ASCII / 자연어)
  - 기존 컴포넌트 재사용 vs 새 패턴? (정당성 1줄)
- 결과를 `docs/plans/{slug}-intent.json`에 freeze (또는 Plan 마크다운 inline 섹션)
- design.md Sprint Contract에 "시각 의도 검증 조건" 행 자동 추가

**스킵 옵션**: 사용자가 "디자인 시스템 있고 자연어 충분"이면 1초 컷 (`--no-visual-intent` 또는 캡처 거부)

### G2 — Mid-Implementation Visual Checkpoint (Phase B로 미루기)

**무엇**: UI 컴포넌트 단위로 중간 시각 결과 캡처.

**왜 미루기**: G1+G3가 작동하면 자연스럽게 sprint 분할 시 컴포넌트 단위로 G3가 발화한다. G2는 G1+G3의 부산물. 별도 구현 비용 vs 가치 낮음.

### G3 — Self-Verify Before "Done" (Hard Gate)

**무엇**: 구현 PASS 후 시각 의도 대비 자가 검증, 실패 시 완료 선언 차단.

**어떻게**:
- run.md에 Phase 추가 — Phase 5(검증) PASS 후 Phase 5.5 발화 (현재 /nova:auto Phase 5.5와 동일하게 /nova:run에도 이식)
- Phase 5.5a: ux-audit Lite (코드 분석, 현재 있음)
- Phase 5.5b (신규): Playwright/Computer Use로 스크린샷 캡처 + VLM-judge로 `intent.json` 대비 검증
- VLM verdict `incomplete`면 **PASS 토큰 발급 차단** = 커밋 차단 (현재 /nova:review의 NO_PASS와 동일 메커니즘)
- Phase 5.5b 실패 시 폴백 체인: Playwright → Computer Use → 안내만 (Lite로 폴백, 차단 X)

**캐시**: detect-ui-change.sh의 hash 캐시 활용 — 동일 변경 재검증 차단

---

## 우선순위 / 비용 / 리스크 매트릭스

| 옵션 | 작업 | 가치 | 비용 | 리스크 | 임시 패치 여부 |
|------|------|------|------|-------|--------------|
| **A — G1+G3 페어 (근본 해결)** | plan.md/design.md/run.md에 게이트 추가, intent.json 스키마, VLM-judge 통합 | 매우 높음 — 사용자 (a)(c)(d) 모두 해결, ecosystem first-mover | 큼 — 4~6 SKILL/script 수정, 새 스키마 정의, VLM 비용 모델, 12+ 파일 | 중 — VLM-judge false positive, 사용자 의도 캡처 부담, Playwright/Computer Use 미연결 환경 폴백 | ❌ 워크플로우 게이트 |
| **B — G3만 (자가 검증만)** | run.md에 Phase 5.5 이식 + ux-audit Lite 자동 발화 | 중 — 사용자 (a) 부분 해결. 의도 없으니 "정확한 검증"은 못함. | 작음 — 2~3 파일 | 낮음 | ⚠️ 부분 해결 |
| **C — G1만 (의도 캡처만)** | plan.md/design.md에 시각 의도 슬롯만 추가 | 낮음 — 의도 있어도 검증 없으면 (a) 해결 X | 작음 — 2~3 파일 | 낮음 | ⚠️ 부분 해결 |
| **D — 임시 패치** | next.md 추천 강도 강화, hooks/PostToolUse로 ux-audit 안내만 띄우기 | 매우 낮음 — 사용자 직감 갭 그대로 | 매우 작음 | 매우 낮음 | ✅ 임시 패치 |

**권장: A** — 사용자가 "근본적인 해결"을 명시 요구. B/C/D는 (a)(c)(d) 중 일부만 해결하거나 "안내만" 수준.

### A 옵션 분할 제안

| Phase | 범위 | 예상 파일 수 | 주요 산출 |
|-------|------|------------|----------|
| **A0 — Design 문서** | /nova:design ui-quality-gate 작성. Sprint Contract 정의 | 1 (docs/designs/...) | CPS 설계서 |
| **A1 — G1 의도 캡처** | plan.md/design.md에 detect-ui-change --planning 통합. intent.json 스키마. | 4~5 | Plan에 시각 의도 슬롯 |
| **A2 — G3 자가 검증** | run.md에 Phase 5.5 이식. VLM-judge 통합 (Playwright MCP). 폴백 체인. | 5~6 | run에서 시각 차단 게이트 |
| **A3 — 통합 + 테스트** | session-start.sh 동기화, /nova:next 워크플로우 추천, fixtures, test-scripts.sh 회귀 가드 | 4~5 | 565+N tests |

**총 예상**: 14~17 파일, 4 sprints, 복잡도 8+ → Plan → Design → 스프린트 정상 경로.

---

## 결정 필요 — 사용자 입력

1. **A 옵션(근본 해결)으로 진행하는 게 맞는가?** B/C/D는 사용자가 명시 요구한 "근본적 해결" 기준 미달.
2. **A0 (Design 작성)부터 시작하는가, 아니면 A1+A2 일괄 Plan을 먼저 만드는가?** 복잡도 8+이라 /nova:plan → /nova:design → 스프린트 정상 경로. 권장: /nova:plan부터.
3. **VLM-judge 비용 임계치**: 매 UI 변경마다 VLM 호출 OK? 또는 cache hit율 X% 이상이어야 발화? (현재 detect-ui-change.sh hash 캐시 있음)
4. **Computer Use vs Playwright MCP 우선순위**: 어느 쪽을 primary로? (Playwright MCP가 안정적, Computer Use는 강력하지만 Research Preview)
5. **사용자 의도 캡처 부담 허용 범위**: 모든 UI 작업마다 3~5 질문 OK? 또는 기본 스킵 + opt-in?

---

## Refs

- 폐기된 proposal: `docs/proposals/archive/2026-04-18-{design-system-evaluator,ui-build-command,figma-skills-cooperation}.md`
- 기존 인프라: `scripts/detect-ui-change.sh` (이미 운영), `scripts/detect-design-system.sh`, `.claude/skills/ux-audit/SKILL.md` (5인 평가자), `.claude/skills/orchestrator/SKILL.md` Phase 5.5 (G3-Lite 코드 기반)
- 외부 SOTA: AAAI 2026 VLM-Judge, Anthropic Playwright MCP, superpowers visual-companion, Devin auto-QA
- 사용자 메모리: `feedback_structured_over_natural_language.md` ("구조화 > 자연어"), `feedback_evidence_first_identity.md` ("효과 측정 후 정체성")
