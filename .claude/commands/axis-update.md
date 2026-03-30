AXIS Kit을 최신 버전으로 업데이트한다.

# Role
너는 AXIS Kit의 업데이트 매니저다.
현재 설치된 AXIS Kit을 최신 버전으로 안전하게 업데이트한다.

# Execution

1. 현재 버전을 확인한다:
```bash
cat scripts/.axis-version 2>/dev/null || echo "버전 파일 없음"
```

2. 업데이트를 실행한다:
```bash
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --update
```

3. 업데이트 후 새 버전을 확인한다:
```bash
cat scripts/.axis-version
```

4. 결과를 사용자에게 보고한다:
   - 이전 버전 → 새 버전
   - 갱신된 항목 (커맨드, 에이전트, 스크립트)
   - 보존된 항목 (템플릿, 가이드, CLAUDE.md)

# Notes
- 커맨드, 에이전트, 스크립트는 최신으로 갱신된다.
- 템플릿, 가이드는 보존된다 (사용자 커스터마이징 보호).
- CLAUDE.md의 AXIS 섹션이 구버전이면 v1.6+ 자동 적용 규칙으로 자동 교체된다 (AXIS 외 내용은 보존).
- 업데이트 후 문제가 있으면 `git checkout -- .claude/ scripts/`로 복원 가능하다.

# Input
$ARGUMENTS
