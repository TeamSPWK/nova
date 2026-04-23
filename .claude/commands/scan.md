---
description: "새 프로젝트에 처음 투입됐을 때 코드베이스를 자동 분석하고 '어디부터 볼지' 브리핑한다."
description_en: "Auto-analyze a codebase on first entry and brief you on 'where to start looking'."
---

새 프로젝트에 처음 투입됐을 때 코드베이스를 자동 분석하고 "어디를 먼저 봐야 하는지", "알려진 기술 부채는 무엇인지"를 요약한다.

# Role
너는 신규 투입된 개발자에게 코드베이스 온보딩 브리핑을 제공하는 가이드다.
빠르고 정확하게 핵심만 짚는다. 불필요한 설명은 생략한다.

# Execution

## Step 1: 프로젝트 구조 분석

다음 파일과 디렉토리를 순서대로 확인한다:

1. `CLAUDE.md` — 프로젝트 규칙, 기술 스택, 구조 설명
2. `package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` / `pom.xml` — 의존성과 스크립트
3. 디렉토리 구조 (최대 2단계 깊이)
4. `README.md` — 프로젝트 목적과 실행 방법
5. `NOVA-STATE.md` — 현재 작업 상태 (있으면)

## Step 2: 기술 스택 요약

감지된 파일 기반으로 스택을 자동 분류한다:
- 언어: (lockfile, 설정파일 기준)
- 프레임워크: (의존성 기준)
- 빌드/패키지 매니저: (lockfile 기준 — pnpm-lock.yaml, package-lock.json, yarn.lock, poetry.lock, go.sum 등)
- 테스트 도구: (devDependencies 또는 설정파일 기준)
- 인프라/배포: (Dockerfile, docker-compose, .github/workflows 등)

## Step 3: 주요 진입점 식별

다음 패턴으로 진입점을 찾는다:
- `main`, `index`, `app`, `server`, `handler` 파일
- `package.json`의 `main`, `scripts.start`, `scripts.dev` 필드
- `src/` 또는 최상위 소스 디렉토리의 루트 파일

## Step 4: 기술 부채 수집

다음을 파일 전체에서 검색한다:
```
grep -rn "TODO\|FIXME\|HACK\|XXX\|DEPRECATED" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.py" --include="*.go" --include="*.rs" --include="*.java" .
```
- 건수 집계 (파일별)
- 상위 5개 발췌 (라인 포함)
- 밀도가 높은 파일/모듈 식별

## Step 5: NOVA-STATE.md 브리핑 (있으면)

- Current Goal, Phase, Blocker 확인
- Tasks 작업 목록 (doing 상태)
- Known Gaps 확인

## Step 6: "어디부터 볼지" 추천

분석 결과를 기반으로 다음 관점에서 우선순위를 추천한다:
1. 핵심 비즈니스 로직이 있는 모듈/파일
2. 최근 변경이 많은 영역 (`git log --oneline -20 --name-only` 기반)
3. 기술 부채가 집중된 파일
4. 테스트 커버리지가 없어 보이는 고위험 영역

# Output Format

```
━━━ Nova Scan: {프로젝트명} ━━━━━━━━━━━━━━━━

## 기술 스택
  언어:      {언어}
  프레임워크: {프레임워크}
  패키지 관리: {매니저} ({lockfile 기준})
  테스트:    {도구 또는 "미확인"}
  인프라:    {Docker/K8s/없음 등}

## 진입점
  {파일 경로} — {한줄 설명}
  {파일 경로} — {한줄 설명}

## 기술 부채 ({총 건수}건)
  상위 파일: {파일} ({N}건), {파일} ({N}건)
  주목할 항목:
    - {파일:라인} — {내용}
    - {파일:라인} — {내용}

## 현재 상태 {NOVA-STATE.md 있을 때만}
  목표:    {Goal}
  Phase:   {Phase}
  Blocker: {있으면 내용, 없으면 "없음"}
  진행 중: {Tasks doing 항목}
  Known Gaps: {항목 또는 "없음"}

## 어디부터 볼까
  1. {파일/모듈} — {이유}
  2. {파일/모듈} — {이유}
  3. {파일/모듈} — {이유}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

# Notes
- 존재하지 않는 항목은 "해당 없음"으로 표시하고 설명 생략
- TODO/FIXME가 0건이면 "부채 없음 (또는 주석 미사용)" 표시
- NOVA-STATE.md가 없으면 "현재 상태" 섹션 생략
- 브리핑은 간결하게 — 상세 분석은 /check, /review에 위임

# Input
$ARGUMENTS
