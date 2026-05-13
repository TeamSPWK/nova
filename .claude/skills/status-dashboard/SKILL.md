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
./scripts/render-status.sh --auto-bootstrap --open
```

### Step 2: 결과 분기

| JSON `mode` / `minimal` | 동작 |
|------------------------|------|
| `roadmap` | ✅ 완료. Phase/Sprint/Drift 1줄 요약 보고 |
| `phase1` + `minimal:false` | ✅ Phase 1 호환. plan frontmatter 기반 dashboard 작동 |
| `phase1` + `minimal:true` | → `--auto-bootstrap`이 §22 흐름 자동 진입 |

### Step 3 (자동): minimal → 자동 부트스트랩

`render-status.sh --auto-bootstrap`이 자동 처리:
1. `init-roadmap.sh --llm` 자료 수집 (NOVA-STATE + git log + plans)
2. Agent(general-purpose) subagent — 외부 API 키 0 (visual-self-verify 패턴 일관)
3. `/tmp/ROADMAP-{slug}-draft.md` 작성 → build 재실행
4. **자동 commit 0건** — 사용자 검수 후 명시적 commit

### Step 4: 사용자 보고

- HTML 경로 + drift verdict (green/amber/red/unknown)
- minimal 자동 부트스트랩 발생 시: draft 경로 + 검수·채택 안내
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
