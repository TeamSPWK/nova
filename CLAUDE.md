# Nova

AI 개발 품질 게이트 — Claude Code 플러그인으로 배포. 오케스트레이터 루프 안의 검문소.

## Language

- Claude는 사용자에게 항상 **한국어**로 응답한다.

## Nova Quality Gate

이 프로젝트는 Nova Quality Gate 방법론을 따른다.
아래 규칙은 사용자가 커맨드를 명시적으로 호출하지 않아도 **모든 대화에 자동 적용**된다.

### 자동 적용 규칙

#### 1. 작업 전 복잡도 + 위험도 판단

| 복잡도 | 기준 | 자동 행동 |
|--------|------|----------|
| **간단** | 버그 수정, 1~2 파일 수정, 명확한 변경 | 바로 구현 → 구현 후 독립 검증 |
| **보통** | 3~7 파일, 새 기능 추가 | Plan 작성 → 승인 → 구현 → 독립 검증 |
| **복잡** | 8+ 파일, 다중 모듈, 외부 의존성 | Plan → Design → 스프린트 분할 → 구현 → 독립 검증 |

#### 2. Generator-Evaluator 분리 (핵심)

- 구현(Generator)과 검증(Evaluator)은 **반드시 다른 서브에이전트**로 실행한다.
- 검증 에이전트는 적대적 자세: "통과시키지 마라, 문제를 찾아라."
- 간단한 작업에서도 구현 후 최소한 서브에이전트로 코드 리뷰를 수행한다.
- Nova는 검증만 담당한다. 실행/오케스트레이션은 사용자 또는 외부 오케스트레이터가 담당한다.

#### 3. 검증 기준

- **기능**: 요청한 것이 실제로 동작하는가?
- **데이터 관통**: 입력 → 저장 → 로드 → 표시까지 완전한가?
- **설계 정합성**: 기존 코드/아키텍처와 일관되는가?
- **크래프트**: 에러 핸들링, 엣지 케이스, 타입 안전성

#### 4. 실행 검증 우선

"코드가 존재한다" ≠ "동작한다". 가능한 경우 `bash tests/test-scripts.sh` 등 실제 실행 테스트를 수행한다.

#### 5. 검증 경량화 원칙

- 검증이 무거우면 사용자가 우회한다.
- 기본 검증은 경량(Lite)으로 수행한다.
- `--strict`를 명시적으로 요청할 때만 풀 검증을 수행한다.

#### 6. 세션 상태 유지

- 프로젝트 루트에 `NOVA-STATE.md`가 있으면 세션 시작 시 반드시 읽는다.
- 작업 시작/완료/검증 시 `NOVA-STATE.md`를 업데이트한다.
- 상태 파일은 50줄 이내를 유지한다 — 인덱스 역할만, 상세는 링크로.

## Release Workflow (필수)

Nova는 Claude Code 플러그인이므로 **모든 커밋은 릴리스 단위**다.
변경사항을 커밋할 때 반드시 다음을 한 세트로 수행한다:

```
1. 구현 + 테스트 통과 확인
2. git add + git commit
3. bash scripts/bump-version.sh <patch|minor|major>  ← 범프된 파일 자동 생성
4. git add + git commit (버전 범프)
5. git tag v{새버전}
6. git push origin main --tags
7. gh release create v{새버전} --title "v{새버전} — {한줄 설명}" --notes "{변경 요약}"
```

### 버전 범프 기준

| 수준 | 기준 | 예시 |
|------|------|------|
| **patch** | 버그 수정, 문서 정리, 레거시 정리 | v2.4.0 → v2.4.1 |
| **minor** | 새 커맨드/스킬 추가, 기존 기능 개선 | v2.4.0 → v2.5.0 |
| **major** | 호환성 깨지는 변경, 아키텍처 전환 | v2.4.0 → v3.0.0 |

### 버전 동기화 구조

`bump-version.sh`가 3곳을 자동 동기화한다:
- `scripts/.nova-version` — 원격 버전 체크용 (단일 파일 curl)
- `.claude-plugin/plugin.json` — 플러그인 매니페스트
- `README.md` + `README.ko.md` — 배지

## Tech Stack

- 마크다운 기반 커맨드/에이전트/스킬 정의
- Bash 스크립트 (bump-version.sh, test-scripts.sh)
- Claude Code Plugin API (.claude-plugin/)

## Project Structure

```
nova/
├── .claude/
│   ├── commands/     # 11개 슬래시 커맨드
│   ├── agents/       # 5개 전문가 에이전트
│   ├── skills/       # 3개 스킬
│   └── settings.json
├── .claude-plugin/
│   ├── plugin.json       # 플러그인 매니페스트 (버전 source)
│   └── marketplace.json  # 마켓플레이스 메타데이터
├── docs/
│   ├── templates/    # CPS 문서 템플릿 + NOVA-STATE.md 템플릿
│   ├── decisions/    # ADR
│   └── proposals/    # 규칙 제안서
├── scripts/
│   ├── .nova-version # 버전 파일
│   └── bump-version.sh
├── tests/
│   └── test-scripts.sh  # 자동 테스트 (118개)
└── CLAUDE.md         # 이 파일
```

## Git Convention

```
feat: 새 기능/커맨드 추가   | fix: 버그 수정, 레거시 정리
update: 기존 기능 개선      | docs: 문서 변경
refactor: 리팩토링          | chore: 설정/기타
```

커밋 메시지에 버전 포함: `feat(v2.5.0): 새 기능 설명`

## Credentials

- **절대 git 커밋 금지**: `.env`, `.secret/`, `*.pem`, `*accessKeys*`

## Human-AI Boundary

| 영역 | AI 담당 | 인간 담당 |
|------|---------|----------|
| 코드 생성 | 구현 + 독립 검증 | 아키텍처 결정, 방향성 |
| 릴리스 | 버전 범프 + 태그 + 릴리스 실행 | 범프 수준 결정 (patch/minor/major) |
| 규칙 관리 | 패턴 감지, 규칙 제안 | 승인/거부 |
