# [Plan] Nova Orchestrator — Level 2 스킬 + Level 3 MCP 서버

> Nova Engineering — CPS Framework
> 작성일: 2026-04-02
> 작성자: Spacewalk Engineering
> Design: docs/designs/nova-orchestrator.md (작성 예정)

---

## Context (배경)

### 현재 상태
- Nova v3.12.0: 12개 커맨드, 4개 스킬, 5개 에이전트 타입
- `/nova:run`은 단일 프로젝트 내에서 구현→검증 사이클을 수행
- 멀티 프로젝트 오케스트레이션은 **사람(또는 숙련된 AI)이 수동으로** 수행
- 오늘 nova-projects 3개 프로젝트를 17개 서브에이전트로 병렬 구현한 경험이 있음

### 왜 필요한가
- Nova 프로젝트 내에서 작업할 때는 모든 맥락이 로드되어 높은 품질이 나옴
- 다른 프로젝트에서 작업할 때는 session-start.sh의 1200자 요약만 주입됨
- **설계→구현 프롬프트 변환**, **에이전트 편성**, **QA→Fix 루프**가 자동화되지 않음
- 오늘 수동으로 한 오케스트레이션 패턴을 코드화하면 어느 프로젝트에서든 재현 가능

### 관련 자료
- 오늘 세션: nova-projects 3개 프로젝트 병렬 생성 (17개 에이전트 투입)
- 기존 스킬: evaluator, jury, field-test, context-chain
- 기존 커맨드: /nova:run (단일 프로젝트 Full Cycle)

---

## Problem (문제 정의)

### 핵심 문제
Nova의 깊은 맥락(CPS 설계, Generator-Evaluator 분리, 오케스트레이션)이 **Nova 프로젝트 밖에서는 충분히 활용되지 못한다.**

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | 설계→프롬프트 변환 자동화 | CPS 설계서를 Dev 에이전트 프롬프트로 자동 변환하는 로직 부재 | 높음 |
| 2 | 멀티 에이전트 편성 | 복잡도에 따른 에이전트 팀 자동 구성 (Architect/Dev/QA/Fix) | 높음 |
| 3 | QA→Fix 루프 자동화 | QA 결과를 파싱하여 Fix 에이전트를 자동 투입하는 로직 부재 | 중간 |
| 4 | 프로젝트 간 맥락 공유 | Nova 프로젝트의 규칙/패턴을 다른 프로젝트에서 풀 로드 | 높음 |
| 5 | 상시 접근성 | 어느 프로젝트에서든 Nova 오케스트레이션을 호출할 수 있어야 함 | 높음 |

### 제약 조건
- Nova는 Claude Code 플러그인 → 스킬/커맨드 체계 내에서 동작
- MCP 서버는 Claude Code의 MCP 통합 프로토콜을 따라야 함
- 기존 12개 커맨드와 충돌하면 안 됨
- 플러그인 업데이트만으로 배포 가능해야 함 (수동 설정 금지)

---

## Solution (해결 방안)

### 선택한 방안
**Level 2 (orchestrate 스킬)와 Level 3 (MCP 서버)를 순차 구현.** Level 2가 오케스트레이션 로직의 코어, Level 3은 그 코어를 MCP 프로토콜로 노출.

### 대안 비교

| 기준 | 방안 A: 스킬만 (Level 2) | 방안 B: MCP 서버만 (Level 3) | 방안 C: 스킬 + MCP (Level 2+3) |
|------|------------------------|---------------------------|-------------------------------|
| 구현 난이도 | 낮음 (기존 스킬 체계) | 중간 (MCP 서버 개발 필요) | 중간 (순차 구현) |
| 접근성 | 플러그인 설치된 곳만 | 어디서든 | 어디서든 + 플러그인 연동 |
| 맥락 깊이 | 스킬 로드 시 1회성 | 상시 풀 맥락 | 상시 풀 맥락 |
| 재사용성 | 스킬 내부 로직 | API로 외부 노출 | 스킬이 MCP를 호출 |
| 선택 | 기각 (접근성 한계) | 기각 (스킬 연동 없음) | **채택** |

### 구현 범위

#### Level 2: `/nova:auto` 스킬
- [ ] 오케스트레이션 SKILL.md 작성
- [ ] 자연어 → CPS 설계 자동 변환 로직
- [ ] 복잡도 기반 에이전트 팀 자동 편성
- [ ] 설계서 → Dev 프롬프트 자동 생성
- [ ] QA 결과 파싱 → Fix 에이전트 자동 투입
- [ ] 멀티 프로젝트 병렬 지원
- [ ] `/nova:auto` 커맨드 등록

#### Level 3: Nova MCP 서버
- [ ] MCP 서버 스캐폴딩 (TypeScript, stdio transport)
- [ ] Nova 규칙 풀텍스트 제공 도구 (get_rules)
- [ ] CPS 설계 생성 도구 (create_plan)
- [ ] 오케스트레이션 실행 도구 (orchestrate)
- [ ] 프로젝트 상태 조회 도구 (get_state → NOVA-STATE.md)
- [ ] 검증 실행 도구 (verify)
- [ ] Claude Code settings.json에 MCP 서버 자동 등록
- [ ] session-start.sh에서 MCP 서버 자동 시작

### 검증 기준
- `/nova:auto "proptech-lab에 건폐율 시각화 추가"` → 설계→구현→QA→Fix 자동 완료
- 다른 프로젝트(nova-landing 등)에서 MCP 도구 호출 가능
- MCP 서버가 Nova 규칙 전문을 반환
- 기존 12개 커맨드와 충돌 없음
- `bash tests/test-scripts.sh` 기존 169개 테스트 통과

---

## Sprints (스프린트 분할)

| Sprint | 기능 단위 | 예상 파일 | 의존성 | Done 조건 |
|--------|----------|----------|--------|----------|
| 1 | auto 스킬 코어 | SKILL.md, auto.md, 커맨드 등록 (4~5파일) | 없음 | `/nova:auto` 호출 → Architect→Dev→QA 사이클 동작 |
| 2 | MCP 서버 구현 | mcp-server/ 디렉토리 (8~10파일) | Sprint 1 | MCP 도구 6개 호출 가능, Claude Code에서 연동 확인 |
| 3 | 통합 + 자동 등록 | session-start.sh, settings.json, plugin.json (3~4파일) | Sprint 2 | 플러그인 설치만으로 MCP 서버 자동 시작 + 스킬 연동 |

---

## 리스크

| 리스크 | 영향도 | 완화 방안 |
|--------|--------|----------|
| MCP 서버가 Claude Code 버전에 종속 | 높음 | stdio transport 표준만 사용, 버전별 호환성 테스트 |
| 오케스트레이션 프롬프트 품질 일관성 | 중간 | 오늘 패턴을 템플릿화, field-test로 검증 |
| MCP 서버 프로세스 관리 (시작/종료) | 중간 | session-start.sh에서 lifecycle 관리 |
| 기존 테스트 169개 깨짐 | 높음 | Sprint별 테스트 추가, 기존 테스트 먼저 통과 확인 |
