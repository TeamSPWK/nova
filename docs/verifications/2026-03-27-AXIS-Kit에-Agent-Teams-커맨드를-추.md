# X-Verification: AXIS Kit에 Agent Teams 커맨드를 추가하려 한다. TeamCreate는 Claude Code 내부 도구로, .claude/comm

> 날짜: 2026-03-27
> 합의율: 100%
> 판정: auto_approve
> AI: claude gpt gemini

## 질문
AXIS Kit에 Agent Teams 커맨드를 추가하려 한다. TeamCreate는 Claude Code 내부 도구로, .claude/commands/ 에서 직접 호출할 수 없고 자연어 프롬프트로 유도해야 한다. 설정은 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1이 필요하다. 질문: 1) /team 커맨드를 만들어 프리셋 팀(qa, review, design)을 자연어로 유도하는 방식이 적절한가? 2) install.sh에서 settings.json에 Agent Teams 설정을 자동으로 추가해야 하는가, 아니면 선택 옵션으로 둬야 하는가? 3) 팀 프리셋은 어떤 조합이 실용적인가?

## claude
# AXIS Kit Agent Teams 설계 의견

## 1) /team 커맨드 자연어 유도 방식

**적절하다, 단 구조화 필요**

```markdown
# .claude/commands/team.md
사용자가 "$ARGUMENTS" 팀 구성을 요청했습니다.

다음 지침으로 TeamCreate를 실행하세요:
- 팀 유형: $ARGUMENTS
- [qa] → 테스트 설계자 + 엣지케이스 탐색자 + 자동화 엔지니어
- [review] → 아키텍트 + 보안 감사자 + 성능 분석가
- [design] → UX 설계자 + API 설계자 + 문서화 전문가
```

**핵심 원칙**: 프롬프트에 역할 조합을 명시적으로 기술할수록 Claude의 TeamCreate 해석 일관성이 높아짐

---

## 2) settings.json 자동 추가 여부

**선택 옵션 권장** — 이유:

```bash
# install.sh 권장 패턴
echo "Agent Teams 활성화? (실험적 기능) [y/N]"
read -r response
if [[ "$response" == "y" ]]; then
    # settings.json에 env 추가
    jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"' \
        settings.json > tmp && mv tmp settings.json
fi
```

- **실험적 기능**은 기본 강제 적용 시 안정성 리스크
- 팀 컨텍스트(개인/팀/CI)마다 필요성 다름
- 단, README에 "설치 후 활성화 방법" 명확히 문서화

---

## 3) 실용적 팀 프리셋 조합

| 프리셋 | 역할 구성 | 트리거 상황 |
|--------|-----------|-------------|
| `qa` | 테스터 + 엣지케이스 + 회귀분석 | PR 전 품질 검증 |
| `review` | 아키텍트 + 보안 + 성능 | 코드 리뷰 |
| `design` | API설계 + UX + 문서화 | 신규 기능 설계 |
| `debug` | 근본원인분석 + 로그분석 + 재현 | 프로덕션 이슈 |
| `refactor` | 클린코드 + 의존성 + 테스트커버리지 | 기술부채 해소 |

**`debug`와 `refactor` 추가를 강력 권장** — 실제 사용 빈도가 qa/review만큼 높음

---

## 종합 판단

> **자연어 유도는 유효하나, 프롬프트 명세가 팀 품질을 결정한다**
> 설정은 opt-in, 프리셋은 5개로 시작해 사용 패턴 기반으로 확장

## gpt
가능합니다. 권장안은 아래와 같습니다.

1) **`/team` 커맨드**
- 적절합니다. `TeamCreate`를 직접 못 부르므로, `/team qa|review|design` → **자연어 프롬프트 템플릿**으로 유도하는 방식이 현실적입니다.
- 단, “보장된 실행”이 아니라 **Claude가 해석하는 유도형**임을 문서에 명시해야 합니다.
- 각 프리셋은 역할, 목표, 산출물 형식을 고정해 일관성을 높이세요.

2) **install.sh 설정 방식**
- **자동 강제 추가보다는 선택 옵션**이 바람직합니다.
- 이유: experimental 플래그는 사용자 정책/보안/버전 호환 이슈가 있을 수 있습니다.
- 권장: 설치 시 “Agent Teams 활성화(y/N)” 프롬프트 제공 + 미선택 시 수동 설정 안내.

3) **실용적 프리셋**
- **qa**: tester + bug reproducer + edge-case reviewer
- **review**: code reviewer + security reviewer + performance reviewer
- **design**: architect + API designer + DX/Docs reviewer
- 추가 추천:
  - **ship**: implementer + reviewer + qa
  - **refactor**: architect + refactoring reviewer + regression tester

즉, **유도형 `/team` + opt-in 설정 + 목적별 3~5개 프리셋**이 가장 실용적입니다.

## gemini
소프트웨어 아키텍처 관점에서 AXIS Kit에 Agent Teams를 통합하기 위한 의견을 제시합니다.

1. **`/team` 커맨드 적절성**: **매우 적절합니다.** 내부 도구(`TeamCreate`)의 직접 호출 제약을 프롬프트 템플릿으로 추상화하는 것은 사용자 경험(DX)을 개선하고, 도구의 복잡성을 은닉하는 훌륭한 아키텍처적 우회 전략입니다.

2. **설정 자동화 여부**: **선택 옵션(Interactive Opt-in)** 방식을 권장합니다. `EXPERIMENTAL` 플래그는 환경에 따라 불안정할 수 있으므로, `install.sh` 실행 중 사용자 동의를 구하거나 별도의 `--enable-teams` 플래그를 통해 `settings.json`에 반영하는 것이 안전합니다.

3. **실용적 팀 프리셋 조합**:
   - **Reviewer**: 보안 취약점, 성능 병목, 코드 컨벤션 정밀 진단.
   - **QA/Tester**: 유닛/통합 테스트 자동 생성 및 경계 조건(Edge case) 검증.
   - **Architect**: 도메인 모델 설계 및 모듈 간 의존성/기술 부채 분석.
   - **Refactor**: 코드 가독성 개선 및 최신 디자인 패턴 적용 제안.


## 합의 분석
- **합의율**: 100%
- **판정**: auto_approve
- **요약**: 모든 모델이 자연어 유도 방식의 커맨드 설계, 선택적 설정 도입, QA/리뷰/리팩토링 중심의 프리셋 구성에 완전히 일치하는 의견을 보임

### 공통점
- /team 커맨드를 통해 자연어 프롬프트로 TeamCreate를 유도하는 방식이 가장 적절한 우회 전략임에 동의
- 실험적 기능(EXPERIMENTAL)이므로 install.sh에서 강제 적용이 아닌 사용자 선택(Opt-in) 방식을 권장
- QA, Review, Design(Architect), Refactor를 핵심적인 실용적 프리셋 조합으로 공통 제안

### 차이점
- 추가 프리셋 제안의 차이 (Claude: debug, GPT: ship, Gemini: Architect 중심)
- Claude는 구체적인 프롬프트 구조와 코드 스니펫을 제공한 반면, 타 모델은 개념적 설계 위주로 답변
