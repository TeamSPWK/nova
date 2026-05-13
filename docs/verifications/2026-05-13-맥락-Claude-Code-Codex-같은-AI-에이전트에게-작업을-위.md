# X-Verification: 맥락: Claude Code/Codex 같은 AI 에이전트에게 작업을 위임하는 빈도가 늘면서, "프로젝트 원래 의도(로드맵) vs AI가 실제로

> 날짜: 2026-05-13
> 합의율: 95%
> 판정: auto_approve
> AI: claude, gpt, gemini

## 질문
맥락: Claude Code/Codex 같은 AI 에이전트에게 작업을 위임하는 빈도가 늘면서, "프로젝트 원래 의도(로드맵) vs AI가 실제로 한 일(git log/코드)"의 drift가 발생. 사용자 판단이 필요한 시점을 놓치는 문제.

만들고자 하는 도구: 어느 프로젝트 루트에서든 호출하면 stand-alone HTML 1개를 생성해 (1) 현재 단계 progress bar (2) 카드 grid (목표/지금/다음/백로그/외부승인) (3) drift 알람 배지 를 보여주는 Nova 스킬.

핵심 제약:
1. 하드코딩 금지 — 사용자가 진행률·상태를 수동 갱신하면 안 됨. 단일 SOT에서 모든 게 자동 파생.
2. 휴리스틱 마크다운 파싱은 정확도 60~70% (선행 구현 한계). 95%+ 결정론적 파싱 필요.
3. 외부 의존성 0 (file:// 로 열어도 동작)
4. drift 감지는 false positive 최소화 — 사용자가 알람을 신뢰해야 함
5. 별도 metadata 파일을 또 만들면 SOT가 3개 됨 (NOVA-STATE.md + ROADMAP.md + meta) → sync 문제 재현

후보 방향 평가 + 더 좋은 패턴 제안 요청:

(A) NOVA-STATE.md (이미 존재하는 단일 세션 맥락 파일) frontmatter 표준화 + git log path-glob 매칭으로 drift 결정론 감지
(B) Conventional Commits + 커밋 메시지에 `goal:g1` 같은 태그 강제
(C) AST/코드 분석 기반 — 어느 파일이 어느 goal에 속하는지 코드 자체에서 추론
(D) Linear/Jira 등 외부 SOT 연동 (네트워크 의존 — 제약 위반)
(E) 다른 패턴 (창의적 제안)

업계 레퍼런스 관점에서:
- Linear Cycle Reviews, Notion Project Tracker, Backstage(Spotify), Plane.so 등은 SOT를 어떻게 관리하고 drift를 어떻게 감지하는가?
- Astro/MkDocs 같은 SSG의 frontmatter SOT 패턴이 이 케이스에 어떻게 적용 가능한가?
- "AI agent drift monitor" 같은 새 카테고리 도구가 이미 있는가?

각 후보의 정확도/사용자부담/유지보수성 trade-off + 추천안 + 그 근거. 한국어로 답변.

## claude
## 평가

**(A) NOVA-STATE.md frontmatter + git path-glob** ⭐ 추천 베이스
- 정확도 95%+ (frontmatter는 YAML 파서로 결정론적)
- 사용자 부담: 낮음 (이미 쓰는 파일 확장)
- SOT 1개 유지. SSG(Astro/MkDocs) 패턴과 정확히 일치 — frontmatter=구조화 메타, 본문=서사

**(B) Conventional Commits 태그**: AI 에이전트가 일관되게 따른다는 보장 없음. 사람이 수정 시 부담↑. 보조 신호로만.

**(C) AST 추론**: 정확도 낮고 언어별 구현 폭증. 유지보수 지옥.

**(D) 외부 SOT**: 제약 위반.

## 업계 레퍼런스

- **Linear/Plane**: SOT는 DB지만 drift는 "issue ↔ PR 링크"로 감지 (Magic Link 패턴)
- **Backstage**: `catalog-info.yaml` 단일 frontmatter가 SOT. 코드 위치는 annotation으로 역참조
- **Astro Content Collections**: frontmatter schema(zod)로 결정론 보장
- **AI drift monitor**: 아직 명확한 카테고리 없음. cline, aider가 task 로그를 남기지만 roadmap-drift 비교는 미개척 영역.

## 추천: A + Backstage annotation 패턴 하이브리드

```yaml
---
current: g2
goals:
  g1: {title: "파서 구현", status: done, paths: ["src/parser/**"]}
  g2: {title: "drift 감지", paths: ["src/drift/**", "!**/*.test.ts"]}
  g3: {title: "HTML 렌더", paths: ["src/render/**"], blocked_by: external}
---
```

**Drift 감지 로직** (false positive 최소화):
1. `git log --since=<last_render>` → 변경 파일 목록
2. 각 파일을 goals[*].paths glob으로 매칭
3. **current 외 goal에 매칭 + 매칭 안 됨**이 N회 이상 → drift 배지
4. 진행률 = goal별 커밋 수 / 예상치 아닌, **status 필드 기반** (AI가 완료 시 frontmatter 자체를 수정 — 이게 핵심)

**왜 이게 SOT 1개인가**: AI 에이전트가 작업 종료 시 NOVA-STATE.md frontmatter를 갱신하도록 스킬 프롬프트에 명시. git log는 "검증자"일 뿐 SOT 아님 — frontmatter 선언과 실제 커밋의 **불일치가 곧 drift 신호**. 두 소스가 충돌할 때만 알람이 울리므로 false positive가 구조적으로 낮음.

## gpt
추천: **(E) “문서 내장형 결정론 SOT + Git 증빙”**.  
핵심은 **`NOVA-STATE.md` 하나만 SOT**로 두고, 여기에 **엄격한 frontmatter/schema**를 넣어 `goal_id`, `status`, `acceptance`, `owned_paths`, `needs_approval`를 선언합니다. HTML은 이 문서만 파싱해 progress/card를 만들고, **git diff/log는 SOT 검증용**으로만 씁니다.

평가:
- **A**: 가장 현실적. 정확도 높고(file/path 매칭은 결정론적), 외부 의존성 0. 단, path ownership 관리 필요.
- **B**: 정확도 높지만 사용자/에이전트 discipline 강제 큼. 커밋 누락·squash에 취약.
- **C**: 유지보수성 낮음. 코드→goal 추론은 언어/구조별 예외 많아 false positive 위험.
- **D**: 제약 위반.

권장 drift 규칙:
1) **owned_paths 밖 변경** 발생  
2) `acceptance` 미충족인데 status가 완료  
3) `needs_approval=true` goal 관련 변경 후 승인 기록 없음  
4) backlog goal path에 선행 변경 발생  
→ 이 정도만 알람해 false positive 최소화.

업계적으로 Linear/Jira/Plane는 **이슈 DB가 SOT**, git은 증빙입니다. Backstage도 catalog 메타데이터 중심. SSG(Astro/MkDocs)처럼 **frontmatter를 기계판독 가능한 계약**으로 쓰는 패턴이 여기 가장 적합합니다.  
결론: **A를 기반으로, B를 선택적 보강**(commit tag는 가산점)하는 하이브리드가 최선입니다.

## gemini
후보안 평가 및 추천 아키텍처를 제시합니다.

### 1. 후보 방향 평가
| 구분 | 정확도 | 사용자 부담 | 유지보수성 | 평가 |
| :--- | :---: | :---: | :---: | :--- |
| **(A) Frontmatter+Glob** | 중상 | 낮음 | 높음 | 실용적이나 폴더 구조 변경에 취약 |
| **(B) Conventional Tag** | **최상** | 높음 | 중 | 결정론적이나 AI/인간의 실수 가능성 |
| **(C) AST/코드 분석** | 낮음 | 최저 | 낮음 | 오탐(False Positive) 확률 매우 높음 |

### 2. 추천 패턴: (A)와 (B)를 결합한 **"Living Spec & Git-Goal Mapping"**
단일 SOT인 `ROADMAP.md`(또는 `NOVA-STATE.md`)의 **Frontmatter에 Goal ID와 관련 Scope(Path)를 정의**하고, Git 로그를 통해 이를 검증하는 방식입니다.

**구현 메커니즘:**
1.  **SOT 구조:** Markdown Frontmatter에 `goals: [{id: G1, paths: ["src/auth/*"], status: doing}]` 정의.
2.  **Drift 감지 로직:** 
    *   `git log`를 분석하여 커밋 메시지에 `[G1]` 등 ID가 포함되었는지 확인.
    *   `git diff --name-only`로 수정된 파일이 해당 Goal의 `paths` 범위를 벗어났는지 체크.
3.  **Drift 알람 조건:** ① ID 없는 커밋 발생 시, ② 특정 Goal 작업 중 선언되지 않은 경로의 파일이 수정될 시 발생.

### 3. 추천 근거 및 레퍼런스
*   **근거:** 별도 메타데이터 없이 Markdown 하나로 95% 이상의 결정론적 파싱이 가능하며, AI에게 "커밋 시 ID를 포함하라"는 페르소나 주입만으로 자동화가 완성됩니다.
*   **레퍼런스:** **Backstage**의 `catalog-info.yaml`이 정적 메타데이터로 복잡한 엔티티를 관리하는 방식과 유사하며, **Linear**가 브랜치명/커밋으로 상태를 자동 동기화하는 로직을 로컬 파일 기반으로 이식한 형태입니다. "AI Agent Drift"는 최근 **LangSmith** 등에서 관찰(Observability) 영역으로 다루기 시작한 최신 과제입니다.

## 합의 분석
- **합의율**: 95%
- **판정**: auto_approve
- **요약**: 모든 응답이 Markdown Frontmatter를 설계도로, Git 이력을 검증기로 사용하는 (A)안 기반의 하이브리드 패턴을 최적으로 합의함.

### 공통점
- 단일 SOT로서 Markdown 파일의 Frontmatter(YAML)를 활용하는 구조 제안
- Git log/diff의 변경 파일 목록과 Frontmatter에 정의된 path-glob을 매칭하여 drift를 결정론적으로 감지
- AST 기반 분석(C)이나 외부 도구 연동(D)은 복잡도와 제약 사항으로 인해 부적합하다고 판단
- Backstage의 catalog-info.yaml 또는 Astro의 Content Collections 패턴을 주요 레퍼런스로 인용

### 차이점
- Claude는 AI 에이전트가 작업 완료 시 직접 Frontmatter의 status를 갱신하는 루프를 강조함
- GPT는 acceptance criteria 및 승인 여부(needs_approval) 등 더 상세한 메타데이터 스키마 설계를 제안함
- Gemini는 커밋 메시지에 Goal ID를 태깅하는 방식(B)을 보조적인 검증 수단으로 결합할 것을 권장함
