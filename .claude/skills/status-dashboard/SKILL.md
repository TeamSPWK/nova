---
name: status-dashboard
description: "프로젝트 현황(Phase·Sprint·그룹 진행률) + 로드맵 drift 알람을 stand-alone HTML로 본다. — MUST TRIGGER: /nova:status 호출, 사용자가 '현황 보여줘'·'어디까지 됐어'·'drift 확인'을 요청할 때, AI에게 위임 후 결과 점검 필요할 때, 멀티 프로젝트 상태를 한 눈에 보고 싶을 때."
description_en: "Render project status (Phase/Sprint/group progress) + roadmap drift alerts as a stand-alone HTML dashboard. — MUST TRIGGER: /nova:status invocation, user asks for project status/progress, post-agent-delegation audit, multi-project glance."
user-invocable: false
---

# Nova Status Dashboard

Plan frontmatter(SOT) + git log를 결정론적으로 파싱하여 토스식 카드 HTML 대시보드를 만든다.
사용자가 손으로 갱신할 필드는 0개. 진행률은 git/파일시스템에서 자동 파생.

## 적용 규칙

- `docs/designs/status-dashboard.md` (§4 frontmatter / §5 JSON / §6 drift 5분류 / §7 HTML 템플릿 / §8 graceful degradation)
- `docs/guides/status-dashboard.md` (사용자 가이드 — TL;DR · 절차 · FAIL 시 · cheatsheet)

## 실행 흐름

### Step 1: 호출

```bash
./scripts/render-status.sh --plan <plan_path> --open    # 한 번에 build + render + 브라우저
./scripts/render-status.sh --open                         # plan 자동 발견
./scripts/build-status.sh --plan <plan_path> --out out.json   # JSON만
```

### Step 1.4: 기존 plans 자동 enrich (Phase 3)

`docs/plans/*.md`에 frontmatter v1.1 (`parent_phase`/`sprint_id`/`status`) 일괄 자동 추가:

```bash
./scripts/enrich-plans.sh --collect       # 자료 수집
# (메인 Claude → Agent subagent → output-N.json)
./scripts/enrich-plans.sh --dry-run        # drafts 생성 (안전)
./scripts/enrich-plans.sh --apply --force  # 원본 prepend + .bak
```

5중 안전 가드 — 본문 0 byte 변경 / 기존 frontmatter skip / .bak 자동 / batch 10 / 자동 commit 0.

### Step 1.5: ROADMAP.md 없을 때 (Phase 2 init wizard)

ROADMAP.md 부재 + 사용자가 dashboard 호출 → init wizard 안내:

```bash
./scripts/init-roadmap.sh --blank   # 빈 템플릿 (사용자가 손으로 채움)
./scripts/init-roadmap.sh --scan    # docs/plans/* parent_phase 추출 (결정론)
./scripts/init-roadmap.sh --llm     # 자료 수집 → Agent subagent (외부 API 0)
```

LLM 모드 흐름:
1. `init-roadmap.sh --llm` 호출 → `.nova/init-input.json` 자료 수집
2. Agent(general-purpose) subagent 호출 — prompt: "Design §12 + init-input.json 기반 ROADMAP.md.draft 작성. ⚠️ unsure rule 준수"
3. Agent가 draft 작성 → 사용자 검수 → 명시적 `git commit`
4. **자동 commit 0건 보장**

### Step 2: frontmatter 자가 점검

호출 후 stdout warnings를 사용자에게 1줄 요약으로 전달한다.
주요 위반:
- `plan_id` 누락 → minimal mode 진행
- `groups[].target ≤ 0` → 해당 group 표시 안 됨
- `phases id 중복` → 첫 항목만 사용

### Step 3: drift verdict 해석

| verdict | 의미 | 후속 |
|---------|------|------|
| green | drift 30% 미만 — 정렬 양호 | 진행 |
| amber | 30~70% — 검토 필요 | drifted commits 리스트 확인 |
| red | 70%+ — 즉시 사용자 개입 | 작업 중단, drift 원인 분석 |
| unknown | tag_missing 100% — commit 컨벤션 미적용 | CLAUDE.md 룰 추가 안내 |

### Step 4: 후속 작업 제안

- drift 발견 시 → drifted commits를 사용자에게 보고 + 의도 재정의 또는 plan goals 수정 제안
- minimal mode → 가이드 §부트스트랩 링크 제공
- frontmatter 위반 → 구체적 위반 항목 + 수정 위치 안내

## 결정론 보장

- 동일 frontmatter + 동일 git 상태 → byte-identical JSON (generated_at 제외)
- YAML 파싱: PyYAML (frontmatter 정규식 추출 후)
- glob: 자체 fast-glob 패턴 (negation `!prefix` 지원)
- git log: `--no-merges` + commit tag 정규식 (`^Plan:\s*(...)$`, `^Goal:\s*(...)$`)
- 5분류 매핑: `docs/designs/status-dashboard.md` §6.3 의사코드 글자 그대로

## file:// 보장

HTML은 외부 fetch 0건:
- Tailwind는 Play CDN `<script src>` 1줄 (CDN fetch는 file://에서도 작동)
- 데이터는 `<script>const DATA={...}</script>` inline 임베드
- fetch/XHR/WebSocket 0회

## 관련 커맨드

- `/nova:status` — 진입점
- `/nova:next` — 다음 커맨드 추천 (drift 점수 1줄 표시)
- `/nova:plan` — frontmatter v1.0 스키마와 짝
- `context-chain` 스킬 — NOVA-STATE.md 세션 맥락 (drift와 별개 차원)
