# Contributing to AXIS Kit

AXIS Kit에 기여해주셔서 감사합니다.

## 기여 방법

### 버그 리포트
GitHub Issues에 다음을 포함하여 등록:
- 재현 단계
- 기대 동작 vs 실제 동작
- 환경 (OS, Claude Code 버전)

### 기능 제안
1. 먼저 Issue로 아이디어를 공유
2. CPS 구조로 제안: Context(왜 필요) → Problem(뭐가 문제) → Solution(어떻게)
3. 논의 후 구현

### 코드 기여
1. Fork → Branch (`feat/기능명` or `fix/버그명`)
2. 변경 후 `bash tests/test-scripts.sh` 통과 확인
3. Pull Request

## 개발 규칙

### 커밋 컨벤션
```
feat: 새 기능      | fix: 버그 수정
update: 기능 개선  | docs: 문서 변경
refactor: 리팩토링 | chore: 설정/기타
```

### 경량 원칙
- 커맨드 추가 시: 정말 필요한가? 기존 커맨드로 해결 가능하지 않은가?
- 스크립트 수정 시: `bash tests/test-scripts.sh` 통과 필수
- 문서 추가 시: CPS 구조를 따르는가?

### 테스트
```bash
bash tests/test-scripts.sh  # 전체 테스트 (35개 항목)
```

## 디렉토리 가이드

| 경로 | 내용 | 수정 시 주의 |
|------|------|-------------|
| `.claude/commands/` | 슬래시 커맨드 | 기존 커맨드 형식 따를 것 |
| `scripts/` | CLI 스크립트 | 테스트 필수, 에러 처리 포함 |
| `docs/templates/` | 문서 템플릿 | CPS 구조 유지 |
| `docs/` | 방법론/가이드 | 기존 문서와 일관성 |
| `examples/` | 사용 예시 | 현실적인 시나리오 |
| `tests/` | 테스트 | 새 파일 추가 시 테스트도 추가 |
