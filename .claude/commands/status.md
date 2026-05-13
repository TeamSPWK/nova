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
./scripts/render-status.sh --auto-bootstrap --open
```

- 다른 도구 검토·발견 단계 **skip**. 위 명령 그대로 실행.
- `--auto-bootstrap`: minimal 감지 시 Step 3 자동 진입 (Phase 4+).
- `--open`: macOS open / Linux xdg-open으로 브라우저 자동.

## Step 2 — 결과 분류 + 사용자 보고

build/render JSON의 `mode`·`minimal` 필드로 분기:

| 조건 | 동작 |
|------|------|
| `mode: roadmap` | ✅ 완료. HTML 경로 + Phase/Sprint 한 줄 요약 보고. |
| `mode: phase1` + `minimal: false` | ✅ Phase 1 호환 동작. plan frontmatter 기반 dashboard. |
| `mode: phase1` + `minimal: true` | → **Step 3 자동 부트스트랩 강제 진입** |

## Step 3 — 자동 부트스트랩 (minimal 떨어진 경우만)

`--auto-bootstrap` 옵션이 `render-status.sh` 내부에서 자동 실행. 단계:

1. `./scripts/init-roadmap.sh --llm` 자동 호출 → `.nova/init-input.json` 자료 수집
2. Agent(general-purpose) subagent 호출 → `/tmp/ROADMAP-{slug}-draft.md` 작성
3. `./scripts/render-status.sh --roadmap /tmp/ROADMAP-{slug}-draft.md --open` 재실행
4. 사용자 보고:
   ```
   ✅ 임시 ROADMAP draft로 풍부한 dashboard 생성.
   📂 검수 후 채택: mv /tmp/ROADMAP-*-draft.md ROADMAP.md && git add ROADMAP.md && git commit
   ```

**자동 commit 0건**. 사용자 명시적 commit이 있을 때까지 ROADMAP.md 변경 0.

---

# 보조 — 사용자가 직접 호출

위 강제 흐름은 Claude(메인) 경유 시. 사용자가 명령 줄에서 직접:

```bash
nova-status          # bin/ wrapper — Claude 개입 0, 무조건 표준 강제
```

또는 직접 스크립트:

```bash
./scripts/render-status.sh --auto-bootstrap --open
```

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
