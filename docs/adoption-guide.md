# AXIS Kit 도입 가이드

> 기존 프로젝트에 AXIS를 도입하는 3가지 방법과 단계별 전략

---

## TL;DR — 어떻게 설치하나요?

```bash
# 방법 1: 최소 설치 (핵심 3개 커맨드만 — 권장 시작점)
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --minimal

# 방법 2: 전체 설치 (11개 커맨드 + 스크립트 + 템플릿 + 가이드)
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash

# 방법 3: 직접 복사 (원하는 것만 골라서)
cp axis-kit/.claude/commands/next.md your-project/.claude/commands/
cp axis-kit/.claude/commands/plan.md your-project/.claude/commands/
cp axis-kit/.claude/commands/review.md your-project/.claude/commands/
```

설치 후:
```bash
# 기존 CLAUDE.md에 AXIS 섹션 추가 (기존 내용 유지)
bash scripts/init.sh --adopt my-project

# 바로 시작
/next   # 다음 할 일 확인
```

---

## 처음이라면: 2~3개 커맨드부터

AXIS는 11개 커맨드를 제공하지만, **처음부터 전부 쓸 필요 없습니다.**

### 추천 시작 세트

| 커맨드 | 하는 일 | 왜 먼저? |
|--------|---------|---------|
| `/next` | 다음 할 일 추천 | 뭘 해야 할지 바로 알 수 있음 |
| `/plan` | CPS Plan 문서 작성 | 기능 시작 전 구조화된 사고 |
| `/review` | 코드 리뷰 | 구현 후 바로 품질 점검 |

이 3개만으로 AXIS의 핵심 가치(구조화 + 검증)를 체험할 수 있습니다.

### 익숙해지면 추가

| 단계 | 추가 커맨드 | 효과 |
|------|------------|------|
| 2단계 | `/design`, `/gap` | 설계 문서 + 역방향 검증 |
| 3단계 | `/xv` | 멀티 AI 교차검증 |
| 4단계 | `/propose`, `/metrics` | 규칙 진화 + 도입 수준 측정 |

---

## 기존 프로젝트 도입 (비파괴적)

### 원칙: 기존 설정을 존중한다

- **덮어쓰지 않는다** — 기존 CLAUDE.md를 교체하지 않고 섹션을 추가
- **충돌하지 않는다** — 기존 컨벤션/린터 규칙과 공존
- **점진적으로 적용한다** — 한 번에 전부가 아니라, 필요한 것부터

### Step 1: 설치

```bash
# 최소 설치 (핵심 3개만)
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --minimal

# 또는 전체 설치
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash
```

### Step 2: 기존 CLAUDE.md에 AXIS 섹션 추가

```bash
bash scripts/init.sh --adopt my-project
```

기존 CLAUDE.md를 **교체하지 않고**, 아래 섹션만 추가합니다:

```markdown
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

### Workflow Hint
- 작업이 끝나면 `/next`를 실행하여 다음 단계를 확인한다.
- 설계 판단이 필요하면 `/xv`로 교차검증한다.

### 합의 프로토콜
- 90%+ → 자동 채택
- 70~89% → 사람 판단
- 70% 미만 → 재정의 필요
```

### Step 3: 바로 시작

```bash
/next   # 현재 상태 진단 + 다음 할 일 추천
```

### Step 4: docs 디렉토리 확장 (선택)

기존 docs 구조가 있다면, 충돌하지 않게 AXIS용 하위 디렉토리만 추가합니다:

```bash
mkdir -p docs/plans docs/designs docs/decisions docs/verifications
```

기존 `docs/architecture.md`, `docs/api.md` 등은 그대로 유지됩니다.

### Step 5: API 키 설정 (교차검증용, 선택)

`/xv` 교차검증을 사용하려면:

```bash
cat > .env << 'EOF'
ANTHROPIC_API_KEY="your-key"
OPENAI_API_KEY="your-key"
GEMINI_API_KEY="your-key"
EOF
```

> `/next`, `/plan`, `/review` 등 대부분의 커맨드는 API 키 없이 동작합니다.

---

## 신규 프로젝트 도입

```bash
# 1. 전체 설치
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash

# 2. 초기화
bash scripts/init.sh my-project "Next.js + TypeScript"

# 3. .env 설정 (교차검증용)
cat > .env << 'EOF'
ANTHROPIC_API_KEY="your-key"
OPENAI_API_KEY="your-key"
GEMINI_API_KEY="your-key"
EOF

# 4. 시작
/next
```

---

## 기존 CLAUDE.md와의 공존 패턴

### 패턴 A: 섹션 추가 (권장)
기존 CLAUDE.md 끝에 `## AXIS Engineering` 섹션을 추가.
기존 내용 전혀 수정하지 않음. `--adopt` 모드가 이 방식.

### 패턴 B: 별도 파일
CLAUDE.md는 건드리지 않고, `.claude/commands/` 안의 커맨드로만 AXIS를 사용.
CLAUDE.md에 AXIS 인식이 없어도 커맨드 자체는 동작함.

### 패턴 C: 단계적 마이그레이션
1주차: 커맨드만 사용 (CLAUDE.md 수정 없음)
2주차: AXIS 섹션 추가
3주차: 기존 문서를 CPS 구조로 점진적 전환
4주차: `/metrics`로 평가, 부족한 부분 보강

---

## 업데이트

이미 설치된 AXIS Kit을 최신 버전으로 업데이트:

```bash
curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --update
```

커맨드와 스크립트만 업데이트하고, 템플릿/가이드 등 커스터마이징한 파일은 보존합니다.

---

## FAQ

**Q: 기존 CLAUDE.md의 Convention 섹션이 AXIS와 다른데?**
A: 기존 컨벤션을 유지하세요. AXIS는 특정 컨벤션을 강제하지 않습니다. git 커밋 접두사(feat/fix/...)는 권장 사항이지, 필수가 아닙니다.

**Q: 이미 다른 AI 도구(Cursor Rules 등)를 쓰고 있는데?**
A: 공존 가능합니다. AXIS 커맨드는 `.claude/commands/`에만 있으므로, 다른 도구와 충돌하지 않습니다. 교차검증(`/xv`)은 오히려 다른 도구와 병행하면 효과적입니다.

**Q: 팀원들도 AXIS를 써야 하나?**
A: 선택입니다. 한 사람만 써도 효과가 있습니다. 팀 전체 도입 시에는 CLAUDE.md에 AXIS 섹션을 커밋하면 됩니다.

**Q: API 키가 없어도 쓸 수 있나?**
A: 네. `/xv`(교차검증)만 API 키가 필요합니다. `/next`, `/plan`, `/design`, `/gap`, `/review` 등은 API 키 없이 동작합니다.
