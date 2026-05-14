---
name: status-dashboard
description: "프로젝트 현황(Phase·Sprint·그룹 진행률) + 로드맵 drift 알람을 stand-alone HTML로 본다. — MUST TRIGGER: /nova:status 호출, 사용자가 '현황 보여줘'·'어디까지 됐어'·'drift 확인' 요청 시, AI 위임 후 결과 점검 필요할 때. **자율 우회 금지** — 프로젝트 자체 dashboard 도구·NOVA-STATE 텍스트 요약으로 대체 행위 차단."
description_en: "Render project status as stand-alone HTML dashboard. — MUST TRIGGER: /nova:status invocation, user asks for project status. STRICT — do NOT bypass to project-local tools or substitute with text summaries."
user-invocable: false
---

# Nova Status Dashboard (STRICT)

너는 `/nova:status` 호출 시 **다음 흐름을 순서대로 강제 실행**한다. 자율 해석 금지.
사용자 의도 = **Nova 표준 HTML 대시보드 생성**. 다른 의도로 우회하지 않는다.

## 🚫 금지 행동 (Claude 우회 차단)

다음 행동은 사용자 의도 위반이다:

1. **NOVA-STATE.md만 읽고 텍스트 요약으로 대체** — 사용자는 HTML 요청 (텍스트 답변 X)
2. **프로젝트 자체 dashboard 도구로 우회** — `dashboard/build*.py` / `Makefile dashboard` / `web/app/status/` 발견해도 무시
3. **minimal mode HTML 만들고 멈춤** — `--auto-bootstrap`이 자동 진화 강제
4. **"이런 대안 있어요" 제안하며 멈춤** — Step 1 무조건 실행 후 결과 보고

예외: 사용자가 명시적으로 자체 도구를 요청한 경우.

## ✅ 실행 흐름 (STRICT)

### Step 1: 무조건 실행

```bash
nova-status
```

Claude Code가 플러그인 `bin/`을 Bash tool PATH에 자동 등록하므로 cwd 무관 작동. `bin/nova-status` wrapper가 내부적으로 `--auto-bootstrap --open` 강제.

PATH 미반영(오래된 세션) 폴백: `bash "$NOVA_PLUGIN_ROOT/bin/nova-status"` — SessionStart hook이 `$CLAUDE_ENV_FILE`을 통해 export.

### Step 2: 결과 분기

| JSON `mode` / `minimal` | 동작 |
|------------------------|------|
| `roadmap` | ✅ 완료. Phase/Sprint/Drift 1줄 요약 보고 |
| `phase1` + `minimal:false` | ✅ Phase 1 호환. plan frontmatter 기반 dashboard 작동 |
| `phase1` + `minimal:true` | → `--auto-bootstrap`이 §22 흐름 자동 진입 |

### Step 3 (MUST 자동): minimal → 자동 부트스트랩

`render-status.sh --auto-bootstrap`이 자동 처리하며, **stderr에 `[CLAUDE_AUTO_CONTINUE]` 마커가 출력되면 메인 Claude는 무조건 다음 단계를 단일 응답 내에 자동 수행** (사용자 결정 요청 없음):

1. `init-roadmap.sh --llm` 자료 수집 (NOVA-STATE + git log + plans) — 자동
2. **Agent(general-purpose) spawn** — stderr `[2/3]` 블록의 prompt 그대로 사용 (사용자 결정 요청 X)
3. Agent가 `/tmp/ROADMAP-{slug}-draft.md` 작성 (slug = `[CLAUDE_AUTO_CONTINUE]`의 `DRAFT_PATH` 값)
4. **`render-status.sh --roadmap {DRAFT_PATH} --open --no-bootstrap` 재실행** — 풍부 모드 HTML 갱신
5. **자동 commit 0건** — 사용자 검수 후 명시적 commit

🚫 minimal HTML(빈 껍데기)만 사용자에게 보여주고 멈추면 **사용자 의도 위반**이다. 결과(풍부 모드 dashboard)까지 무조건 자동.

### Step 3.5 (SOT 충돌 시): default 자동 선택

stderr 마커 `PLAN_COUNT > 0`이면 docs/plans/* SOT가 이미 존재. A/B/C 중:
- (A) Plan frontmatter 수정, (B) Plan 마일스톤 ROADMAP 흡수 — 파괴적 → 사용자 결정 영역
- **(C) draft 검수 + 임시 풍부 모드 유지 — 자동 default 적용**

Claude는 무조건 (C)를 자동 적용해 dashboard 결과를 즉시 제공한다. A/B로 변경하려면 사용자가 명시 요청.

### Step 4: 사용자 보고 (한 번에, dashboard 완료 후)

- HTML 경로 + drift verdict (green/amber/red/unknown)
- Phase 수 + current_phase + blocked 건수
- minimal 자동 부트스트랩 발생 시: draft 경로 + default C 적용 안내 + A/B 변경 옵션
- warnings 1줄 요약

## drift verdict 해석

| verdict | 의미 | 후속 |
|---------|------|------|
| green | drift < 30% | 진행 |
| amber | 30~70% | drifted commits 검토 |
| red | 70%+ | 즉시 사용자 개입 |
| unknown | tag_missing 100% | CLAUDE.md commit convention 안내 |

## 관련 자산

- 데이터 계약: `docs/designs/status-dashboard.md` §1~§24
- 사용자 가이드: `docs/guides/status-dashboard.md`
- 커맨드: `commands/status.md` (STRICT 톤)
- bin 진입점: `bin/nova-status` (Claude 개입 없이 사용자 직접 호출)
- 스크립트: `scripts/{build,render}-status.sh` + `scripts/{init-roadmap,enrich-plans}.sh`

## 결정론 보장

- 동일 frontmatter + 동일 git 상태 → byte-identical JSON (generated_at 제외)
- 외부 API 호출 0건 (LLM은 Claude Code 세션 모델 Agent subagent)
- HTML 외부 fetch 0건 (Tailwind Play CDN + inline JSON, file:// 작동)
