---
plan_id: status-dashboard
title: Status Dashboard (`/nova:status` — 현황 대시보드 + drift 알람)
sprint: S5 (Phase 2 — ROADMAP 통합)
created: 2026-05-13
current_phase: P5
current_sprint: S5
phases:
  - {id: P1, title: Plan, status: done, summary: "CPS 4섹션 + Sprint 분할 4"}
  - {id: P2, title: Design, status: done, summary: "frontmatter 스키마 + JSON 인터페이스 + 5분류 매트릭스"}
  - {id: P3, title: "Phase 1 — 도구 빌드 (S1·S2·S3·S4)", status: done, summary: "build/render/template/회귀 17개 + dogfooding nova/zippit/swk-gc"}
  - {id: P4, title: "Phase 1 통합 (S4 흡수)", status: done, summary: "commands·skills·hooks·tests·guide·nova-meta 동기화 — 743/743 PASS"}
  - {id: P5, title: "Phase 2 — ROADMAP 통합 + init wizard", status: in_progress, summary: "S5·S6·S7·S8. ROADMAP.md 표준 SOT + LLM init wizard + stale 검증"}
  - {id: P6, title: "Phase 2 통합 + 릴리스", status: pending, summary: "review PASS + minor 버전(v5.33 또는 v5.34)"}
sprints:
  P3:
    - {id: S1, title: "frontmatter 스키마 + HTML 템플릿 모듈", status: done}
    - {id: S2, title: "파서 + 데이터 빌더", status: done}
    - {id: S3, title: "HTML 렌더 + 토스식 카드 + drift 카드", status: done}
    - {id: S4, title: "통합 + 회귀 가드 + 가이드 (릴리스 제외)", status: done}
  P5:
    - {id: S5, title: "ROADMAP frontmatter 스키마 + Design 확장", status: in_progress}
    - {id: S6, title: "build-status.py: ROADMAP + 멀티 plan + stale", status: pending}
    - {id: S7, title: "init wizard (CLI + Agent subagent)", status: pending}
    - {id: S8, title: "통합 + 회귀 + 가이드 + dogfooding", status: pending}
goals:
  - {id: G-Build, title: "파서 + 데이터 빌더 (Phase 1)", paths: ['scripts/build-status.sh', 'scripts/lib/build-status.py'], status: done}
  - {id: G-Render, title: "HTML 렌더 + 카드 (Phase 1)", paths: ['scripts/render-status.sh', 'templates/status-dashboard/**'], status: done}
  - {id: G-Integration, title: "커맨드/스킬/훅 통합 (Phase 1)", paths: ['commands/status.md', 'skills/status-dashboard/**', 'hooks/session-start.sh', 'commands/next.md'], status: done}
  - {id: G-Tests, title: "회귀 + 가이드 (Phase 1)", paths: ['tests/test-scripts.sh', 'tests/fixtures/status-dashboard/**', 'docs/guides/status-dashboard.md'], status: done}
  - {id: G-Roadmap, title: "ROADMAP.md 표준 SOT + 멀티 plan 통합 + stale (Phase 2)", paths: ['scripts/lib/build-status.py', 'docs/designs/status-dashboard.md'], status: in_progress}
  - {id: G-InitWizard, title: "init wizard 3 모드 (빈 템플릿 / LLM 초안 / docs 스캔) (Phase 2)", paths: ['scripts/init-roadmap.sh', 'scripts/lib/init-roadmap.py'], status: pending}
  - {id: G-Dogfood, title: "nova → swk-ground-control 적용 (Phase 2)", paths: ['ROADMAP.md', 'docs/ROADMAP.md'], status: pending}
related:
  - docs/designs/status-dashboard.md
  - skills/status-dashboard/SKILL.md
  - commands/status.md
  - scripts/build-status.sh
  - scripts/render-status.sh
references:
  - https://github.com/bgervin/spec-kit-sync  # 5분류 차용 (aligned/drifted/unspecced/unverifiable/conflict)
  - https://docs.astro.build/en/guides/content-collections/  # frontmatter SOT + 빌드 시점 검증
  - https://backstage.spotify.com/docs/portal/core-features-and-plugins/catalog  # "aggregator, not SOT" 격언
  - https://www.conventionalcommits.org/en/v1.0.0/  # commit tag 정규식 기반
  - https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/using-keywords-in-issues-and-pull-requests  # closing keywords 9개 패턴
  - https://tailwindcss.com/docs/installation/play-cdn  # stand-alone HTML
  - docs/verifications/2026-05-13-맥락-Claude-Code-Codex-같은-AI-에이전트에게-작업을-위.md  # 멀티 AI 자문 (합의 95%)
---

# [Plan] Status Dashboard (`/nova:status` — 현황 대시보드 + drift 알람)

> Nova Engineering — CPS Framework
> 작성일: 2026-05-13
> Design: docs/designs/status-dashboard.md (Plan 승인 후 작성)

---

## Context

`/nova:status`는 어느 프로젝트 루트에서든 호출하면 **stand-alone HTML 1개**를 생성해 (1) Phase 시계열 progress bar (2) 현재 Phase의 Sprint 리스트 (3) 그룹별 진행률 bar (4) drift 알람 카드를 보여주는 Nova 스킬이다.

도입 배경:
- Claude Code/Codex 등 AI 에이전트 위임 빈도 증가 → "원래 계획 vs 실제 진행" 시야 부족 → 사용자 판단 시점 놓침
- 멀티 프로젝트 운영자는 노션/wiki에 진행률을 손으로 입력 → sync drift 영구화
- swk-ground-control 레포에서 선행 구현 완료 (Phase bar + Sprint list + 그룹 진행률 + drift 감지 휴리스틱) — Nova 범용 플러그인 사용자에게 동일 가치를 제공하기 위해 일반화 필요
- Nova `NOVA-STATE.md`는 50줄 세션 맥락 (drift/로드맵 추적은 별도 차원)

근거:
- 멀티 AI 자문 결과 합의율 95% (Claude/GPT/Gemini) — frontmatter SOT + git log path-glob 매칭 결정론 패턴
- 외부 레퍼런스 조사 — spec-kit-sync(bgervin)가 거의 동일 영역 OSS 선행 사례. LLM judge 의존이 약점, Nova는 결정론 파싱으로 차별화 가능
- 사용자 직감 — "AI에게 위임한 작업이 원래 계획에서 얼마나 벗어났는지를 git 기록 하나로 5초 안에 보여주는 도구"

---

## Problem

핵심 문제: **사용자가 프로젝트 현황과 AI 작업 결과를 결정론적으로 한 눈에 파악할 수단이 없다.**

문제 분해:

| # | 영역 | 설명 | 영향도 |
|---|------|------|--------|
| 1 | 현황 가시화 부재 | Phase / Sprint / 그룹별 진행률을 한 화면에 볼 도구 없음 | 높음 |
| 2 | 노션/wiki sync drift | 손으로 입력한 진행률이 실제 코드와 어긋남 → 회의에서 "왜 75%? 안 끝났던데" | 높음 |
| 3 | AI 위임 drift 감지 부재 | AI가 의도 밖 작업 시 사용자 알람 없음 → 시간 소비 후 발견 | 높음 |
| 4 | 결정론 보장 한계 | 마크다운 휴리스틱은 정확도 60~70% (선행 구현 실측) → 95%+ 필요 | 중간 |
| 5 | SOT 단일화 | 별도 metadata 파일을 또 만들면 sync 부담 재현 (NOVA-STATE + ROADMAP + meta = 3 SOT) | 중간 |
| 6 | AI에게 줄 객관적 피드백 부재 | "왜 자꾸 엉뚱한 데 손대?" 같은 막연한 불만 → AI 학습 루프 약함 | 중간 |

---

## Solution Overview

해결 방식은 **단일 SOT(plan frontmatter) + 결정론 파싱 + stand-alone HTML 시각화**다.

### 1. SOT — plan frontmatter 1개

`docs/plans/<slug>.md`의 YAML frontmatter를 단일 SOT로 사용. 별도 metadata 파일 0개.

- **Astro Content Collections 패턴** 차용 — frontmatter = 구조화 메타, 본문 = 사람이 쓰는 서사
- **Backstage 격언** 적용 — frontmatter는 aggregator, **실제 진실은 git/코드**. 두 소스의 불일치 자체가 drift 신호
- 빌드 시점 스키마 검증 (Zod-style) — 잘못된 frontmatter는 시작부터 차단

### 2. 결정론 파서

- YAML parser (yq 또는 Node 내장) → frontmatter 추출
- fast-glob → `groups[].paths` 매칭 파일 수 카운트 (진행률 결정론)
- `git log --name-only --grep` → commit tag(`Plan: <id>` / `Goal: G1`) 정규식 추출 + path 매칭

### 3. 시각 3종 + drift 레이어

| 시각 요소 | 데이터 출처 | 시각 모티프 |
|-----------|------------|------------|
| ① Phase 시계열 progress bar | `phases[]` 배열의 `status` 필드 | 7단 점·선 (선행 구현 이미지 1 상단) |
| ② Sprint 리스트 | `sprints[current_phase][]` | 체크리스트 + 진행중 화살표 (이미지 1 하단) |
| ③ 그룹별 진행률 | `groups[].target` + paths glob count | 좌측 큰 숫자 + 우측 bar grid (이미지 2) |
| ④ drift 알람 카드 | git log + path 매칭 5분류 | aligned / drifted / unspecced / unverifiable / conflict |

①~③이 **본체(현황 대시보드)**, ④는 그 위에 얹는 **시각 알람 레이어**.

### 4. drift 5분류 (spec-kit-sync 차용)

| 분류 | 정의 | false positive 대응 |
|------|------|---------------------|
| **aligned** | commit tag 있음 + paths 일치 | — |
| **drifted** | commit tag 있음, paths 어긋남 | 임계 30% 미만은 amber |
| **unspecced** | commit tag 없음, 추적 불가 | `tag-missing` 별도 버킷 분리 |
| **unverifiable** | tag 있으나 path 검증 불가 (테스트 부족) | 사용자 검수 카드로 분리 |
| **conflict** | 여러 goal에 동시 매핑 | spec 충돌 알람 |

### 5. 출력 — stand-alone HTML

- `.nova/status/index.html` 위치 (default)
- `<script src="https://cdn.tailwindcss.com">` 1줄 + `<script>const DATA={...}</script>` inline JSON
- 외부 fetch 0 → `file://` 완전 동작
- 의존성 0 (Node·jq·git 외에는 빌드 단계 없음)

### 6. 트리거 3단

| 트리거 | 동작 |
|--------|------|
| `/nova:status` 명시 호출 | 전체 리포트 재생성 (기본) |
| PostToolUse hook (옵션) | drift 임계 초과 시 `.nova/intervention-queue.jsonl` append + HTML 갱신 |
| SessionStart hook | drift 점수 1줄 표시 (lean 모드 영향 0 — soft 1200 안) |

### 7. 커밋 컨벤션 (CLAUDE.md 룰 1개로 강제)

```
feat: drift 감지 결정론 로직

Plan: status-dashboard
Goal: G1
```

- release-please/conventional commits + GitHub closing keywords 9개 정규식 모범 차용
- Soft 강제 (놓치면 `tag-missing` 분류, 차단 아님)
- AI 에이전트는 CLAUDE.md 룰 1줄 읽고 자동 동참

---

## Sprint 분할

### Sprint S1 — Design + frontmatter 스키마 + HTML 템플릿

범위:
- `docs/designs/status-dashboard.md` 작성 (Astro Zod 스타일 스키마 + 5분류 매트릭스 + HTML 템플릿 명세)
- `templates/status-dashboard/index.html` — Tailwind Play CDN + inline JSON 패턴, 빈 데이터로 렌더 PASS
- 데이터 계약 (`StatusData` JSON 인터페이스) freeze

Done Criteria:
- Design 문서 freeze
- 빈 데이터로 HTML 렌더 시 빈 카드 grid 정상 표시
- swk-ground-control 이미지 1·2와 시각 동일성 fixture 1차 확인

### Sprint S2 — 파서 + 데이터 빌더

범위:
- `scripts/build-status.sh` — YAML frontmatter 파싱 + fast-glob count + git log path 매칭 → JSON
- graceful degradation 로직 (frontmatter 미작성 / group target 미선언 / commit tag 누락)
- 단위 테스트 — fixture 3종 (minimal / full / swk-replica)

Done Criteria:
- 결정론 95%+ 입증 — 동일 입력 → 동일 JSON (10회 반복 동일)
- 5분류 매핑 PASS (5개 fixture 시나리오)
- graceful degradation — frontmatter 0 keys 입력 시 빈 JSON 반환, crash 0건

### Sprint S3 — HTML 렌더 + 토스식 카드 + drift 카드

범위:
- `scripts/render-status.sh` — JSON → HTML (templates 인플레이스)
- 시각 3종 (Phase bar 7단 / Sprint 리스트 / 그룹 진행률 bar) 구현
- drift 카드 5분류 시각 매핑 (color: green<30% / amber 30~70% / red>70%)

Done Criteria:
- swk-ground-control 이미지 1·2와 1:1 시각 동일성 (스크린샷 비교 PASS)
- file:// 환경에서 모든 카드 정상 렌더
- drift 카드 5분류 색상·아이콘 매핑 PASS

### Sprint S4 — 통합 + 회귀 가드 + 가이드 + 릴리스

범위:
- `commands/status.md` — `/nova:status` 슬래시 커맨드 진입점
- `skills/status-dashboard/SKILL.md` — 스킬 정의 (MUST TRIGGER 명세)
- `hooks/session-start.sh` — drift 1줄 표시 + 커맨드 목록 추가
- `commands/next.md` — 워크플로우 추천 경로 추가
- `tests/test-scripts.sh` — EXPECTED_COMMANDS + 회귀 가드
- `docs/guides/status-dashboard.md` — 사용자 가이드 (TL;DR + 절차 + FAIL 시 + cheatsheet)
- `scripts/generate-meta.sh` 자동 호출로 `nova-meta.json` 동기화
- README 테이블 자동 갱신

Done Criteria:
- 모든 회귀 테스트 PASS
- `/nova:review --fast` PASS
- swk-ground-control에서 dogfooding (현재 페이지와 병렬 운영) PASS
- minor 버전 릴리스 (예: v5.33.0)

---

## Sprint Done Criteria 요약

| Sprint | 완료 조건 |
|--------|----------|
| S1 | Design freeze + 빈 HTML 렌더 + 데이터 계약 freeze |
| S2 | 결정론 95%+ + 5분류 매핑 + graceful degradation |
| S3 | 이미지 1·2 1:1 시각 동일성 + file:// 작동 + 5분류 색상 |
| S4 | 회귀 PASS + dogfooding PASS + 릴리스 |

---

## Design

세부 계약(frontmatter 스키마 / JSON 인터페이스 / HTML 템플릿 / 5분류 매트릭스)은 아래 문서를 단일 진실원으로 사용한다.

- `docs/designs/status-dashboard.md` (Plan 승인 후 작성)

---

## Risk

### 1) plan frontmatter 미작성 — 무가치 위험

위험:
- 기존 plan에 frontmatter 없거나 부족하면 빈 페이지 → 사용자 효용 0
- 외부 Nova 사용자는 plan 자체를 안 쓸 수 있음

완화:
- **graceful degradation** — frontmatter 0이면 "minimal mode" (제목 + Last Activity body만)
- `/nova:plan` 커맨드가 새 frontmatter 스키마를 기본 채움 (별도 PR)
- 가이드 문서 첫 줄 — "이 도구는 `/nova:plan` 산출물과 짝"

### 2) group target 미선언 — false 진행률 위험

위험:
- target 없으면 진행률 계산 불가 → 임의 추정 시 false 0건 보장 X

완화:
- target 미선언 group은 "선언 필요" 카드로 표시 + 추정 진행률 0 표시 X
- 추정 X = 정직성 우선

### 3) commit tag 누락 — drift 오인 위험

위험:
- AI/사람이 `Plan: <id>` 태그 안 달면 모든 commit이 drift로 오인 → 알람 폭증

완화:
- `tag-missing` 별도 버킷 분리 (drift 아님)
- CLAUDE.md 룰 1줄로 AI 동참 강제 (soft)
- 임계: drifted+unspecced > 30% 시에만 ⚠️ 카드

### 4) swk-ground-control 시각 차이 — 일반화 brittle

위험:
- 선행 구현의 토스식 UX를 stand-alone HTML로 옮기면서 시각 차이 발생 가능
- 사용자 검증 기준: 이미지 1·2와 동일

완화:
- Sprint S1에서 이미지 1·2를 fixture로 freeze
- Sprint S3에서 스크린샷 1:1 비교 (Playwright MCP 사용 가능 시)
- 차이 발견 시 템플릿 surgical 수정

### 5) file:// 환경 fetch 0 — CORS 제약

위험:
- 외부 JSON fetch는 file:// 에서 차단됨

완화:
- 모든 데이터는 `<script>const DATA={...}</script>` inline 임베드
- Tailwind는 Play CDN (file:// 에서도 정상 작동 — 검증됨)
- 외부 fetch 0 강제

### 6) Nova 기존 자산과의 중복

위험:
- `/nova:next`(상태 진단), `/nova:scan`(브리핑), `context-chain`(NOVA-STATE 관리)와 정체성 충돌

완화:
- 역할 명확 분리:
  - `/nova:next` — "다음 커맨드 추천" (텍스트 출력, drift 점수 1줄 추가만)
  - `/nova:scan` — "코드베이스 첫 분석" (1회성)
  - `context-chain` — NOVA-STATE.md 50줄 관리 (변경 0)
  - `/nova:status` — **현황 + drift HTML 시각화** (반복 호출)

---

## 검증 포인트

1. **결정론 입증**: 동일 frontmatter + 동일 git 상태 → 동일 JSON (10회 반복 byte-identical)
2. **시각 동일성**: swk-ground-control 이미지 1·2 fixture와 출력 1:1 비교 PASS
3. **graceful degradation**: 빈 frontmatter / 부분 frontmatter / 완전 frontmatter 3종 입력 시 crash 0건
4. **회귀 가드**: `tests/test-scripts.sh` 신규 회귀 케이스 (최소 15개) PASS
5. **계약 정합**: Design 문서의 JSON 인터페이스와 build/render 스크립트 라인 근거 일치
6. **사용자 가이드**: `docs/guides/status-dashboard.md`에 TL;DR + 절차 + FAIL 시 + cheatsheet 모두 포함 (사용자 가이드 블라인드 스팟 메모리 반영)
7. **dogfooding**: swk-ground-control에서 선행 구현과 병렬 운영 → 사용자 효용 동일 또는 ↑

---

## 참고: 외부 레퍼런스 핵심 차용 매핑

| 차용 패턴 | 출처 | Nova 적용 위치 |
|----------|------|---------------|
| 5분류 체계 | spec-kit-sync (bgervin) | drift 레이어 |
| frontmatter SOT + Zod 검증 | Astro Content Collections | plan frontmatter 스키마 |
| "aggregator, not SOT" 격언 | Backstage (Spotify) | frontmatter ↔ git 불일치 = drift 신호 |
| commit tag 정규식 | release-please + GitHub closing keywords 9개 | `Plan: <id>` / `Goal: G1` 파싱 |
| Tailwind Play CDN + inline data | Tailwind 공식 | HTML 템플릿 |
| guides vs sensors | Martin Fowler "Harness Engineering" | CLAUDE.md 룰(guide) + PostToolUse hook(sensor) |

차별점 (spec-kit-sync 대비):
- LLM judge 의존 X → 결정론 파싱
- markdown 출력 X → 토스식 HTML 카드
- 사용자 재실행 의존 X → PostToolUse 자동 트리거

---

## Out of Scope (Sprint S1~S4 범위 외)

- 멀티 프로젝트 통합 대시보드 (각 프로젝트 1개 HTML 우선, 통합은 후속)
- Slack/Discord 알람 (SWK 색채 제거 — 페이지 배지만)
- Next.js `app/status/` 자동 페이지 생성 옵션 (framework-specific 분기 회피)
- `/nova:reconcile` (drift 자동 수정 — spec-kit-reconcile 영감, 후속 스킬 후보)
- 외부 SOT 연동 (Linear/Jira — 네트워크 의존 제약 위반)

---

## Phase 2 (P5) — ROADMAP 통합 + init wizard

> 사용자 통찰 (2026-05-13): *"NOVA-STATE만으로 전체 과정 파악 어렵다. ROADMAP.md 없으면 만들어주고, 있으면 그걸 기반으로."*

근거:
- swk-ground-control: NOVA-STATE 50줄 + `docs/ROADMAP.md` (Phase 12·13·14) + `docs/plans/ao-*.md` 정보 분산. 우리 Phase 1 모델로는 모두 plan frontmatter에 손으로 옮겨야 함
- 멀티 AI 자문 + 사용자 의견 합의: B(멀티 plan) + D(ROADMAP 표준) + C(init wizard) 결합
- 사용자 핵심 지적: 레거시 docs가 오히려 파악 방해 → wizard에 "기존 docs 무시" 옵션 필수

### Sprint S5 — ROADMAP frontmatter 스키마 + Design 확장

범위:
- `ROADMAP.md` frontmatter v1.0 스키마 (roadmap_id / current_phase / phases / external_pending) 정의
- 멀티 plan 통합 규칙 (`docs/plans/*.md` frontmatter에 `parent_phase` 추가)
- stale 검증 정책 (7일+ commit 누락 또는 current_phase ↔ 최근 git 활동 불일치)
- `docs/designs/status-dashboard.md` §4 확장

Done Criteria:
- Design §4 확장 freeze
- ROADMAP.md fixture 1개 (nova 자체 dogfooding 후보)

### Sprint S6 — build-status.py: ROADMAP + 멀티 plan + stale

범위:
- `scripts/lib/build-status.py` 확장 — ROADMAP.md 자동 발견·파싱 + `docs/plans/*.md` 멀티 스캔 + `parent_phase` 그룹핑
- stale 검증 로직 (ROADMAP 마지막 commit + current_phase 일관성)
- 결정론 + graceful degradation 유지 (ROADMAP 부재 시 Phase 1 동작 그대로)

Done Criteria:
- ROADMAP 부재 시 Phase 1 회귀 PASS
- ROADMAP + multi-plan 입력 시 정확한 phase·sprint 통합 출력
- stale 7일+ 시 `stale: true` + alert message
- 결정론 2회 byte-identical

### Sprint S7 — init wizard (CLI + Agent subagent)

범위:
- `/nova:status init` 진입점 + ROADMAP 부재 자동 감지 시 wizard 안내
- 3 모드:
  - (1) 빈 템플릿 — 가장 단순. 레거시 docs 0건 참조
  - (2) LLM 자동 초안 — Agent subagent (메모리 `feedback_api_key_optional_principle` 준수: API 키 0)
  - (3) `docs/plans/*` 스캔 추출 — 휴리스틱 + frontmatter 우선
- 사용자 검수 단계 명시 + commit 안내

Done Criteria:
- ROADMAP 부재 시 wizard 자동 안내
- 3 모드 모두 동작
- LLM 모드 시 외부 API 키 0 보장 (Agent subagent 패턴, visual-self-verify와 동일)
- 초안 사용자 검수 후 명시적 commit (자동 commit 금지)

### Sprint S8 — 통합 + 회귀 + 가이드 + dogfooding

범위:
- HTML 템플릿 stale 배지 추가 (헤더 ⚠️ "ROADMAP 마지막 commit: N일 전")
- `commands/status.md` + `skills/status-dashboard/SKILL.md` init 모드 안내
- `tests/test-scripts.sh` R32 회귀 가드 (≥10 케이스 — ROADMAP 파싱·multi-plan·stale·wizard 3 모드)
- `docs/guides/status-dashboard.md` ROADMAP 섹션 + init wizard 절차 추가
- nova 자체 dogfooding → swk-ground-control dogfooding (Phase 12·13·14 + AO-* sprint 자동 통합 시각 검증)

Done Criteria:
- R31 + R32 모두 PASS
- Phase 1 사용자 흐름 100% 호환 (ROADMAP 없이도 작동)
- swk-ground-control: 우리가 손으로 만든 `/tmp/swk-status.html`과 동등한 결과를 자동 도구로 재현

---

## Risk (Phase 2)

### P2-R1) LLM 초안 정확도 한계 (init wizard)

위험:
- LLM이 만드는 ROADMAP 초안 약 80% 정확도 — 사용자가 검수 없이 commit 시 잘못된 SOT 고착

완화:
- wizard 마지막에 "이대로 commit하시겠습니까?" 명시 확인
- 추론 신뢰도 낮은 항목에 `⚠️ unsure` 자동 마커
- "모르겠음" 항목은 빈 값 강제 (LLM이 추정 채우기 금지)

### P2-R2) 레거시 docs 노이즈 (사용자 핵심 지적)

위험:
- 기존 `docs/plans/` 또는 `ROADMAP.md`에 stale 정보 가득 → LLM이 노이즈 흡수

완화:
- wizard 모드 (1) 빈 템플릿 — 기존 docs 0건 참조 (사용자 선택권)
- `docs/.archive/`, `archived/`, `*.deprecated.md` 자동 제외
- "최근 N일 활동" (default 30일) 기준만 사용하는 옵션

### P2-R3) ROADMAP stale 자체

위험:
- `ROADMAP.md` commit이 오래 전 → frontmatter 정보가 현실과 불일치 → dashboard 거짓 정보

완화:
- stale 임계 7일 (사용자 결정)
- dashboard 상단 ⚠️ 배지 + "ROADMAP 마지막 commit: N일 전"
- 차단 X, 안내만

### P2-R4) 멀티 plan parent_phase 매핑 충돌

위험:
- 같은 sprint id가 두 plan에 중복 — 어느 phase에 묶일지 모호

완화:
- 첫 발견 plan 우선 + warning 카드 표시
- spec 명시: sprint id는 프로젝트 전체에서 유니크해야 (검증 규칙 추가)

### P2-R5) Phase 1 호환성

위험:
- ROADMAP 통합 후 기존 single plan 사용자 동작 X

완화:
- ROADMAP 없으면 Phase 1 동작 그대로 (graceful degradation)
- 회귀 가드 R31a~q 100% 유지
- 신규 회귀 R32 = ROADMAP 모드만 추가 검증

---

## 검증 포인트 (Phase 2)

1. ROADMAP frontmatter 결정론 — 동일 ROADMAP + 동일 plans → byte-identical JSON
2. Phase 1 호환성 — ROADMAP 없을 때 기존 결과 100% 동일
3. stale false positive 0 — 7일 이내 commit 있으면 stale 표시 X
4. init wizard 모드 (1) 빈 템플릿 = 5분 부트스트랩
5. init wizard 모드 (2) LLM = 외부 API 키 0 (네트워크 호출 grep 0)
6. 멀티 plan 통합 — parent_phase 결정론 매핑 + 중복 sprint id 경고
7. swk-ground-control dogfooding — Phase 12·13·14 + AO-* sprint 자동 표시 (우리가 손으로 만든 demo와 동등)
