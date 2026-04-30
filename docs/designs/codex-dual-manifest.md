# [Design] Codex CLI 듀얼 매니페스트 지원

> Nova Engineering — CPS Framework
> 작성일: 2026-04-15
> 제약: Claude 사용자 사이드이펙트 0
> 관련 이슈: TeamSPWK/nova#3

---

## Context (설계 배경)

### 현재 상태

Nova는 Claude Code 전용 플러그인이다. 배포 구조:

| 파일 | 역할 |
|------|------|
| `.claude-plugin/plugin.json` | Claude 플러그인 매니페스트 |
| `.claude-plugin/marketplace.json` | Claude 마켓플레이스 등록 |
| `.mcp.json` | Claude용 MCP 설정 (`${CLAUDE_PLUGIN_ROOT}` 환경변수 사용) |
| `hooks/session-start.sh` | Claude SessionStart 훅 — 10개 규칙 자동 주입 |
| `.claude/commands/*.md` | 슬래시 커맨드 12개 |
| `.claude/agents/*.md` | 전문 서브에이전트 5종 |
| `.claude/skills/*/SKILL.md` | 복합 스킬 7개 |

### 목표

Codex CLI 사용자도 Nova를 설치·활용할 수 있도록 **듀얼 매니페스트**를 추가한다.
Phase 1 범위: skills 7개 + MCP만 Codex에서 동작.
commands/agents 이식은 Phase 2로 연기.

### 설계 원칙

1. **Claude 사용자 사이드이펙트 0** — 기존 파일 수정 금지
2. **최소 침습 추가** — 신규 파일만, 기존 구조 변경 없음
3. **경로 공유 우선** — 가능하면 skills 디렉토리 중복 없이 공유
4. **불확실한 환경변수는 명시적 경고** — 실측 전까지 보수적으로 설계

---

## Problem (설계 과제)

### 기술적 과제

| # | 과제 | 복잡도 | 의존성 |
|---|------|--------|--------|
| 1 | Codex 매니페스트 포맷 준수 | 낮음 | 없음 |
| 2 | MCP 경로 문제 (`${CLAUDE_PLUGIN_ROOT}` Codex 미지원 가능성) | 중간 | 없음 |
| 3 | skills 경로 공유 (symlink vs 직접 지정) | 낮음 | 없음 |
| 4 | bump-version.sh 동기화 대상 확장 | 낮음 | 과제#1 |
| 5 | release.sh bump 커밋 대상 확장 | 낮음 | 과제#4 |
| 6 | 테스트 추가 (Codex 매니페스트 유효성) | 낮음 | 과제#1 |
| 7 | README 구조 — Codex 설치 가이드 + 손실 경고 | 낮음 | 없음 |

### 기존 시스템과의 접점

- `scripts/bump-version.sh` — `.codex-plugin/plugin.json` version 필드 동기화 추가 필요
- `scripts/release.sh` — Step 4 bump 커밋 대상에 `.codex-plugin/plugin.json` 추가 필요
- `tests/test-scripts.sh` — Codex 매니페스트 검증 테스트 추가
- `README.md` / `README.ko.md` — Codex 설치 섹션 추가

---

## Solution (설계 상세)

### 아키텍처

```
nova/
├── .claude-plugin/          ← 기존 Claude 매니페스트 (수정 금지)
│   ├── plugin.json
│   └── marketplace.json
├── .codex-plugin/           ← 신규 (Codex 전용)
│   ├── plugin.json          ← 신규
│   └── .mcp.json            ← 신규 (Codex용 MCP, 상대경로)
├── .mcp.json                ← 기존 Claude용 (수정 금지, ${CLAUDE_PLUGIN_ROOT} 사용)
└── .claude/
    └── skills/              ← Claude + Codex 공유 (경로 직접 지정)
        ├── evaluator/SKILL.md
        ├── orchestrator/SKILL.md
        └── ...
```

### D1. Codex용 .mcp.json 위치와 내용

**결정: `.codex-plugin/.mcp.json` 신규 생성**

근거:
- 루트 `.mcp.json`은 `${CLAUDE_PLUGIN_ROOT}` 환경변수를 사용한다. Codex에서 이 변수가 동작하는지 공식 문서에 명시가 없다. 실측 전까지 독립 파일을 두는 것이 안전하다.
- Codex가 `.codex-plugin/` 내 `.mcp.json`을 읽는다는 공식 명세는 아직 없다. 따라서 **사용자가 Codex 설치 시 `~/.codex/config.toml`에 수동 등록하는 방식을 병행 안내**한다.

**경로 전략:**

| 방안 | 내용 | 트레이드오프 |
|------|------|------------|
| **A. 상대경로 (채택)** | `"args": ["./mcp-server/dist/index.js"]` — Codex가 plugin root 기준 상대경로를 지원한다고 가정 | 동작 여부 불확실, Phase 3에서 실측 |
| B. 절대경로 하드코딩 | `"args": ["/Users/xxx/nova/mcp-server/dist/index.js"]` | 배포 불가, 개인 환경에만 적용 |

**채택: 방안 A + Phase 3 실측 의무화**

`.codex-plugin/.mcp.json` 내용:

```json
{
  "mcpServers": {
    "nova": {
      "type": "stdio",
      "command": "node",
      "args": ["./mcp-server/dist/index.js"]
    }
  }
}
```

실측 실패 시 폴백: `~/.codex/config.toml` `[mcp_servers.nova]` 블록으로 절대경로 등록 안내.

### D2. skills 경로 공유 방식

**결정: `.codex-plugin/plugin.json`의 `skills` 필드에 `./.claude/skills/` 직접 지정**

근거:
- symlink(`skills` -> `.claude/skills`)가 Codex 환경에서 추종되는지 불확실하므로, symlink 의존 없이 실제 경로를 명시한다.
- Claude는 `.claude/skills/`를 직접 읽으므로 경로 충돌 없음.

### D3. Codex 마켓플레이스 엔트리

**결정: Phase 1에서는 `.codex-plugin/plugin.json`만 추가. `.agents/plugins/marketplace.json`은 작성하지 않는다.**

근거: Codex 공식 publishing이 "coming soon" 상태. 과잉 설계 지양. 사용자는 git clone + 로컬 경로로 설치.

### D4. README 구조

**결정: 기존 "Install / Update / Remove" 섹션 아래에 "Codex CLI (Beta)" 서브섹션 추가**

- AUTO-GEN 마커 영역 밖에 배치 (generate-meta.sh 오작동 방지)
- session-start.sh 손실을 블록인용 경고로 명시
- `~/.codex/config.toml` 수동 등록 폴백 안내 포함

### D5. bump-version.sh 영향

**결정: `.codex-plugin/plugin.json`의 version도 동기화 대상에 포함**

`bump-version.sh` 수정 내용 (기존 `# 3. plugin.json` 블록 이후에 추가):

```bash
# 3-1. .codex-plugin/plugin.json (있을 경우)
CODEX_PLUGIN="$ROOT/.codex-plugin/plugin.json"
if [[ -f "$CODEX_PLUGIN" ]]; then
  sedi "s/\"version\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"version\": \"$NEW_VERSION\"/" "$CODEX_PLUGIN"
  echo "  ✅ .codex-plugin/plugin.json"
fi
```

`release.sh` Step 4 수정 — bump 커밋 대상에 `.codex-plugin/plugin.json` 추가.

### D6. tests/test-scripts.sh

**결정: Codex 매니페스트 검증 테스트 5개 추가 → 169 + 5 = 174개**

- 섹션 5-1 신규: Codex 매니페스트 존재/JSON 유효성/필수 필드 (4개)
- 섹션 6 버전 일관성에 `.codex-plugin/plugin.json` version 동기화 검증 (1개)
- 섹션 9 bump-version.sh 임시 환경 테스트 BUMP_DIR 복사 대상에 `.codex-plugin/` 추가

### D7. ${CLAUDE_PLUGIN_ROOT} 실측 방법

**Phase 3 검증 절차**:

1. Codex 환경에 Nova 설치 (git clone)
2. `mcp-server` 빌드 확인
3. `.codex-plugin/.mcp.json`의 상대경로가 Codex에서 동작하는지 확인 (MCP 서버 로드 로그, 도구 호출)
4. 실패 시:
   - `~/.codex/config.toml` 절대경로 방식으로 전환
   - README의 수동 등록 안내를 Primary 경로로 승격

---

## 구현 체크리스트

### Sprint 1: 파일 추가 (신규 파일만)

| # | 파일 | 동작 | 검증 명령 |
|---|------|------|----------|
| 1.1 | `.codex-plugin/plugin.json` | 신규 | `jq . .codex-plugin/plugin.json` |
| 1.2 | `.codex-plugin/.mcp.json` | 신규 | `jq . .codex-plugin/.mcp.json` |

**`.codex-plugin/plugin.json` 스펙:**
```json
{
  "name": "nova",
  "version": "5.0.2",
  "description": "AI 개발 품질 게이트 — 적대적 코드 리뷰, 멀티 AI 교차검증, 설계-구현 정합성 검증으로 재작업을 제거한다.",
  "author": {
    "name": "Spacewalk Engineering",
    "email": "jay@spacewalk.dev",
    "url": "https://spacewalk.tech"
  },
  "homepage": "https://github.com/TeamSPWK/nova",
  "repository": "https://github.com/TeamSPWK/nova",
  "license": "MIT",
  "skills": "./.claude/skills/",
  "keywords": [
    "quality-gate",
    "adversarial-review",
    "cross-verification",
    "cps",
    "code-review"
  ]
}
```

**`.codex-plugin/.mcp.json` 스펙:**
```json
{
  "mcpServers": {
    "nova": {
      "type": "stdio",
      "command": "node",
      "args": ["./mcp-server/dist/index.js"]
    }
  }
}
```

### Sprint 2: 스크립트 수정

| # | 파일 | 변경 내용 | 검증 명령 |
|---|------|----------|----------|
| 2.1 | `scripts/bump-version.sh` | `# 3. plugin.json` 블록 직후 `# 3-1.` 블록 추가 | `bash scripts/bump-version.sh patch && jq .version .codex-plugin/plugin.json` |
| 2.2 | `scripts/release.sh` | Step 4 `git add` 대상에 `.codex-plugin/plugin.json` 추가 | 파일 내 해당 줄 확인 |

### Sprint 3: 테스트 추가

| # | 파일 | 변경 내용 | 검증 명령 |
|---|------|----------|----------|
| 3.1 | `tests/test-scripts.sh` | 섹션 5-1 Codex 매니페스트 4개 + 섹션 6 버전 동기화 1개 + 섹션 9 BUMP_DIR 복사 대상 확장 | `bash tests/test-scripts.sh` (174개 PASS) |

### Sprint 4: README 업데이트

| # | 파일 | 변경 내용 |
|---|------|----------|
| 4.1 | `README.md` | "Install / Update / Remove" 섹션에 "Codex CLI (Beta)" 서브섹션 추가 |
| 4.2 | `README.ko.md` | 동일 내용 한국어로 추가 |

---

## 검증 기준 (Evaluator PASS/FAIL)

| # | 항목 | 판정 방법 | 기준 |
|---|------|----------|------|
| V1 | `.codex-plugin/plugin.json` JSON 유효 | `jq . .codex-plugin/plugin.json` | exit 0 |
| V2 | `.codex-plugin/.mcp.json` JSON 유효 | `jq . .codex-plugin/.mcp.json` | exit 0 |
| V3 | 필수 필드 존재 | `jq -e '.name,.version,.description,.skills'` | exit 0 |
| V4 | version == `.nova-version` | 문자열 비교 | 동일 |
| V5 | 기존 Claude 파일 무변경 | `git diff .claude-plugin/ .mcp.json hooks/ .claude/commands/ .claude/agents/` | diff 없음 |
| V6 | `bash tests/test-scripts.sh` 전체 통과 | 스크립트 실행 | ALL PASS, exit 0 |
| V7 | `bump-version.sh patch` 후 버전 동기화 | 버전 문자열 비교 | 일치 |
| V8 | `release.sh` git add에 `.codex-plugin/plugin.json` 포함 | grep | 매칭 |
| V9 | README에 Codex 설치 섹션 | `grep -q 'Codex CLI' README.md` | 매칭 |
| V10 | README에 손실 기능 경고 | `grep -q 'session-start' README.md` | Codex 섹션 내 매칭 |

---

## 리스크 / 미지원 범위

### Phase 1에서 Codex 사용자가 잃는 것

| 기능 | Claude | Codex Phase 1 | 우회 방안 |
|------|--------|---------------|----------|
| `session-start.sh` 규칙 자동 주입 | 있음 | **없음** | 세션 시작 시 nova-rules.md 수동 첨부 |
| 슬래시 커맨드 (`/nova:plan` 등) | 12개 | **없음** | commands/*.md 내용 직접 참조 (Phase 2에서 skill wrapper) |
| Specialist Agents | 5종 | **없음** | agents/*.md 내용 수동 복사 (Phase 2에서 TOML 변환) |
| MCP 경로 | `${CLAUDE_PLUGIN_ROOT}` 자동 | 불확실 | `~/.codex/config.toml` 수동 절대경로 (Phase 3 실측) |

### 리스크

| 리스크 | 확률 | 영향 | 완화 |
|--------|------|------|------|
| Codex가 `.codex-plugin/.mcp.json` 상대경로 미지원 | 중 | MCP 동작 안 함 | Phase 3 실측 → 절대경로 config.toml 안내 |
| Codex가 `skills` 필드 경로를 다르게 해석 | 낮음 | 스킬 미로드 | `skills` 절대경로 교체 |
| bump-version.sh 임시 환경 테스트 BUMP_DIR 누락 | 중 | 버전 동기화 테스트 FAIL | 섹션 9 BUMP_DIR 복사 대상 확장 |
| README 변경이 AUTO-GEN 마커 범위 침범 | 낮음 | generate-meta.sh 오작동 | AUTO-GEN 마커 밖에 배치 |

---

## Phase 로드맵

| Phase | 범위 |
|-------|------|
| **Phase 1 (현재)** | 듀얼 매니페스트, skills 공유, bump/release/test 동기화, README |
| **Phase 2** | commands → skill wrapper, agents → `.codex/agents/*.toml` 변환 |
| **Phase 3** | Codex 설치 후 MCP 상대경로 실측 → 경로 전략 확정 |
