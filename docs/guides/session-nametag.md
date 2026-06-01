# 세션 라벨(네임태그) — 무엇이고 어떻게 바꾸나

Claude Code를 Nova로 실행하면 세션마다 라벨이 붙는다. 이 라벨은 `hooks/session-start.sh`가 SessionStart 시점에 `sessionTitle`로 내보내며, Claude Code가 세션 식별용으로 표시한다(`/rename`과 동일 효과).

## TL;DR

```sh
# 기본:           <프로젝트> · <goal>      예) nova · v3 work-item registry
# 접두사 붙이기:   export NOVA_TITLE_PREFIX="◆ "   → ◆ nova · v3 work-item registry
# 접두사 비우기:   (미설정이 기본 — 아무것도 안 붙음)
```

## 생성 기준

라벨은 **프로젝트명을 정체성으로 먼저** 두고, 현재 목표를 보조로 붙인다.

| 구성 | 출처 |
|------|------|
| `<프로젝트>` | git 레포명(`git rev-parse --show-toplevel`의 basename) → 없으면 현재 디렉토리명 |
| `· <goal>` | `NOVA-STATE.md`의 `goal`(v2 frontmatter) 또는 `- **Goal**:`(v1). 마크다운 강조 제거 + 자연 경계에서 자르기 + 80자 cap |

- goal이 없으면(`NOVA-STATE.md` 부재 등) 라벨은 **프로젝트명만**.
- 세션을 여러 개 띄워도 `nova · …`, `spacewalk-api · …` 처럼 맨 앞 프로젝트명으로 바로 구분된다.

## 커스터마이즈 — `NOVA_TITLE_PREFIX`

라벨 맨 앞에 붙는 접두사. 셸 rc(`~/.zshrc` 등)에 export 하면 모든 세션에 적용된다.

| 값 | 결과 |
|----|------|
| (미설정/빈 값, 기본) | `nova · v3 work-item registry` |
| `NOVA_TITLE_PREFIX="◆ "` | `◆ nova · v3 work-item registry` |
| `NOVA_TITLE_PREFIX="[work] "` | `[work] nova · v3 work-item registry` |

> 기본값은 빈 문자열이라 미설정 시 접두사가 붙지 않는다. 셸 rc에서 export 하면 모든 세션에 적용된다.

## 색상은 왜 못 바꾸나 (정직한 한계)

라벨 색(예: 청록색)은 **Claude Code 테마가 결정**하며 hook이 제어할 수 없다.

- 공식 hooks reference에 `sessionTitle`용 color/style 필드가 없다 — plain 문자열만 받는다.
- `terminalSequence` allowlist는 CSI 색상·OSC 팔레트 시퀀스를 명시적으로 거부한다.
- 이 환경(cmux→Ghostty→tmux)은 탭 색상 OSC 자체가 막혀 있다(Ghostty는 iTerm `OSC 1337`을 parse-only, 미구현).

→ 세션을 색으로 구분하고 싶으면 현재로선 셸 `PS1`에 truecolor(`\033[38;2;R;G;Bm`)를 직접 넣거나, 진짜 탭 색이 필요하면 iTerm2(`OSC 1337 SetColors=tab`)로 전환하는 것이 정공법이다. Nova hook은 색을 칠하지 않는다.

## 관련

- 구현: `hooks/session-start.sh` (`_NOVA_PROJECT`, `SESSION_TITLE`)
- 회귀 테스트: `tests/test-scripts.sh` R37p~R37s
