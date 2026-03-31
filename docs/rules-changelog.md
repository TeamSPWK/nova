# Rules Changelog

> Nova Adaptive — 규칙 변경 이력
> 규칙이 추가/수정/폐기될 때마다 기록한다.

---

## 형식

```
## [YYYY-MM-DD] {규칙명}
- **변경**: 추가 | 수정 | 폐기
- **내용**: {규칙 요약}
- **사유**: {왜 이 변경이 필요한가}
- **제안**: {AI / 사람}
- **승인**: {승인자}
- **참조**: {proposal 문서 링크 또는 커밋}
```

---

## 이력

### [2026-03-31] 플러그인 사용자 우선 검증
- **변경**: 추가
- **내용**: 모든 변경 시 "플러그인 사용자에게 전달되는가" 관점 검증 필수. session-start.sh 동기화 테스트로 강제.
- **사유**: CLAUDE.md만 수정하고 session-start.sh 동기화 누락 3회, 신규 프로젝트 온보딩 실패 1회
- **제안**: AI
- **승인**: jay
- **참조**: `docs/proposals/004-plugin-user-first.md`

### [2026-03-31] 릴리스 전 /review 필수
- **변경**: 추가
- **내용**: Release Workflow에 `/review` 단계 추가 (patch: --fast, minor: 기본, major: --strict)
- **사유**: v3.3.0 릴리스 직후 Critical 3건 발견 → v3.3.1 핫픽스 필요
- **제안**: AI
- **승인**: jay
- **참조**: `docs/proposals/005-review-before-release.md`

### [2026-03-27] 공통 쉘 프리앰블 분리
- **변경**: 추가
- **내용**: `scripts/lib/common.sh` 생성 — 색상, `load_env`, `require_commands`, `banner`, `divider` 공통 함수
- **사유**: 5개 스크립트에서 동일 코드 반복 (색상 5회, 의존성 검사 2회, 배너 15회)
- **제안**: AI
- **승인**: jay
- **참조**: `docs/proposals/001-shared-shell-preamble.md`

### [2026-03-27] 쉘 strict 모드 통일
- **변경**: 추가
- **내용**: 모든 스크립트는 `set -euo pipefail` 사용. 테스트 스크립트는 assert 특성상 `-e` 제외 허용 (주석 명시)
- **사유**: gap-check.sh, test-scripts.sh에서 `-e` 누락으로 일관성 부재
- **제안**: AI
- **승인**: jay
- **참조**: `docs/proposals/002-strict-mode-convention.md`

### [2026-03-27] 배너 출력 함수화
- **변경**: 추가
- **내용**: `banner()`, `divider()` 함수를 common.sh에 포함. 각 스크립트에서 raw echo 대신 함수 사용
- **사유**: 4개 스크립트에서 동일 구분선 15회 반복
- **제안**: AI
- **승인**: jay
- **참조**: `docs/proposals/003-banner-function.md`

### [2026-03-26] Nova 초기 규칙 체계
- **변경**: 추가
- **내용**: CPS 문서 구조, git 커밋 컨벤션, 보안 규칙, 교차검증 프로토콜
- **사유**: Nova Engineering v1.0 도구 키트 초기 릴리즈
- **제안**: Spacewalk Engineering
- **승인**: Spacewalk Engineering
- **참조**: 커밋 `8a67854`
