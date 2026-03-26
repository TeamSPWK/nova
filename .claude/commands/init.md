새 프로젝트에 AXIS Kit을 초기 설정한다.

# Role
너는 AXIS Engineering 프로젝트 초기화 도우미다.
사용자의 프로젝트에 AXIS Kit 구조를 셋업하고, CLAUDE.md를 생성한다.

# Execution

1. 사용자에게 기본 정보를 확인한다 (인자가 없으면 질문):
   - **프로젝트명**: 프로젝트 이름 (예: my-app)
   - **기술 스택**: 프레임워크와 언어 (예: Next.js + TypeScript)
   - **응답 언어**: Claude 응답 언어 (기본: 한국어)

2. 디렉토리 구조를 생성한다:
   ```bash
   mkdir -p docs/plans docs/designs docs/decisions docs/verifications docs/templates
   mkdir -p scripts
   ```

3. `CLAUDE.md`를 프로젝트 루트에 생성한다:
   - `docs/templates/claude-md.md` 템플릿을 참고하되, axis-kit에서 직접 가져오지 않고 사용자 정보로 채워서 생성한다.
   - `{중괄호}` 플레이스홀더를 사용자가 제공한 정보로 대체한다.
   - 프로젝트 구조(Project Structure)는 실제 디렉토리를 확인해서 채운다.

4. `.gitignore`에 다음 항목을 추가한다 (이미 있으면 스킵):
   ```
   # AXIS Engineering
   .env
   .secret/
   *.pem
   *accessKeys*
   ```

5. 완료 후 요약을 출력한다:
   ```
   ✅ AXIS Kit 초기화 완료

   생성된 파일:
   - CLAUDE.md
   - docs/plans/
   - docs/designs/
   - docs/decisions/
   - docs/verifications/
   - docs/templates/
   - .gitignore (업데이트)

   다음 단계: /plan 으로 첫 기능을 기획해 보세요.
   ```

# Notes
- 이미 CLAUDE.md가 있으면 덮어쓰기 전에 사용자에게 확인한다.
- 이미 docs/ 구조가 있으면 기존 파일을 건드리지 않는다.
- 최소한의 설정만 생성한다 (경량 원칙).
- 스크립트로 실행하려면: `bash scripts/init.sh {프로젝트명}`

# Input
$ARGUMENTS
