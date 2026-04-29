# UI Quality Gate — Visual Intent Capture + Self-Verify (G1+G3)

> Nova의 UI/UX 작업 게이트. **시각 의도를 묻지 않고, 시각 검증 없이 "완료" 선언하는 갭**을 차단.
> Spec: `docs/designs/visual-intent-verify.md` · Plan: `docs/plans/visual-intent-verify.md`

---

## TL;DR

UI 코드 변경 시 Nova가 자동으로:

1. **G1 (계획 단계)**: 사용자에게 시각 의도 4가지 묻기 — 어휘 / 스코프 / 디자인 시스템 / reference
2. **G3 (검증 단계)**: 결과 화면을 캡처하고 Agent 서브에이전트가 의도와 비교 → fail이면 커밋 차단

핵심 원칙:
- ✅ Anthropic API 키 **불필요** (Agent는 사용자 Claude Code 세션 모델 사용)
- ✅ Playwright MCP **선택적** (없으면 사용자 수동 캡처 또는 코드 분석 폴백)
- ✅ 모든 Claude Code 사용자 보장 (키 없어도, MCP 없어도 동작)

---

## 자동 발화 시점

다음 모두 만족하면 게이트가 자동 발화한다:

| 게이트 | 발화 조건 | 호출 위치 |
|--------|---------|---------|
| **G1** | `/nova:plan` 호출 + UI 파일 변경 후보 감지 (`detect-ui-change.sh --planning` → `likely_ui:true`) | `plan.md` step 5 |
| **G3** | `/nova:run` 또는 `/nova:check` Phase 검증 PASS + UI 변경 감지 + `intent.json` 존재 | `run.md` Phase 5.5b / `check.md` Phase 3.5 |
| **G3 (orchestrator)** | `/nova:auto`의 Phase 5.5b (intent.json 존재 시) | `orchestrator/SKILL.md` |

**비-UI 작업**: detect-ui-change.sh가 `likely_ui:false` 반환 → 게이트 발화 X (false positive 방지).

---

## 절차 — UI 작업 한 사이클

### 1. `/nova:plan` 단계 (G1)

```
> /nova:plan 사용자 프로필 페이지 새로 만들기 — shadcn 스타일

[Nova] UI 변경 가능성 감지 → 시각 의도 캡처 시작

[1/4] 디자인 어휘 — 어떤 트렌드/시스템?
  자동 추천: shadcn  [prompt에서 감지]
  > [Enter for default]

[2/4] 스코프 — 어디까지?
  자동 감지 파일: 0개 (신규)
  > screen

[3/4] 디자인 시스템?
  감지: tailwind.config.ts (Tailwind preset, 토큰 18개)
  > use-existing

[4/4] 시각 reference (선택)
  > (Enter)

[Nova] Intent captured: docs/plans/profile-page-intent.json
```

`--quick` 옵션 — 1초 컷 (default로 즉시 freeze):

```
bash scripts/capture-visual-intent.sh --slug profile-page --quick
```

### 2. 구현

`/nova:run` 또는 직접 코딩.

### 3. `/nova:run` 단계 (G3)

```
> /nova:run

Phase 1~4 PASS

Phase 5.5a: ux-audit Lite (코드 분석) → PASS

Phase 5.5b: G3 Visual Self-Verify
  [Nova] intent.json 발견 — 시각 검증 시작
  [Nova] Playwright MCP 미연결 → 폴백
  [Nova] 수동 스크린샷 경로를 입력하세요 (Enter로 코드 분석 폴백):
  > ~/Desktop/profile-screenshot.png

  → Agent 서브에이전트(vision) verdict:
     verdict: pass
     overall_score: 88
     strengths: ["shadcn 어휘 잘 적용됨", "tailwind 토큰 일관"]
     mismatches: []

  → 캐시 갱신, 다음 Phase

Verdict: PASS — 커밋 가능
```

### 4. 차단 시나리오

```
Phase 5.5b: G3 Visual Self-Verify
  → Agent verdict:
     verdict: fail
     mismatches:
       - { check_id: vc-001, severity: critical,
           expected: "x 버튼은 ghost 스타일 (shadcn 어휘)",
           observed: "x 버튼이 빨간 사각형 destructive로 강조됨",
           fix_suggestion: "ghost button + neutral color, hover에서만 destructive" }

[Nova] 시각 검증 FAIL — 커밋 차단
[Nova] 옵션: (a) 수정 후 재시도 (b) --skip-visual-verify (c) intent.json 수정
```

---

## FAIL 4종 매핑 — 발생 시 해결

### FAIL 1: `intent.json not found`

**증상**: `bash scripts/visual-self-verify.sh ...` 실행 시 `Error: intent.json not found`

**원인**: G1 캡처가 발화하지 않음 (Plan 단계 스킵 또는 비-UI 작업으로 분류)

**해결**:
```bash
# 수동 캡처 (UI 작업이라면)
bash scripts/capture-visual-intent.sh --slug <plan-slug> --from-prompt "<원본 prompt>"

# 또는 quick 모드
bash scripts/capture-visual-intent.sh --slug <plan-slug> --quick
```

### FAIL 2: `verdict == fail` (critical 1+ 또는 high 2+)

**증상**: G3 검증에서 차단

**원인**: 구현 결과가 의도와 mismatch

**해결**:
1. mismatches 목록의 fix_suggestion 적용
2. 재구현 후 재실행 (`/nova:run`) — 캐시 hash 갱신되어 자동 재검증
3. 의도 자체가 잘못됐다면 `intent.json` 수정 후 재실행

### FAIL 3: 폴백 체인 미완료 (`verdict == degraded`)

**증상**: 차단은 안 되지만 "[Nova] 시각 검증 폴백 모드 — 사용자 수동 확인 권장" 안내

**원인**: Playwright MCP 미설치 + non-interactive 환경 + 사용자 수동 입력 불가

**해결** (선택):
- Playwright MCP 설치 (1차 폴백 활성화)
- 수동 스크린샷 경로 직접 전달: `bash scripts/visual-self-verify.sh --intent ... --screenshots "/path/to/*.png"`
- 또는 그대로 진행 (degraded는 차단 X — 사용자가 시각 직접 확인)

### FAIL 4: false positive (비-UI 작업에서 게이트 발화)

**증상**: 백엔드/유틸 변경인데 G1 캡처 묻기 발생

**원인**: detect-ui-change.sh 휴리스틱 오탐 (드물지만 가능)

**해결**:
- `--skip-visual-verify` 플래그
- 또는 `nova-config.json`:
  ```json
  { "auto": { "visualVerify": false } }
  ```
- 영구 비활성화 시 nova-config.json 권장

---

## Cheatsheet

```bash
# G1: 시각 의도 캡처
bash scripts/capture-visual-intent.sh --slug <slug> --from-prompt "<prompt>"
bash scripts/capture-visual-intent.sh --slug <slug> --quick           # 1초 컷
bash scripts/capture-visual-intent.sh --slug <slug> --non-interactive # CI 모드

# G3: 시각 자가 검증
bash scripts/visual-self-verify.sh --intent docs/plans/<slug>-intent.json
bash scripts/visual-self-verify.sh --intent ... --screenshots "/path/to/*.png"
bash scripts/visual-self-verify.sh --intent ... --mode code-only      # 폴백 직행
bash scripts/visual-self-verify.sh --intent ... --strict-vlm          # opus model
bash scripts/visual-self-verify.sh --intent ... --skip-visual-verify  # opt-out

# 카탈로그 확인
jq '.vocabulary[].key' docs/catalogs/design-vocabulary.json

# 캐시 확인 / 무효화
cat .nova/last-visual-audit.json
rm .nova/last-visual-audit.json    # 강제 재검증

# 영구 비활성화
echo '{"auto":{"visualVerify":false}}' > nova-config.json
```

---

## 외부 의존성 — 모든 사용자 보장 정책

| 의존성 | 필요? | 미보유 시 |
|--------|------|---------|
| **Anthropic API 키** | ❌ 불필요 | Agent 서브에이전트가 Claude Code 세션 모델 자동 사용 |
| **Playwright MCP** | 선택 | 사용자 수동 캡처 (2차) → 코드 분석 (3차) → 안내 (4차) |
| **dev server** | Playwright 사용 시만 | 폴백 시 무관 |

**원칙**: Nova는 모든 Claude Code 사용자가 추가 설정 없이 핵심 가치를 받는 범용 플러그인. 유료 서비스 의존성을 필수로 강제하지 않는다.

---

## 디자인 어휘 카탈로그 (11종)

| key | 이름 | 적합 |
|-----|------|------|
| material-3 | Material Design 3 | Android, Google 생태계, expressive |
| apple-hig | Apple HIG | iOS/macOS, polished, consistent |
| shadcn | shadcn/ui | Tailwind 프로젝트, 미니멀, 접근성 우선 |
| linear | Linear | B2B SaaS, 고밀도, 키보드 우선 |
| vercel | Vercel/Geist | 타이포그래피 강조, Monospace 강세 |
| notion | Notion | 블록 기반, warm neutral, writing-first |
| tailwind-ui | Tailwind UI | Tailwind 공식, 마케팅+app 포괄 |
| radix | Radix UI | unstyled primitives, 접근성 |
| mantine | Mantine | B2B SaaS, 폼/데이터 입력 우수 |
| chakra | Chakra UI | 접근성 우선, props 스타일링 |
| liquid-glass | Apple Liquid Glass (WWDC 2026) | visionOS/iOS 26, glass-morphism |

신규 트렌드 추가는 `docs/catalogs/design-vocabulary.json` PR 또는 `/nova:evolve`로.

---

## 측정 지표 (KPI)

`measurement-spec.md`에 정의:

- `visual_intent_capture_rate` — UI 작업 중 G1 캡처 발화 비율
- `visual_verify_block_rate` — G3에서 fail으로 차단된 비율
- `visual_quick_skip_rate` — `--quick` 사용 비율 (사용자 부담 지표)
- `visual_cache_hit_rate` — 캐시 hit 비율 (재검증 절감)

`bash scripts/publish-metrics.sh`로 baselines 누적 (4주 리츄얼).

---

## 관련 문서

- Spec: `docs/designs/visual-intent-verify.md`
- Plan: `docs/plans/visual-intent-verify.md`
- Research: `docs/research/2026-04-29-ui-ux-gap-rescan.md`
- 규칙: `docs/nova-rules.md` §14
- 카탈로그: `docs/catalogs/design-vocabulary.json`
- 측정: `docs/measurement-spec.md`, `docs/guides/measurement.md`
