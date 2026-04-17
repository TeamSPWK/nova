# Worktree Setup 가이드

> Nova **환경 기둥**의 첫 시민. git worktree를 만들 때 메인 레포의 환경변수·시크릿이 따라오도록 자동 셋업한다.

---

## 한 줄 요약

Nova를 설치하기만 하면, 새 worktree에 진입할 때마다 메인 레포의 `.env`·`.secret/`·`.npmrc`가 자동으로 심볼릭 링크된다. **설정 없이 동작한다.**

## 왜 필요한가

git worktree는 기본적으로 **gitignored 파일**을 새 작업 디렉토리로 복사하지 않는다.

```bash
git worktree add -b feat/login wt-login
cd wt-login
cat .env           # 파일 없음. 환경변수가 모두 사라짐.
ls .secret/        # 디렉토리도 없음. 시크릿도 사라짐.
npm install        # .npmrc도 없어서 프라이빗 레지스트리 인증 실패.
```

병렬로 여러 worktree를 돌리는 AI 에이전트 시대에는 치명적이다. Nova `worktree-setup`은 이 갭을 닫는다:

```bash
# Nova 설치 상태에서 동일한 과정
git worktree add -b feat/login wt-login
cd wt-login
# → SessionStart 훅이 자동으로 심링크 셋업
cat .env           # ✓ 메인 레포의 내용 그대로
ls .secret/        # ✓ 메인 레포의 시크릿 그대로
```

---

## Quick Start

### 1. Nova 설치

```bash
claude plugin marketplace add TeamSPWK/nova
claude plugin install nova@nova-marketplace
```

설치되면 SessionStart 훅에 `worktree-setup.sh`가 자동 등록된다. **추가 설정 필요 없음.**

### 2. worktree 만들기

```bash
# 메인 레포에서
git worktree add -b feat/new-api wt-new-api

# Claude Code에서 새 worktree로 이동하거나 EnterWorktree 도구 사용
cd wt-new-api
```

### 3. 확인

새 worktree에서 Claude Code 세션을 시작하면, 훅이 자동 실행된 결과를 세션 시작 직후에 볼 수 있다:

```
🔗 Nova worktree-setup: 3개 링크 (.env .secret .npmrc)
```

심볼릭 링크가 제대로 걸렸는지 수동 확인:

```bash
ls -la .env .secret .npmrc
# .env -> /path/to/main-repo/.env
# .secret -> /path/to/main-repo/.secret
# .npmrc -> /path/to/main-repo/.npmrc
```

---

## 기본 링크 대상 (5종)

| 대상 | 타입 | 용도 |
|------|------|------|
| `.env` | 파일 | 기본 환경변수 |
| `.env.local` | 파일 | 로컬 오버라이드 |
| `.env.development` | 파일 | 개발 환경 |
| `.secret` | 디렉토리 | 시크릿 디렉토리 (SWK 컨벤션) |
| `.npmrc` | 파일 | 프라이빗 레지스트리 토큰 |

> **`.env.production`은 의도적 제외.** 운영 시크릿이 worktree에 흘러들어가는 사고를 방지한다. 필요하면 아래 오버라이드로 명시.

---

## 프로젝트별 오버라이드

기본 5종이 맞지 않으면 메인 레포 루트에 `.claude/worktree-sync.json`을 생성한다:

```json
{
  "links": [
    ".env",
    ".env.local",
    ".envrc",
    "config/secrets.json",
    ".google-credentials.json"
  ]
}
```

**규칙:**
- `links`가 있으면 기본 5종은 완전히 대체된다 (교체 방식, 병합 아님)
- 경로는 **메인 레포 루트 기준 상대 경로**
- 절대 경로(`/etc/passwd`)와 경로 세그먼트 `..`(`../../../etc/shadow`)는 보안상 무시된다
- 파일명 안의 `..`(예: `.env..backup`)는 허용된다

### 자주 쓰는 조합

**Node + direnv 프로젝트**
```json
{ "links": [".env", ".env.local", ".envrc", ".npmrc"] }
```

**Python + venv**
```json
{ "links": [".env", ".env.local", ".python-version", "secrets/"] }
```

**모노레포 (공유 config 디렉토리)**
```json
{ "links": [".env", "config/", "packages/shared/.env.local"] }
```

---

## 수동 실행 — `/nova:worktree-setup`

SessionStart 훅이 어떤 이유로 놓쳐졌거나, 메인 레포에 나중에 파일이 추가된 경우:

```
/nova:worktree-setup
```

- 현재 worktree에서 즉시 재시도
- 이미 걸린 링크는 건드리지 않음 (멱등)
- 디버그 로그를 보고 싶으면 직접 훅 실행:
  ```bash
  NOVA_WORKTREE_DEBUG=1 bash "$CLAUDE_PLUGIN_ROOT/hooks/worktree-setup.sh"
  ```

### `--dry-run`

어떤 파일이 링크될지 먼저 확인하고 싶을 때:

```
/nova:worktree-setup --dry-run
```

실제 링크는 만들지 않고 "링크 예정 / 메인에 없음 / 이미 존재"로 분류만 출력한다.

---

## 트러블슈팅

### Q1. worktree인데 `.env`가 보이지 않는다

1. 현재 위치가 정말 worktree인지 확인
   ```bash
   git worktree list
   pwd
   ```

2. 메인 레포 자체에 `.env`가 존재하는지 확인
   ```bash
   ls -la "$(git worktree list | awk 'NR==1{print $1}')/.env"
   ```
   메인에도 없으면 당연히 링크할 대상이 없다.

3. Claude Code 세션을 새로 시작하거나 `/nova:worktree-setup` 수동 실행

### Q2. "깨진 심링크 감지" 경고가 뜬다

메인 레포의 원본 파일이 삭제되었는데 worktree에 링크만 남은 상태.

```bash
⚠️ Nova worktree-setup: 깨진 심링크 1개 (.env) — 수동 확인 필요
```

**Nova는 자동으로 복구하지 않는다** (의도적인 삭제를 덮어쓸 위험). 사용자가 직접 판단:

```bash
readlink .env           # 링크가 가리키던 경로 확인
rm .env                 # 의도한 삭제면 링크 제거
# 또는 메인 레포에 .env를 다시 만들고 /nova:worktree-setup 실행
```

### Q3. 오버라이드가 안 먹는다

1. `.claude/worktree-sync.json`이 **메인 레포 루트**에 있는지 확인 (worktree가 아니라)
2. JSON 문법 유효성:
   ```bash
   jq . .claude/worktree-sync.json
   ```
3. `jq` 미설치 시 오버라이드가 무시되고 기본값으로 돌아간다. `brew install jq` 또는 시스템 패키지 매니저로 설치.

### Q4. 기존 파일을 덮어쓰고 싶다

Nova는 **이미 존재하는 파일·심링크를 절대 덮어쓰지 않는다** (멱등성·안전성 보장). 교체하고 싶으면:

```bash
rm .env                         # 기존 제거
/nova:worktree-setup            # 다시 링크
```

### Q5. Windows에서 동작하나?

현재는 **macOS/Linux만 공식 지원**한다. Windows는 `ln -s`가 기본 권한에서 실패할 수 있어 별도 junction 지원이 필요하다 — 후속 릴리스에서 검토 예정.

---

## 고급

### Conductor 환경

[Conductor](https://conductor.build) 워크스페이스에서는 `CONDUCTOR_ROOT_PATH` 환경변수가 자동 제공된다. Nova는 이를 우선 사용하므로 추가 설정 없이 동작한다.

### 다른 프로젝트의 기존 `setup-worktree.sh`가 있다면

`swk-cloud-manage` 같은 기존 프로젝트에 로컬 `setup-worktree.sh` + SessionStart 훅 조합이 이미 있다면, Nova v5.5.0+ 설치 후 로컬 버전을 제거해도 된다. 두 훅이 모두 멱등하므로 당장 충돌은 없지만, 관리 포인트가 중복된다.

```bash
# 레거시 제거 예시
rm scripts/setup-worktree.sh
# .claude/settings.json의 SessionStart 훅에서 관련 라인 제거
```

### 보안 모델

- **경로 주입 차단**: 오버라이드의 절대 경로와 `..` 세그먼트는 처리 전에 거부된다
- **원본 파일은 건드리지 않음**: 심볼릭 링크만 생성하며 메인 레포의 원본은 읽기만
- **권한**: 심링크는 원본의 권한을 그대로 따른다 — 원본이 `0600`이면 링크를 통해서도 `0600`
- **.env.production 기본 제외**: 운영 시크릿 사고 방지 (필요 시 오버라이드로 명시)

---

## 관련

- 스킬 명세: `.claude/skills/worktree-setup/SKILL.md`
- 커맨드: `.claude/commands/worktree-setup.md`
- 구현: `hooks/worktree-setup.sh`
- 자동 등록: `hooks/hooks.json` (SessionStart)
- 5기둥 정체성: [`docs/nova-rules.md`](../nova-rules.md)
