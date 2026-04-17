---
description: "현재 worktree에서 메인 레포의 .env·시크릿·설정 파일을 즉시 심볼릭 링크한다. SessionStart 자동 훅의 수동 재시도 버전."
---

현재 worktree에서 메인 레포의 환경 파일을 즉시 다시 연결한다.

# Role
너는 Nova의 **환경 기둥** 핸들러다.
worktree 진입 후 환경변수·시크릿이 제대로 연결됐는지 확인하고, 누락되면 즉시 링크를 복구한다.

# 언제 사용하나

- worktree에서 작업하려는데 `.env`, `.secret/`, `.npmrc`가 보이지 않을 때
- SessionStart 훅이 어떤 이유로 실패했거나 메인 레포에 나중에 파일이 추가된 경우
- `/nova:worktree-setup --dry-run`으로 어떤 파일이 링크될지 미리 보고 싶을 때

# Execution

1. **현재 위치 확인**
   ```bash
   git worktree list
   pwd
   ```
   - 현재 디렉토리가 메인 레포면 "메인 레포에서는 링크 불필요" 안내 후 종료
   - worktree가 아니면 (단일 clone) "worktree 환경이 아닙니다" 안내 후 종료

2. **`hooks/worktree-setup.sh` 실행**
   ```bash
   NOVA_WORKTREE_DEBUG=1 bash "$CLAUDE_PLUGIN_ROOT/hooks/worktree-setup.sh"
   ```
   - `NOVA_WORKTREE_DEBUG=1`로 어떤 파일이 링크/skip됐는지 상세 로그 출력
   - 멱등하므로 여러 번 실행해도 안전

3. **결과 확인**
   ```bash
   ls -la .env .env.local .env.development .secret .npmrc 2>/dev/null
   ```
   - 심볼릭 링크가 제대로 걸려있는지 확인
   - `readlink`로 링크 대상 경로 확인 (macOS: `readlink file`, Linux: `readlink -f file`)

4. **사용자에게 결과 보고**
   ```
   🔗 Worktree 환경 셋업 결과

   메인 레포: <경로>
   현재 worktree: <경로>

   링크됨:
     ✓ .env → ../main/.env
     ✓ .secret/ → ../main/.secret/

   스킵:
     - .npmrc (메인에 없음)
     - .env.local (이미 존재)

   📝 오버라이드 필요 시: .claude/worktree-sync.json 생성
   ```

# `--dry-run` 플래그

사용자가 `--dry-run`을 전달하면:
1. `hooks/worktree-setup.sh`를 실행하지 않는다
2. 대신 메인 레포의 `.env`, `.env.local`, `.env.development`, `.secret/`, `.npmrc` 존재 여부만 확인하고 "링크 예정 / 메인에 없음 / 이미 존재"로 분류해 출력

# 오버라이드 가이드

기본 대상(5종) 외의 파일을 링크하려면 메인 레포에 `.claude/worktree-sync.json`을 생성한다:

```json
{
  "links": [".env", ".env.local", "config/secrets.json", ".envrc"]
}
```

- `links`가 존재하면 기본값 대체(교체 방식)
- 절대 경로(`/...`)와 상위 이동(`..`)은 무시됨

> 환경 변경은 설정 파일 직접 수정 금지. 환경변수/CLI 플래그 우선 사용 (§9 환경 안전 규칙).

# Notes

- 이 커맨드는 **SessionStart 훅의 수동 재시도** 역할만 한다. 매 세션마다 자동으로 이미 돌아간다.
- `.env.production`은 의도적으로 기본 제외. 운영 시크릿을 worktree에 노출하지 않기 위함.
- Windows는 현재 미지원 (macOS/Linux `ln -s` 전용).
- 사용자가 "어떻게 쓰나요?" 같은 사용법 질문을 하면 **[docs/guides/worktree-setup.md](../../docs/guides/worktree-setup.md)** 를 먼저 안내한다. 설치→첫 사용→오버라이드→트러블슈팅까지 흐름대로 정리되어 있다.

# Input
$ARGUMENTS
