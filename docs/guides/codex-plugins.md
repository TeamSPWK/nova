# Codex 플러그인 팀 설치 가이드

## TL;DR

팀원에게 아래 한 줄을 전달한다.

```bash
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/nova/main/scripts/install-codex-recommended-plugins.sh | bash
```

이미 Nova 저장소를 클론한 사람은 로컬에서 실행해도 된다.

```bash
git clone https://github.com/TeamSPWK/nova.git
cd nova
bash scripts/install-codex-recommended-plugins.sh
```

설치 후 Codex를 재시작한다.

## 설치되는 것

| 플러그인 | ID | 용도 |
|---|---|---|
| Browser Use | `browser-use@openai-bundled` | localhost, file URL, 클릭/스크린샷 기반 UI 검증 |
| Documents | `documents@openai-primary-runtime` | `.docx` 생성, 수정, 렌더 검증 |
| Spreadsheets | `spreadsheets@openai-primary-runtime` | `.xlsx`, `.csv`, 계산식, 차트 작업 |
| Presentations | `presentations@openai-primary-runtime` | `.pptx` 생성, 수정, 렌더 검증 |
| Nova | `nova@nova-marketplace` | Nova 스킬, MCP 품질 게이트, 교차검증 도구 |

스크립트는 `~/.codex/config.toml`을 수정하기 전에 `~/.codex/config.toml.bak.YYYYMMDDHHMMSS` 백업을 만든다. 재실행해도 같은 설정으로 수렴한다.

## 사전 조건

- Codex Desktop 또는 Codex CLI가 설치되어 있고 `codex` 명령이 PATH에 있어야 한다.
- Nova MCP 서버 빌드를 위해 `node`가 필요하다.
- `pnpm`이 필요하다. 없으면 스크립트가 `corepack`으로 활성화를 시도한다.
- `curl | bash` 방식은 Nova 저장소를 `~/.codex/marketplaces/nova`에 클론하므로 `git`이 필요하다.

## 동작 방식

1. Nova 저장소를 찾는다.
   - 저장소 안에서 실행하면 현재 체크아웃을 사용한다.
   - `curl | bash`로 실행하면 `~/.codex/marketplaces/nova`에 클론하거나 업데이트한다.
2. `codex plugin marketplace add <nova-root>`로 Nova marketplace를 등록한다.
3. `mcp-server`에서 `pnpm install --frozen-lockfile`과 `pnpm build`를 실행한다.
4. Codex가 스킬을 로드하는 `~/.codex/plugins/cache/nova-marketplace/nova/<version>/`에 Nova 플러그인을 materialize한다.
5. `~/.codex/config.toml`에 추천 플러그인 활성화 블록을 추가/갱신한다.
6. `.codex-plugin/.mcp.json` 자동 로드가 안 되는 환경을 위해 `[mcp_servers.nova]` 폴백도 등록한다.

## 옵션

```bash
# 특정 Nova 체크아웃을 marketplace로 사용
bash scripts/install-codex-recommended-plugins.sh --local /absolute/path/to/nova

# 저장소 안에서 실행해도 ~/.codex/marketplaces/nova를 사용
bash scripts/install-codex-recommended-plugins.sh --remote

# MCP 빌드를 건너뜀
bash scripts/install-codex-recommended-plugins.sh --skip-mcp-build

# ~/.codex/config.toml에 [mcp_servers.nova] 폴백을 쓰지 않음
bash scripts/install-codex-recommended-plugins.sh --no-mcp-fallback

# 도움말
bash scripts/install-codex-recommended-plugins.sh --help
```

## 실패 시 해결

`codex: command not found`

Codex Desktop/CLI 설치 후 새 터미널을 열어 `codex --version`이 되는지 확인한다.

`pnpm not found`

Node.js가 있으면 보통 `corepack enable`로 해결된다. 그래도 안 되면 `npm install -g pnpm` 후 다시 실행한다.

`MCP build output missing`

`mcp-server` 빌드가 실패한 상태다. 아래 명령으로 원인을 확인한다.

```bash
cd /absolute/path/to/nova/mcp-server
pnpm install --frozen-lockfile
pnpm build
```

Codex UI에 Nova가 보이지 않음

Codex를 완전히 재시작한다. 그래도 안 보이면 `~/.codex/config.toml`에 아래 블록이 있는지 확인한다.

```toml
[plugins."nova@nova-marketplace"]
enabled = true
```

그리고 아래 캐시 디렉토리가 있는지 확인한다.

```bash
ls ~/.codex/plugins/cache/nova-marketplace/nova/
```

Nova MCP 도구가 보이지 않음

`~/.codex/config.toml`에 아래 블록이 있고, 경로의 `dist/index.js`가 존재하는지 확인한다.

```toml
[mcp_servers.nova]
command = "node"
args = ["/absolute/path/to/nova/mcp-server/dist/index.js"]
```

## 팀 공유 문구

```text
Codex 추천 플러그인 세트 설치:
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/nova/main/scripts/install-codex-recommended-plugins.sh | bash

설치 후 Codex 재시작하면 됩니다.
```
