---
description: "프로젝트 현황(Phase·Sprint·그룹 진행률) + drift 알람을 stand-alone HTML로 한 눈에 본다. 노션/wiki sync 불필요 — git이 진실원. — MUST TRIGGER: AI에게 위임 후 점검, 멀티 프로젝트 상태 확인, 로드맵 drift 점검 필요 시. **자율 해석 금지** — Step 1 무조건 실행."
description_en: "View project status (Phase/Sprint/group progress) + drift alerts as a stand-alone HTML. — MUST TRIGGER: status check after delegation, multi-project glance, roadmap drift audit. STRICT FLOW — no autonomous reinterpretation."
---

# /nova:status (STRICT FLOW)

너는 **다음 흐름을 순서대로 강제 실행**한다. 자율 해석·우회·대체 금지.
사용자가 `/nova:status` 입력한 의도 = **Nova 표준 HTML 대시보드 생성**. 다른 의도로 해석하지 않는다.

---

# 🚫 금지 행동 (BLOCKED)

다음 행동은 사용자 의도 위반이다. **절대 수행하지 않는다**:

1. **NOVA-STATE.md만 읽고 텍스트 요약으로 대체** — 사용자는 HTML dashboard를 요청했다. 텍스트 요약 X.
2. **프로젝트 자체 dashboard 도구로 우회** — `dashboard/build_static.py`, `Makefile dashboard` 타겟, `web/app/status/` 등 발견해도 **무시**. Nova 표준 강제.
3. **minimal mode HTML 만들고 멈춤** — minimal 떨어지면 **Step 3 자동 부트스트랩 강제 진입**.
4. **`/nova:status` 호출에 다른 도구 제안하며 멈춤** — "프로젝트에 더 좋은 도구가 있어요" 같은 답변 금지.

예외: 사용자가 명시적으로 `--use-project-tool` 옵션 또는 자연어로 "프로젝트 자체 도구 사용해줘" 요청한 경우만.

---

# ✅ 강제 실행 흐름

## Step 1 (필수, skip 불가)

```bash
nova-status
```

- Claude Code가 플러그인 `bin/`을 Bash tool PATH에 자동 등록. cwd 무관 작동.
- PATH 미반영(오래된 세션) 시 폴백: `bash "$NOVA_PLUGIN_ROOT/bin/nova-status"` — SessionStart hook이 export.
- 다른 도구 검토·발견 단계 **skip**. 위 명령 그대로 실행.
- `nova-status` wrapper가 내부적으로 `--auto-bootstrap --open` 강제 — minimal 감지 시 Step 3 자동 진입.

## Step 2 — 결과 분류 + 사용자 보고

build/render JSON의 `mode`·`minimal` 필드로 분기:

| 조건 | 동작 |
|------|------|
| `mode: roadmap` | ✅ 완료. HTML 경로 + Phase/Sprint 한 줄 요약 보고. |
| `mode: phase1` + `minimal: false` | ✅ Phase 1 호환 동작. plan frontmatter 기반 dashboard. |
| `mode: phase1` + `minimal: true` | → **Step 3 자동 부트스트랩 강제 진입** |

## Step 3 — 자동 부트스트랩 (minimal 떨어진 경우 — **MUST 자동 진행**)

🚫 **사용자 결정 요청 금지** — 사용자가 `/nova:status`를 호출한 의도 = "dashboard 결과 받기". minimal HTML(빈 껍데기)만 보여주고 멈추면 **사용자 의도 위반**이다. v5.35.6 이후 자율 우회 차단.

### 강제 진행 트리거

`nova-status` 실행 후 stderr에 다음 마커가 출력되면 **무조건 진행**:

```
[CLAUDE_AUTO_CONTINUE]
DRAFT_PATH=...
PLAN_COUNT=...
NEXT_ACTION=spawn_agent_then_rerender
AGENT_TYPE=general-purpose
RERENDER_CMD=...
[/CLAUDE_AUTO_CONTINUE]
```

stderr에 `[CLAUDE_AUTO_CONTINUE]`가 보이면 메인 Claude는 **다음을 단일 응답 내에 자동 수행** (사용자 결정 요청 없음, 사이드 보고 없음):

### Step 3.A — Agent(general-purpose) spawn (필수)

stderr `[2/3]` 블록의 Agent prompt를 그대로 추출해 `Agent` tool로 spawn:

```
Agent(
  description="ROADMAP draft 작성",
  subagent_type="general-purpose",
  prompt=<stderr [2/3] 블록의 prompt 그대로 + 다음 추가>:
    - 출력 파일: ${DRAFT_PATH} (stderr 마커값)
    - PLAN_COUNT > 0이면 SOT 충돌 경고 섹션 draft 본문에 강제 포함
    - title 필수, blocked는 외부 trigger 한정, ⚠️ unsure rule 준수
    - 자동 commit 절대 금지
)
```

### Step 3.B — Agent 완료 후 render-status 재실행 (필수)

Agent가 draft를 작성하면 마커의 `RERENDER_CMD` 그대로 실행:

```bash
bash "$NOVA_PLUGIN_ROOT/scripts/render-status.sh" --roadmap ${DRAFT_PATH} --open --no-bootstrap
```

(`--no-bootstrap`은 무한 루프 차단)

### Step 3.C — 사용자 보고 (최종)

풍부 모드 HTML 갱신 완료 후 사용자에게 한 번에 보고:

```
✅ Dashboard 생성 완료 — mode: roadmap

- HTML: .nova/status/index.html (브라우저 자동 오픈)
- Draft: ${DRAFT_PATH} (사용자 검수 대기)
- Phase {N}개 · current_phase: {X} · blocked: {N}건
- SOT 결정 (PLAN_COUNT > 0 시): default C 자동 적용됨 — A/B 변경은 검수 후 선택

다음 단계 (자동 commit 0건):
  검수: cat ${DRAFT_PATH}
  채택: mv ${DRAFT_PATH} ROADMAP.md && git add && git commit
```

### Step 3.D — SOT 충돌 시 default 자동 선택 (PLAN_COUNT > 0)

stderr 마커에 `PLAN_COUNT > 0`이면 메인 Claude는 **dashboard 결과를 무조건 제공한다**. A/B/C 중 선택을 사용자에게 미루지 않고, **default C**(draft 검수 + 임시 풍부 모드 유지)를 자동 적용:

| 옵션 | 파괴성 | 자동 적용 |
|------|--------|----------|
| (A) Plan frontmatter에 phases v1.0 추가 | 기존 Plan 수정 | **사용자 결정 영역** — 자동 X |
| (B) Plan의 마일스톤 표 → ROADMAP 흡수 | 기존 Plan 큰 변경 | **사용자 결정 영역** — 자동 X |
| (C) draft 검수 + 임시 풍부 모드 유지 | 0 (commit 0건, 파일 변경 0) | ✅ **default 자동 적용** |

C 자동 적용 = 사용자에게 dashboard 결과 즉시 보여줌 + draft로 검수 가능 + 채택 여부는 검수 후 결정. 이게 사용자 의도("결과까지 나와야 한다") 충족.

A/B는 commit/파일 수정을 동반하므로 사용자 명시 결정이 있을 때만. Claude가 자율로 A/B 선택 금지.

**자동 commit 0건**은 유지. 사용자 결정 = "최종 채택(A/B/mv) 여부"만이고, draft 작성·dashboard 갱신·default C 적용은 **자동**.

### 금지 패턴 (v5.35.6 이전 사고 사례)

다음은 모두 사용자 의도 위반이다 — 절대 금지:

1. ❌ minimal HTML 생성 후 "다음 단계는 사용자가 결정" 식으로 멈춤
2. ❌ "Agent spawn할까요?" 식의 결정 요청
3. ❌ stderr `[2/3]` 안내만 사용자에게 보여주고 끝
4. ❌ SOT 충돌 발견 시 dashboard 생성 자체를 보류
5. ❌ `--no-bootstrap` 누락으로 재실행 시 무한 루프

SOT 충돌 안내는 **사용자 결정 항목**이지만, dashboard 생성 자체는 그것과 무관하게 **무조건 자동**이다.

### Phase status 의미론 (Agent에게 위임 시 필수 주입)

draft 작성 Agent에게 status 4값의 의미를 반드시 명시한다 — 그렇지 않으면 dependency-pending phase까지 `blocked`로 표기돼 시각적으로 과도하게 빨갛게 나옴(v5.35.2 이전 사례):

| status | 의미 | 사용 시점 |
|--------|------|----------|
| `done` | Exit criteria 통과 + 사용자 검수 완료 | 완료된 phase |
| `in_progress` | 현재 작업 phase | 동시 1개 권장 (frontmatter `current_phase`와 일치) |
| `pending` | **선행 phase 미완료**로 인한 단순 순서 대기 | dependency-blocked는 전부 여기 |
| `blocked` | **외부 trigger**(승인·사고·사람·외부 시스템) 필요 | 진짜 위험 신호 — 빨간 점 표시 |

> ⚠️ "blocked by Phase X" 같은 의존성은 `blocked`가 아닌 `pending`이다. `blocked`는 외부 trigger 한정.

---

# 보조 — 사용자가 직접 호출

위 강제 흐름은 Claude(메인) 경유 시. 사용자가 명령 줄에서 직접:

```bash
# 일반 셸: 사용자 PATH에 plugin bin이 등록되어 있으면
nova-status

# 절대경로 (어디서든 동작)
bash ~/.claude/plugins/marketplaces/*/bin/nova-status
```

`bin/nova-status` wrapper가 내부적으로 `scripts/render-status.sh --auto-bootstrap --open`을 강제 실행. Claude 개입 0, 표준 우회 불가.

---

# Drift 추적 활성화 (선택)

commit 본문에 tag 명시 → drift 5분류 분석:

```
feat: <subject>

Plan: <plan_id>
Goal: <goal_id>   # 선택
```

CLAUDE.md 룰 1줄로 AI(Claude/Codex/Cursor) 자동 동참 가능.

---

# Outputs

| 산출물 | 위치 | 용도 |
|--------|------|------|
| HTML | `.nova/status/index.html` (default) | 사용자가 브라우저에서 본다 |
| JSON | `--data` 옵션으로 분리 가능 | CI · 외부 도구 연동 |

---

# 관련 자산

- 데이터 계약: `docs/designs/status-dashboard.md` §1~§24
- 사용자 가이드: `docs/guides/status-dashboard.md`
- Skill: `skills/status-dashboard/SKILL.md`
- 스크립트: `scripts/{build,render}-status.sh` + `scripts/{init-roadmap,enrich-plans}.sh`
- bin 진입점: `bin/nova-status` (Claude 우회 불가, Phase 4+)

---

# Step 1 실행 → 끝.

사용자에게 "어떻게 할까요?" 또는 "다른 도구도 있어요" 묻지 않는다.
**무조건 Step 1 실행 → 결과 보고**.
