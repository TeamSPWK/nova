# Nova Coexist 모드 — OMC 등 다른 오케스트레이션 플러그인과 공존

## TL;DR

OMC(oh-my-claudecode)처럼 SessionStart·PreToolUse·PostToolUse·Stop 훅을 전부 잡는 "세션 소유형"
플러그인과 Nova를 같이 쓰면 훅이 2배로 쌓인다. **`NOVA_COEXIST=1`** 은 Nova의 고유 가치인
**커밋 게이트만 남기고** 나머지(규칙 주입·per-tool 관찰성·stop·pre-compact·pre-edit)를 끈다.

```bash
bash scripts/nova-coexist.sh on        # 공존 모드 켜기 (게이트만)
bash scripts/nova-coexist.sh off       # 끄기 (full Nova 복귀)
bash scripts/nova-coexist.sh status    # 현재 상태
```

> ⚠️ **"끄기"가 아니라 "다이어트"** — `NOVA_COEXIST=1`은 Nova를 *게이트만 남기고 얇게* 만든다.
> Nova를 완전히 끄는 게 아니다. (완전 off는 `/plugin` 비활성 또는 `NOVA_DISABLE_EVENTS=1`.)

## 3가지 상태

| 설정 | Nova 동작 | 용도 |
|------|-----------|------|
| 없음 / `0` (**기본값**) | full Nova — 모든 훅 | Nova 단독 사용 |
| `NOVA_COEXIST=1` | **게이트만** (나머지 no-op) | OMC 등과 공존 |
| `NOVA_DISABLE_EVENTS=1` | 게이트까지 off | Nova 완전 무력화 |

## 무엇이 유지/억제되나

| 훅 | COEXIST=1 | 이유 |
|----|-----------|------|
| `pre-commit-reminder.sh` (커밋 게이트) | ✅ **유지** | Nova 고유 가치 — 검증 안 된 커밋 차단 |
| `init-nova-state.sh` · `worktree-setup.sh` | ✅ 유지 | 게이트 인프라·env 셋업, OMC와 무충돌 |
| `session-start.sh` (규칙 주입) | ⛔ 최소화 | OMC가 자체 가이드 주입 → 중복 방지 |
| `pre/post-tool-use-record.sh` | ⛔ no-op | OMC per-tool 훅과 레이턴시 중첩 |
| `pre-edit-check.sh` · `stop-event.sh` · `pre-compact.sh` | ⛔ no-op | OMC 대응 훅과 중복 |

## 절차

1. **켜기**: `bash scripts/nova-coexist.sh on` (global) 또는 `... on --project` (현재 레포만).
2. **재시작**: env는 세션 시작 시 로드되므로 **새 Claude Code 세션부터 적용**. 현재 세션은 재시작.
3. **확인**: 새 세션의 SessionStart에 `[Nova coexist] 커밋 게이트만 활성` 1줄이 뜨면 적용됨.
4. **되돌리기**: `bash scripts/nova-coexist.sh off` → 재시작 → full Nova.

## 팀원 영향 (중요)

**완전 opt-in.** 기본값이 "미설정 → full Nova"라 `NOVA_COEXIST`를 설정하지 않은 팀원은
**이전과 100% 동일**하게 동작한다. 플러그인을 이 버전으로 업데이트해도 안 켜면 변화 없음.

- 개인만: global `~/.claude/settings.json`에 켜기 → 본인 환경만.
- 특정 레포에서 팀 공유: 그 레포 `.claude/settings.json`을 커밋(`... on --project` 후 add) → 그 레포에서 팀 전체 공존 모드.

## FAIL 시 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| 켰는데 규칙 주입이 그대로 | 현재 세션에 미적용 | Claude Code **재시작** (env는 세션 로드) |
| 게이트가 안 막힘 | COEXIST가 아니라 게이트 자체 미설치 | `bash scripts/setup.sh` 또는 `NOVA_DISABLE_EVENTS` 해제 확인 |
| `settings.json 파싱 실패` | 기존 settings.json JSON 깨짐 | 해당 파일 JSON 유효성 먼저 복구 |
| 설치된 플러그인이 무시 | 캐시가 구버전(가드 없는) | 플러그인 업데이트(이 변경 포함 버전 이상) |

## Cheatsheet

```bash
bash scripts/nova-coexist.sh status            # 지금 켜져 있나?
bash scripts/nova-coexist.sh on                # 게이트만 (OMC 공존)
bash scripts/nova-coexist.sh on --project      # 이 레포에서만
bash scripts/nova-coexist.sh off               # full Nova 복귀
bash scripts/nova-coexist.sh -h                # 도움말
# 적용은 항상 새 세션부터. 게이트는 COEXIST에서도 항상 살아있다.
```
