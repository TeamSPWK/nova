# [Plan] Single Source of Truth — Nova 메타데이터 자동 동기화

> Nova Engineering — CPS Framework
> 작성일: 2026-04-13
> 작성자: Claude (Nova Evolve)
> Design:

---

## Context (배경)

### 현재 상태

Nova의 "팩트"(커맨드, 스킬, 에이전트, 버전, 규칙)가 최소 4곳에 분산되어 있다:

```
소스 파일 (Single Truth)         수동 복사 대상 (Drift 위험)
─────────────────────────      ──────────────────────────
.claude/commands/*.md    ──→   README.md 커맨드 테이블
.claude/skills/*/SKILL.md ──→  README.md 스킬 테이블
.claude/agents/*.md      ──→   README.md 에이전트 테이블
scripts/.nova-version    ──→   README 배지, plugin.json (✅ bump-version.sh로 자동화)
hooks/session-start.sh   ──→   커맨드 목록 (✅ test-scripts.sh로 검증)
──────────── 외부 프로젝트 ────────────
전체 위 항목             ──→   nova-landing 하드코딩 (❌ 완전 수동, v3.12에서 멈춤)
```

### 왜 필요한가

1. **nova-landing이 v3.12에서 멈춰있다** — 삭제된 커맨드(gap, xv, propose, metrics)가 여전히 표시
2. **README에 스킬 2개 누락** — evolution, ux-audit이 실제 존재하지만 문서화 안 됨
3. **릴리스마다 수동 동기화 부담** — 커맨드 추가 시 최소 4곳 수정 필요
4. **bump-version.sh가 좋은 선례** — 버전은 이미 자동화. 같은 패턴을 확장하면 됨

### 관련 자료
- 기존 자동화: `scripts/bump-version.sh` (버전 3곳 동기화)
- 기존 검증: `tests/test-scripts.sh` (session-start.sh ↔ 커맨드 동기화 검증)
- 랜딩 프로젝트: `../nova-projects/nova-landing/`

---

## Problem (문제 정의)

### 핵심 문제
Nova의 팩트 데이터가 여러 파일에 수동 복사되어 있어, 릴리스마다 동기화가 누락되고 외부 프로젝트(landing)는 완전히 방치된다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | **팩트 추출 부재** | 커맨드/스킬/에이전트 메타데이터를 프로그래밍적으로 추출하는 도구가 없음 | 높음 |
| 2 | **README 수동 관리** | 커맨드/스킬/에이전트 테이블이 하드코딩. 새 항목 추가 시 수동 편집 | 높음 |
| 3 | **외부 프로젝트 단절** | nova-landing이 Nova 레포와 연결 고리가 없음. 수동 확인만 가능 | 높음 |
| 4 | **릴리스 체크리스트 과부하** | CLAUDE.md의 "커맨드/스킬 추가 체크리스트"가 5단계. 실수 여지 | 중간 |

### 제약 조건
- Nova는 bash 스크립트 기반 (Node.js/Python 런타임 의존 최소화)
- 랜딩은 Next.js SSG (빌드 타임에 데이터 fetch 가능)
- 두 레포는 별개 GitHub 레포 (TeamSPWK/nova, jay-swk/nova-landing)
- CI는 GitHub Actions

---

## Solution (해결 방안)

### 선택한 방안

**"generate-meta.sh → nova-meta.json → README 자동 생성 + 랜딩 자동 fetch + CI dispatch"**

```
┌─ Nova 레포 ──────────────────────────────────┐
│                                               │
│  .claude/commands/*.md ─┐                     │
│  .claude/skills/*/SKILL.md ─┤ generate-meta.sh │
│  .claude/agents/*.md ───┤     │               │
│  scripts/.nova-version ─┘     ▼               │
│                         docs/nova-meta.json   │
│                              │                │
│  bump-version.sh ────────────┤ (자동 호출)     │
│                              ▼                │
│                    README.md 테이블 자동 갱신   │
│                              │                │
│  git push ───────────────────┤                │
│                              ▼                │
│            GitHub Actions: release.yml         │
│                    │                          │
└────────────────────│──────────────────────────┘
                     │ repository_dispatch
                     ▼
┌─ nova-landing 레포 ─────────────────────────┐
│                                              │
│  GitHub Actions: sync.yml                    │
│       │                                      │
│       ▼                                      │
│  fetch nova-meta.json (raw GitHub URL)       │
│       │                                      │
│       ▼                                      │
│  Next.js build (SSG) → GitHub Pages 배포     │
│                                              │
└──────────────────────────────────────────────┘
```

### 대안 비교

| 기준 | A: generate-meta.sh (채택) | B: MCP 서버 API | C: npm 패키지로 공유 |
|------|--------------------------|----------------|-------------------|
| 의존성 | bash + jq (이미 CI에 있음) | Node.js 런타임 | npm publish 필요 |
| 복잡도 | 낮음 | 중간 | 높음 |
| 디버깅 | JSON 파일 직접 확인 | API 호출 디버깅 | 패키지 버전 관리 |
| 랜딩 통합 | raw URL fetch | localhost 불가 | import 가능 |
| **선택** | **채택** | 기각 (로컬 전용) | 기각 (과도한 인프라) |

### 구현 범위

#### 1. `scripts/generate-meta.sh` 생성
- [ ] `.claude/commands/*.md`에서 frontmatter(description) + 파일명 추출
- [ ] `.claude/skills/*/SKILL.md`에서 frontmatter(name, description) 추출
- [ ] `.claude/agents/*.md`에서 frontmatter(name, description, tools) 추출
- [ ] `scripts/.nova-version`에서 버전 읽기
- [ ] `docs/nova-meta.json` 생성

#### 2. `bump-version.sh` 확장
- [ ] 버전 범프 후 `generate-meta.sh` 자동 호출
- [ ] 생성된 `nova-meta.json`을 git add에 포함

#### 3. README 자동 갱신 (선택)
- [ ] `generate-meta.sh`가 README의 커맨드/스킬/에이전트 테이블을 자동 교체
- [ ] `<!-- AUTO-GEN:commands -->` ~ `<!-- /AUTO-GEN:commands -->` 마커 방식

#### 4. GitHub Actions — Nova 릴리스 시 랜딩 dispatch
- [ ] `.github/workflows/release.yml`에 dispatch 이벤트 추가
- [ ] nova-landing에 `.github/workflows/sync.yml` 생성

#### 5. nova-landing — JSON 기반 렌더링
- [ ] `app/lib/nova-meta.ts` — 빌드 타임 JSON fetch
- [ ] `CommandsSection.tsx` — 하드코딩 제거, JSON 기반 렌더링
- [ ] `NavBar.tsx` — 버전 배지 동적화
- [ ] `HeroSection.tsx` — 통계 동적화

#### 6. 테스트 강화
- [ ] `test-scripts.sh`에 `nova-meta.json` 유효성 검증 추가
- [ ] README 마커 존재 여부 검증

### 검증 기준
1. `bash scripts/generate-meta.sh` 실행 후 `docs/nova-meta.json`이 현재 커맨드/스킬/에이전트를 정확히 반영
2. `bump-version.sh` 실행 시 `nova-meta.json`이 자동 갱신
3. `bash tests/test-scripts.sh` 통과
4. nova-landing이 빌드 시 JSON을 fetch하여 동적 렌더링

---

## Sprints

예상 수정 파일: 10+ → 스프린트 분할

| Sprint | 기능 단위 | 예상 파일 | 의존성 | Done 조건 |
|--------|----------|----------|--------|----------|
| 1 | generate-meta.sh + nova-meta.json | `scripts/generate-meta.sh`, `docs/nova-meta.json`, `bump-version.sh`, `tests/test-scripts.sh` | 없음 | `bash scripts/generate-meta.sh` → 유효한 JSON, 커맨드 12개 + 스킬 7개 + 에이전트 5개 |
| 2 | README 자동 갱신 | `README.md`, `README.ko.md`, `scripts/generate-meta.sh` 확장 | Sprint 1 | README에 마커 삽입 + generate-meta.sh가 테이블 자동 교체 + 테스트 통과 |
| 3 | GitHub Actions + nova-landing 연동 | `.github/workflows/release.yml`, nova-landing 4~5개 파일 | Sprint 1 | Nova 릴리스 → landing 자동 리빌드 → 버전/커맨드 동기화 확인 |

---

## X-Verification (다관점 수집)

> nova-meta.json 스키마는 단순하므로 다관점 수집 불필요.
> Sprint 3(GitHub Actions cross-repo dispatch)는 보안 고려 필요: PAT vs GITHUB_TOKEN 권한.
