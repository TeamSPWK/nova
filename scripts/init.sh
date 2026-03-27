#!/usr/bin/env bash
#
# AXIS Kit 프로젝트 초기화 스크립트
# Usage: bash scripts/init.sh <프로젝트명> [기술스택] [언어]
#
# 예시:
#   bash scripts/init.sh my-app "Next.js + TypeScript" "한국어"
#   bash scripts/init.sh my-app
#   bash scripts/init.sh --adopt my-app   # 기존 프로젝트에 비파괴적 도입
#

set -euo pipefail

# --- 모드 감지 ---
ADOPT_MODE=false
if [[ "${1:-}" == "--adopt" ]]; then
  ADOPT_MODE=true
  shift
fi

# --- 인자 파싱 ---
PROJECT_NAME="${1:-}"
TECH_STACK="${2:-}"
LANGUAGE="${3:-한국어}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
check_update

if [ -z "$PROJECT_NAME" ]; then
  echo -e "${BOLD}사용법:${NC}"
  echo -e "  ${YELLOW}\$ bash scripts/init.sh [--adopt] <프로젝트명> [기술스택] [언어]${NC}"
  echo ""
  echo -e "${BOLD}예시:${NC}"
  echo -e "  ${YELLOW}\$ bash scripts/init.sh my-app \"Next.js + TypeScript\" \"한국어\"${NC}"
  echo -e "  ${YELLOW}\$ bash scripts/init.sh --adopt my-app${NC}   # 기존 프로젝트에 비파괴적 도입"
  exit 1
fi

if [ "$ADOPT_MODE" = true ]; then
  banner "🔧 AXIS Kit 기존 프로젝트 도입: ${BOLD}$PROJECT_NAME"
else
  banner "🔧 AXIS Kit 초기화: ${BOLD}$PROJECT_NAME"
fi
echo ""

# --- 디렉토리 생성 ---
dirs=(
  "docs/plans"
  "docs/designs"
  "docs/decisions"
  "docs/verifications"
  "docs/templates"
  "scripts"
)

for dir in "${dirs[@]}"; do
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    echo -e "  ${GREEN}✓${NC} 📁 ${CYAN}$dir/${NC} 생성"
  else
    echo -e "  ${YELLOW}→${NC} 📁 ${CYAN}$dir/${NC} (이미 존재)"
  fi
done

echo ""

# --- CLAUDE.md 생성/업데이트 ---
if [ -f "CLAUDE.md" ] && [ "$ADOPT_MODE" = true ]; then
  # 기존 프로젝트: AXIS 섹션만 추가
  if grep -q "AXIS Engineering" CLAUDE.md 2>/dev/null; then
    echo -e "  ${YELLOW}→${NC} 📄 ${CYAN}CLAUDE.md${NC} — AXIS 섹션이 이미 존재합니다."
  else
    cat >> CLAUDE.md << 'AXIS_SECTION'

## AXIS Engineering

이 프로젝트는 AXIS Engineering 방법론을 따른다.

### Commands
| 커맨드 | 설명 |
|--------|------|
| `/next` | 다음 할 일 추천 |
| `/plan 기능명` | CPS Plan 문서 작성 |
| `/xv "질문"` | 멀티 AI 교차검증 |
| `/design 기능명` | CPS Design 문서 작성 |
| `/gap 설계.md 코드/` | 역방향 검증 |
| `/review 코드` | 코드 리뷰 |
| `/propose 패턴` | 규칙 제안 |
| `/metrics` | 도입 수준 측정 |
| `/team 프리셋` | Agent Teams 병렬 구성 |
| `/axis-update` | AXIS Kit 최신 버전으로 업데이트 |

### Workflow Hint
- 작업이 끝나면 `/next`를 실행하여 다음 단계를 확인한다.
- 설계 판단이 필요하면 `/xv`로 교차검증한다.

### 합의 프로토콜
- 90%+ → 자동 채택
- 70~89% → 사람 판단
- 70% 미만 → 재정의 필요
AXIS_SECTION
    echo -e "  ${GREEN}✓${NC} 📄 ${CYAN}CLAUDE.md${NC} — AXIS 섹션 추가 완료 (기존 내용 유지)"
  fi
elif [ -f "CLAUDE.md" ]; then
  echo -e "  ${YELLOW}⚠️  CLAUDE.md가 이미 존재합니다. 건너뜁니다.${NC}"
  echo -e "     기존 프로젝트에 도입하려면: ${YELLOW}\$ bash scripts/init.sh --adopt $PROJECT_NAME${NC}"
else
  TECH_SECTION=""
  if [ -n "$TECH_STACK" ]; then
    TECH_SECTION="- $TECH_STACK"
  else
    TECH_SECTION="- (기술 스택을 여기에 작성)"
  fi

  cat > CLAUDE.md << TMPL
# ${PROJECT_NAME}

{프로젝트 한 줄 설명을 여기에 작성}

## Language

- Claude는 사용자에게 항상 **${LANGUAGE}**로 응답한다.

## AXIS Engineering

이 프로젝트는 AXIS Engineering 방법론을 따른다.

### Commands
| 커맨드 | 설명 |
|--------|------|
| \`/next\` | 다음 할 일 자동 추천 |
| \`/plan 기능명\` | CPS Plan 문서 작성 |
| \`/xv "질문"\` | 멀티 AI 교차검증 |
| \`/design 기능명\` | CPS Design 문서 작성 |
| \`/gap 설계.md 코드/\` | 역방향 검증 |
| \`/review 코드\` | 코드 리뷰 |
| \`/team 프리셋\` | Agent Teams 병렬 구성 |
| \`/axis-update\` | AXIS Kit 최신 버전으로 업데이트 |

### Workflow
\`\`\`
기능 요청 → /plan → /xv (필요시) → /design → 구현 → /gap → /review
\`\`\`

### 합의 프로토콜
- 90%+ → 자동 채택
- 70~89% → 사람 판단
- 70% 미만 → 재정의 필요

## Tech Stack

${TECH_SECTION}

## Project Structure

\`\`\`
${PROJECT_NAME}/
├── src/              # 소스 코드
├── docs/
│   ├── plans/        # CPS Plan 문서
│   ├── designs/      # CPS Design 문서
│   ├── decisions/    # 의사결정 기록 (ADR)
│   ├── verifications/ # 교차검증 결과
│   └── templates/    # 문서 템플릿
├── scripts/          # AXIS 스크립트
└── .env              # API 키 (git 추적 금지)
\`\`\`

## Conventions

### Git
\`\`\`
feat: 새 기능      | fix: 버그 수정
update: 기능 개선  | docs: 문서 변경
refactor: 리팩토링 | chore: 설정/기타
\`\`\`

## Human-AI Boundary

| 영역 | AI 담당 | 인간 담당 |
|------|---------|----------|
| 코드 생성 | 초안 작성, 패턴 적용 | 아키텍처 결정, 비즈니스 판단 |
| 검증 | 자동 테스트, 갭 탐지 | 최종 승인, 엣지 케이스 판단 |
| 규칙 관리 | 패턴 감지, 규칙 제안 | 승인/거부, 방향성 결정 |
| 문서화 | 초안 생성, 동기화 유지 | 의도/맥락 기술 |

## Credentials

- **절대 git 커밋 금지**: \`.env\`, \`.secret/\`, \`*.pem\`, \`*accessKeys*\`
TMPL

  echo -e "  ${GREEN}✓${NC} 📄 ${CYAN}CLAUDE.md${NC} 생성"
fi

echo ""

# --- .gitignore 업데이트 ---
GITIGNORE_ENTRIES=(
  ".env"
  ".secret/"
  "*.pem"
  "*accessKeys*"
)

ADDED=0

if [ ! -f ".gitignore" ]; then
  touch .gitignore
  echo -e "  ${GREEN}✓${NC} 📄 ${CYAN}.gitignore${NC} 생성"
fi

# AXIS 섹션 헤더 추가 여부 확인
if ! grep -q "# AXIS Engineering" .gitignore 2>/dev/null; then
  echo "" >> .gitignore
  echo "# AXIS Engineering" >> .gitignore
fi

for entry in "${GITIGNORE_ENTRIES[@]}"; do
  if ! grep -qF "$entry" .gitignore 2>/dev/null; then
    echo "$entry" >> .gitignore
    ADDED=$((ADDED + 1))
  fi
done

if [ "$ADDED" -gt 0 ]; then
  echo -e "  ${GREEN}✓${NC} 📄 ${CYAN}.gitignore${NC} 업데이트 (${BOLD}${ADDED}개${NC} 항목 추가)"
else
  echo -e "  ${YELLOW}→${NC} 📄 ${CYAN}.gitignore${NC} (변경 없음)"
fi

# --- 완료 ---
echo ""
divider
echo -e "${GREEN}  ✅ AXIS Kit 초기화 완료: ${BOLD}${PROJECT_NAME}${NC}"
divider
echo ""
if [ "$ADOPT_MODE" = true ]; then
  echo -e "${BOLD}👉 다음 단계:${NC}"
  echo ""
  echo -e "  1. 🧭 현재 상태 진단 + 다음 할 일 확인"
  echo -e "     ${YELLOW}\$ /next${NC}"
  echo ""
  echo -e "${BOLD}🔄 익숙해지면 추가 커맨드 설치:${NC}"
  echo -e "     ${YELLOW}\$ curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash${NC}"
  echo ""
else
  echo -e "${BOLD}👉 다음 단계:${NC}"
  echo ""
  echo -e "  1. 📝 ${CYAN}CLAUDE.md${NC}를 열어 프로젝트 설명과 기술 스택을 채우세요"
  echo ""
  echo -e "  2. 🧭 다음 할 일 확인"
  echo -e "     ${YELLOW}\$ /next${NC}"
  echo ""
fi
