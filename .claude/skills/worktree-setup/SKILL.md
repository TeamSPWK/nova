---
name: worktree-setup
description: "git worktree에서 메인 레포의 환경 설정이 필요할 때. — MUST TRIGGER: 새 worktree 진입 직후, 사용자가 '환경변수 안 읽힘·시크릿 못 찾음'을 보고할 때, EnterWorktree 도구 호출 직후."
description_en: "Use when the main repo's environment setup is needed inside a git worktree. — MUST TRIGGER: right after entering a new worktree, when the user reports 'env vars not read' or 'secrets not found', or right after the EnterWorktree tool is called."
user-invocable: false
---

# Nova Worktree Setup

git worktree는 기본적으로 **gitignored 파일**(`.env`, `.secret/`, `.npmrc` 등)을 새 작업 디렉토리로 복사하지 않는다. 그래서 worktree를 만들면 환경변수·시크릿·레지스트리 토큰이 통째로 사라진 채 세션이 시작된다. 이 스킬은 그 갭을 닫는다 — 병렬 에이전트가 같은 환경으로 바로 일할 수 있게.

## 동작

1. **SessionStart 훅이 자동 실행**한다 (`hooks/worktree-setup.sh`). 설치만 하면 끝. opt-in 불필요.
2. 메인 레포를 감지한다: `CONDUCTOR_ROOT_PATH` → `git worktree list` 첫 항목 순서.
3. 메인 레포에서 다음 항목을 worktree 루트로 **심볼릭 링크**한다 (존재하면 skip, 멱등):

   | 기본 대상 | 타입 | 용도 |
   |----------|------|------|
   | `.env` | 파일 | 기본 환경변수 |
   | `.env.local` | 파일 | 로컬 오버라이드 |
   | `.env.development` | 파일 | 개발 환경 |
   | `.secret` | 디렉토리 | 시크릿 디렉토리 (SWK 컨벤션) |
   | `.npmrc` | 파일 | 프라이빗 레지스트리 토큰 |

   > `.env.production`은 **기본 대상에서 제외**한다. 운영 시크릿을 worktree에 노출하는 사고를 막기 위해 — 필요 시 `worktree-sync.json`에 명시.

4. 이미 존재하는 파일·심링크는 **절대 덮어쓰지 않는다**. 재실행도 안전.

5. **깨진 심링크 감지**: worktree에 이미 심링크가 있지만 대상이 사라진 경우(예: 메인 레포에서 `.env` 삭제 후 worktree 심링크만 남음), 자동 교체는 하지 않고 stderr에 경고를 출력한다. 사용자가 `readlink`로 대상을 확인하고 수동 대응한다.

## 프로젝트별 오버라이드

프로젝트 루트에 `.claude/worktree-sync.json`을 두면 기본 대상을 교체한다:

```json
{
  "links": [".env", ".env.local", "config/secrets.json", ".npmrc", ".envrc"]
}
```

- 절대 경로(`/...`)는 무시된다.
- 경로 세그먼트 `..`(상위 디렉토리 이동)이 포함되면 무시된다. 단 파일명 안의 `..` 문자열(예: `.env..backup`)은 허용된다.
- 경로는 메인 레포 루트 기준의 상대 경로다.
- `links`가 있으면 기본 5종 대신 이 목록만 사용한다 (교체 방식).

## 트리거 조건

- **자동**: SessionStart 훅이 매번 실행 (멱등)
- **수동**: 사용자가 `/nova:worktree-setup` 호출 시 즉시 재시도
- **장애**: 사용자가 "env 못 찾음", "시크릿 안 읽힘", ".env가 비었다"를 보고하면 worktree 상황을 의심하고 이 스킬의 동작을 확인한다

## 런타임 감지 체크리스트

사용자가 환경 문제를 보고할 때 확인할 것:

1. `git worktree list` — 현재 메인 레포인지 worktree인지 확인
2. `ls -la .env .secret/ .npmrc` — 심링크가 걸려있는지, 링크 대상이 존재하는지
3. `readlink -f .env` (Linux) / `readlink .env` (macOS) — 링크 대상 경로 확인
4. 메인 레포의 파일이 존재하는지 (`.env` 자체가 메인에도 없으면 링크 대상이 없음)

## 분기 ref 선택 (`worktree.baseRef`, CC v2.1.133+)

Claude Code v2.1.133부터 `--worktree`/`EnterWorktree`/agent-isolation 워크트리가 어느 ref에서 분기할지 settings.json `worktree.baseRef`로 명시 선택할 수 있다.

> 타임라인: v2.1.128에서 `EnterWorktree`가 `origin/<default>` 대신 로컬 `HEAD`에서 분기하도록 동작이 수정됐고(unpushed 커밋 누락 차단), v2.1.133에서 사용자가 `head` vs `fresh`를 명시 선택할 수 있는 설정이 도입됐다. v2.1.128~v2.1.132 구간에는 본 설정 자체가 없다.

| 값 (v2.1.133+) | 동작 | Nova 권장 사용처 |
|----------------|------|------------------|
| `head` | 로컬 `HEAD`에서 분기 — unpushed 커밋 포함 | **기본 권장** (Nova의 incremental 작업 흐름과 일치, v2.1.128 이후 사실상 기본 동작과 동일). |
| `fresh` | `origin/<default>`에서 분기 — 깨끗한 원격 기준 | release-track 검증, hot-fix 분기, "메인이 깨끗한 상태에서 시작하고 싶다"는 의도가 명확할 때. |

설정 예시 (`~/.claude/settings.json` 또는 프로젝트 `.claude/settings.json`):

```json
{
  "worktree": {
    "baseRef": "head"
  }
}
```

> 이 스킬(`worktree-setup`)은 **셋업** 담당이고, **분기 ref**는 Claude Code 자체 설정이다. baseRef는 본 스킬이 자동 변경하지 않는다 — 사용자/팀의 settings.json 결정 영역.

## 범위 밖

- Windows `junction` 지원 — 1차는 macOS/Linux만
- direnv 자동 `allow` — 별도 스킬로 분리 예정
- worktree 생성 자체 (`git worktree add`) — 이 스킬은 셋업만 담당, 생성은 사용자·Claude의 `EnterWorktree` 도구가 수행

## 사용자 가이드

사용자가 "어떻게 쓰는지" 질문하면 먼저 **[docs/guides/worktree-setup.md](../../docs/guides/worktree-setup.md)** 를 안내한다. Quick Start, 오버라이드 예제, 트러블슈팅(깨진 심링크·jq 미설치·Windows 한계), 보안 모델까지 사용자 관점에서 정리되어 있다.

## 참고

- `hooks/worktree-setup.sh` — 실제 스크립트
- `commands/worktree-setup.md` — `/nova:worktree-setup` 수동 실행
- `docs/guides/worktree-setup.md` — 사용자 가이드 (Quick Start · 오버라이드 예제 · 트러블슈팅)
- `CONDUCTOR_ROOT_PATH` — Conductor 워크스페이스 환경에서 자동 제공되는 메인 레포 경로
