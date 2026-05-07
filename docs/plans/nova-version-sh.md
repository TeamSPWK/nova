# [Plan] scripts/nova-version.sh — 설치된 Nova 버전 확인 CLI

> Nova Engineering — CPS Framework
> 작성일: 2026-04-19
> 작성자: Nova DeepPlan
> Mode: deep
> Iterations: 1
> Critic: PASS (2차 — 5 이슈 전부 해소)
> Design: (Design 작성 후 경로 추가)

---

## Context (배경)

### 현재 상태
- Nova의 버전 정보는 **3곳에 분산**되어 있다: `scripts/.nova-version` (단일 소스) · `.claude-plugin/plugin.json` · `.codex-plugin/plugin.json`
- 동기화는 `scripts/bump-version.sh` (릴리스 시 자동)와 `scripts/release.sh`가 담당
- 사용자가 "지금 설치된 Nova 버전이 뭔지" 빠르게 확인할 진입점(CLI)이 없다. README 배지와 plugin.json을 직접 열어봐야 한다

### 왜 필요한가
- 플러그인 사용자가 자신의 Nova 버전을 1초 안에 확인할 수 있어야 한다 (디버깅·이슈 리포트·업그레이드 판단)
- Claude Code 플러그인 설치 경로 다양성(npm-global, brew, `~/.claude/plugins/...`)으로 "어느 Nova"가 활성 상태인지 혼동 가능
- 기존 `scripts/.nova-version`이 이미 "원격 버전 체크용 단일 파일 curl" 용도로 설계되어 있음 → 로컬 조회만 추가하면 완성

### 관련 자료
- `/Users/keunsik/develop/swk/nova/scripts/.nova-version` (현재 5.11.0)
- `/Users/keunsik/develop/swk/nova/scripts/bump-version.sh` — 버전 동기화 로직
- `/Users/keunsik/develop/swk/nova/scripts/lib/common.sh` — 공유 유틸
- `/Users/keunsik/develop/swk/nova/.claude-plugin/plugin.json` — 플러그인 매니페스트
- `/Users/keunsik/develop/swk/nova/README.md` — 버전 배지

---

## Problem (문제 정의)

### 핵심 문제
설치된 Nova 버전을 조회할 공식 CLI가 없고, 다중 버전 소스(.nova-version vs plugin.json) 불일치 시 무엇이 진실인지 사용자가 알 수 없다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | 조회 진입점 부재 | 사용자가 버전 확인을 위해 README나 내부 파일을 열어야 함 | 중간 |
| 2 | 다중 버전 소스 정합성 | `.nova-version` · `.claude-plugin/plugin.json` · `.codex-plugin/plugin.json` 3소스 불일치 시 거짓 안심 가능 | 중간 |
| 3 | 플러그인 설치 경로 다양성 | 여러 Nova 인스턴스(레포 clone + 플러그인 설치) 공존 시 "어느 버전"인지 모호 | 중간 |
| 4 | 상대 경로 의존성 | CWD에 따라 `.nova-version` 탐색 실패 가능 | 높음 |

### 제약 조건
- 플러그인 사용자 환경에서 외부 의존성(jq 등) 강제 금지 (Nova는 "플러그인 업데이트만으로 자동 적용" 원칙)
- macOS/Linux bash 호환 (sed, cat, tr 표준 유틸만)
- 네트워크 비필수 — 오프라인에서도 동작해야 함
- 스크립트 자체는 단순 조회(read-only) — 설정 변경 금지

---

## Solution (해결 방안)

### 선택한 방안
**방안 A 채택**: `scripts/.nova-version`을 `cat`으로 읽어 echo하는 최소 스크립트. 단 `$(dirname "$0")` 기준 절대 경로 해석으로 CWD 독립성 확보, `.nova-version`과 `plugin.json` 버전 불일치 시 경고 출력.

### 대안 비교 (option-explorer 결과 그대로)

| 방안 | 접근 | 장점 | 단점 | 권장도 |
|------|------|------|------|--------|
| A | `scripts/.nova-version` 파일을 `cat`으로 읽어 echo하는 3줄 bash | 의존성 zero(jq 불필요), 기존 단일 버전 소스 규칙과 정합, 구현·테스트 비용 최저, 플러그인 사용자 환경에서도 동작 보장 | 원격 최신 버전과의 비교 기능은 없음(단순 조회만) | ⭐ |
| B | `.claude-plugin/plugin.json`을 `jq -r .version`으로 파싱 | 매니페스트가 진실의 원천이라는 관점에서 의미론적으로 적절 | `jq` 외부 의존성, `.nova-version`이 이미 단일 버전 조회용으로 설계되어 있어 중복 | |
| C | 로컬 버전 + GitHub Releases API로 latest 조회 후 비교 | 업그레이드 필요 여부 한눈에 확인 | 네트워크 필수, curl/jq 의존성, 요청 스펙("간단한 CLI") 초과 | |

**권장 근거**: 요청이 "간단한 CLI"로 명시, `.nova-version`이 이미 단일 버전 참조용 파일로 존재. jq 같은 외부 의존성 없이 한 줄로 끝나며 `bump-version.sh`가 이미 이 파일을 동기화하므로 별도 유지 비용 0. 원격 비교(C)는 추후 `--check-latest` 플래그로 확장 가능.

> **A+B 하이브리드 평가**: 플러그인 배포 후 `.nova-version`이 설치 경로에 포함되지 않는 경우를 대비해, 방안 A에 `plugin.json` 폴백을 추가하는 A+B 하이브리드가 유일한 안전 경로가 된다. 단, `.claude-plugin/plugin.json`과 `.codex-plugin/plugin.json` 모두 `files` 필드를 명시하지 않으므로 Claude Code / Codex 플러그인 배포 규칙상 **레포 전체 파일이 포함**되어 `scripts/.nova-version`도 함께 배포된다. 이 사실을 파일 확인으로 검증(두 plugin.json에 `files` 필드 없음 — 2026-04-19 확인). 따라서 현 시점에서 폴백은 방어적 구현으로만 유지하고, 방안 A를 주 경로로 채택한다.

### 구현 범위

- [ ] `scripts/nova-version.sh` 신규 작성 — `$(dirname "$0")` 기준 절대 경로로 `.nova-version` 읽기
- [ ] `scripts/lib/common.sh`의 공유 유틸 패턴 따름 (색상, 에러 처리)
- [ ] `.nova-version`과 `.claude-plugin/plugin.json` · `.codex-plugin/plugin.json` 3소스 버전 불일치 감지 + 경고 출력
- [ ] 파일 부재 시 명확한 에러 메시지 + exit 1
- [ ] `tests/test-scripts.sh`에 존재/실행/출력 포맷 검증 테스트 추가
- [ ] (선택) `--json` 플래그로 JSON 출력 지원 (sed/grep 기반, jq 미의존)

### 검증 기준

- `bash scripts/nova-version.sh` 실행 시 exit 0, stdout에 단일 라인 버전 출력 (예: `5.11.0`)
- 다른 디렉토리에서 절대 경로로 호출해도 동일 결과 (예: `cd /tmp && bash /path/nova/scripts/nova-version.sh`)
- `.nova-version` 파일 삭제 후 실행 시 exit 1 + 명확 에러 메시지
- 불일치 주입(plugin.json과 `.nova-version` 다른 버전) 시 경고 stdout + exit 2
- `tests/test-scripts.sh` 전체 통과 (회귀 없음)

---

## Sprints (스프린트 분할)

예상 수정 파일 2개 (`scripts/nova-version.sh` 신규 + `tests/test-scripts.sh` 추가 테스트) → **단일 스프린트로 충분**. 분할 불필요.

---

## Risk Map

risk-explorer 결과 그대로:

| 리스크 | 가능성 | 영향 | 완화 |
|--------|--------|------|------|
| 스크립트가 상대경로로 `.nova-version` 탐색 → CWD에 따라 `file not found` | H | H | `$(dirname "$0")` 기준 절대경로. `bump-version.sh`의 `ROOT` 패턴 재사용 |
| 플러그인 설치 경로 다양성(npm-global/brew/`~/.claude/plugins/nova@<ver>/`)에서 "어느 Nova"인지 불명확 | H | M | 현재 스크립트 위치 기준 `.nova-version` 우선, `--source` 옵션으로 plugin vs local 구분 |
| `.nova-version` · `.claude-plugin/plugin.json` · `.codex-plugin/plugin.json` 3소스 버전 불일치 시 거짓 안심 | M | H | 세 값 모두 읽어 일치 시 단일 라인, 불일치 시 경고 + 소스별 나란히 출력. exit code 분기(0/2) |
| `.codex-plugin/plugin.json` 누락 또는 불일치 미감지로 Codex 사용자에게 잘못된 버전 표시 | M | M | 불일치 감지 범위에 `.codex-plugin/plugin.json` 명시. 파일 부재 시 경고만(non-fatal), exit 0 유지 |
| 원격 최신 버전 비교 시 네트워크 실패/DNS 차단에서 hang | M | M | `curl --max-time 3 --fail -sS` + 실패 시 로컬만 출력. `--check-remote` opt-in |
| 플러그인 읽기 전용 설치 경로에 `.nova-version` 미포함 시 crash | M | M | 파일 부재 시 `.claude-plugin/plugin.json` 폴백(grep 기반, jq 미의존). `set -euo pipefail` + 명확 에러. 단, `.claude-plugin/plugin.json`과 `.codex-plugin/plugin.json` 모두 `files` 필드 없어 플러그인 배포 시 전체 포함이 확인됨(2026-04-19 검증) — 발생 가능성 낮음 |
| jq/python 미설치 환경에서 JSON 출력 실패 | L | M | jq 회피. sed/grep으로 `"version": "X.Y.Z"` 추출 |
| `v5.11.0`, `5.10.2-dev` 등 variant에서 semver 비교 실패 | L | L | 정규식 `^v?[0-9]+\.[0-9]+\.[0-9]+([.-].*)?$` 허용. `v` prefix strip |
| tests/test-scripts.sh 동기화 누락으로 회귀 | M | L | 추가 전 스크립트 enumerate 방식 확인, EXPECTED 업데이트, 테스트 실행 확인 |

---

## Unknowns

risk-explorer 결과 그대로:

- **[해소됨]** Claude Code 플러그인이 설치된 후 `scripts/.nova-version` 파일이 실제로 디스크에 존재하는지 — `.claude-plugin/plugin.json`과 `.codex-plugin/plugin.json` 모두 `files` 필드가 없음을 2026-04-19 파일 직접 확인. Claude Code / Codex 플러그인 배포 규칙에 따라 `files` 미지정 시 레포 전체 포함이 기본값이므로 `scripts/.nova-version` 설치 경로 포함 확정. `plugin.json` 폴백은 방어적 구현으로만 유지.
- **[해소됨]** `.codex-plugin/plugin.json` 포함/제외 결정 — `.codex-plugin/plugin.json` 실제 존재 확인(version: 5.11.0, bump-version.sh 동기화 대상). 불일치 감지 범위에 **포함**. 파일 부재 시에는 non-fatal 경고만 출력하여 Claude-only 환경에서도 동작 보장.
- 원격 최신 버전 비교를 스코프에 포함할지 — 요청서가 "현재 설치된 Nova 버전 확인"만 서술. 제외하면 네트워크 리스크 대부분 제거. `--check-latest` 플래그로 추후 확장 예정.
- `/nova:next` 등 다른 커맨드에서 이 스크립트를 호출할지 — 그렇다면 stdout 포맷(human vs JSON) 계약 및 session-start 동기화 체크리스트 대상
- 사용자가 여러 Nova 인스턴스(개발 clone + 설치 플러그인)를 동시 보유하는 비율

---

## Verification Hooks

> Sprint Contract 씨앗 — 이후 `/nova:design` 단계에서 구체화.

| # | 검증 항목 | 검증 방법 | 우선순위 |
|---|----------|----------|---------|
| 1 | `bash scripts/nova-version.sh` → exit 0 + 단일 라인 버전 출력 | `bash scripts/nova-version.sh \| grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+'` | **Critical** |
| 2 | CWD 독립성 — 다른 디렉토리에서 호출해도 동일 결과 | `cd /tmp && bash $ROOT/scripts/nova-version.sh` | **Critical** |
| 3 | `.nova-version` 부재 시 exit 1 + 명확 에러 | `mv scripts/.nova-version .nova-version.bak && bash scripts/nova-version.sh; echo $?` | **Critical** |
| 4 | 버전 불일치 감지 (.nova-version vs plugin.json vs .codex-plugin/plugin.json) | `sed -i.bak 's/"version": "5\.11\.0"/"version": "5.10.0"/' .claude-plugin/plugin.json && bash scripts/nova-version.sh; echo "exit: $?"; mv .claude-plugin/plugin.json.bak .claude-plugin/plugin.json` → exit 2 + 경고 출력 확인 | High |
| 5 | `tests/test-scripts.sh` 회귀 전체 통과 | `bash tests/test-scripts.sh` | **Critical** |
| 6 | 외부 의존성 없음 (jq 미설치 환경 시뮬레이션) | `PATH=/usr/bin bash scripts/nova-version.sh` | High |
| 7 | `--json` 플래그 JSON 출력 (선택 구현 시) | `bash scripts/nova-version.sh --json \| python3 -c "import json,sys; json.load(sys.stdin)"` | Nice-to-have |
| 8 | 스크립트 권한 실행 가능 (`+x`) | `[ -x scripts/nova-version.sh ]` | **Critical** |
