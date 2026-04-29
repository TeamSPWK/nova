# Context Rot Diagnosis (컨텍스트 로스트 진단)

> Nova v5.20.1+ — ECC P0-1 흡수
> 출처: [Adversarial Gap Analysis (2026-04-29)](proposals/2026-04-29-ecc-adversarial-gap.md) + ECC `affaan-m/everything-claude-code` Strategic Compact 패턴
> 목적: Claude가 점진적으로 "멍청해지는" 현상을 진단/분류/대응. v5.20.0 측정 인프라 위에서 후험적 효과 검증.

---

## 컨텍스트 로스트란?

**Claude가 시간이 지남에 따라 출력 품질이 점진적으로 저하되는 현상**. 크래시·에러 없이 단순히 *멍청해지므로* 사용자가 즉시 인지하기 어렵다. ECC 측정 기준 단일 파일 2K~3K 토큰(한글 100단어 분량) 초과 시 점검 신호로 본다.

비유: 200K 토큰 연료 탱크에 출발 시점부터 짐을 가득 싣고 시작하는 자동차. 연비 저하 + 핸들 무거움.

---

## 4 원인 분류 + Nova 1차 대응

| 원인 | 진단 신호 | Nova 1차 대응 | 메모리/스킬 참조 |
|------|----------|----------------|------------------|
| **어텐션 희석 (Attention Dilution)** | 같은 지시 반복, 최근 변경 무시, 대화 초반 정보 인용 정확도 저하 | `/clear` (무관 작업 사이) → NOVA-STATE 자동 재주입 → 작업 재시작 | session-start.sh + context-chain 스킬 |
| **명령 충돌 (Instruction Conflict)** | CLAUDE.md vs session-start vs 사용자 지시 모순. AI가 어느 룰을 따를지 흔들림 | `/nova:check` 정합성 검증 → 충돌 룰 식별 → CLAUDE.md / session-start.sh 동기화 (필수 메모리: feedback_session_start_sync) | check 커맨드 + nova-rules.md |
| **토큰 예산 압박 (Token Budget Pressure)** | 응답 갑자기 짧아짐, 계획 단계 생략, 도구 호출 회피 | session-start lean 프로파일 (≤1200자) + MCP 비활성화 (P1-2 룰 ≤10/80) + 무관 파일 unload | session-start lean / standard / strict 모드 |
| **관련성 미스매치 (Relevance Mismatch)** | 부적절한 파일 인용, 잘못된 경로, 컨텍스트와 무관한 패턴 적용 | `Explore` 서브에이전트 분리 (read-only 폭 분리) + Plan에 정확한 reference 명시 | Explore agent + /nova:plan |

---

## 진단 절차

사용자가 "Claude가 멍청해진 것 같다"고 보고하거나 자가 점검 시:

1. **증상 분류** — 위 4 원인 표에서 일치하는 진단 신호 식별
2. **NOVA-STATE 검사** — `wc -l NOVA-STATE.md` 50줄 초과 시 자가 트림 작동 확인 (v5.19.6 9 진입점 동기화)
3. **events.jsonl 통계 확인**:
   ```bash
   bash scripts/analyze-observations.sh --pattern failures
   bash scripts/analyze-observations.sh --pattern confidence --threshold 0.7
   ```
4. **1차 대응 적용** — 위 표의 "Nova 1차 대응" 컬럼
5. **회복 안 되면 `/clear` 또는 새 세션** — context-chain SKILL이 NOVA-STATE 자동 복원

---

## ECC vs Nova 차이 (정체성 보존)

ECC는 컨텍스트 로스트를 "Strategic Compact 스킬"로 *예방* 중심으로 다룬다. Nova는:

- **예방**: NOVA-STATE 50줄 자가 트림 + session-start lean/standard/strict 프로파일 (메모리 `feedback_session_start_lightweight`)
- **진단**: 본 문서 (4원인 카탈로그)
- **대응**: 위 표 + 측정 인프라 (v5.20.0)로 후험 검증

본 카탈로그가 다음 릴리스(P0-3 Strategic Compact 스킬, v5.21.0)에서 *적용 시점 결정* 의 근거로 활용된다.

---

## 측정 (v5.20.0 인프라 활용)

`docs/baselines/v5.20.0-baseline.md` 기준선 + 본 카탈로그 도입(v5.20.1) 이후의 events.jsonl 변화를 다음 비교:

- **failures 패턴 빈도** — evaluator FAIL/CONDITIONAL 비율 변화
- **session 평균 도구 호출 수** — 토큰 압박 지표
- **CONDITIONAL → PASS 회복률** — 명령 충돌 자가 회복 능력

후험 비교는 v5.22.0+ (P0-2 비용 가이드 + P0-3 Strategic Compact 흡수 후) 시점에 가능.

---

## 다음 단계

- v5.21.0 minor: P0-3 Strategic Compact 스킬 — 본 카탈로그의 "Nova 1차 대응"을 자동 트리거하는 스킬
- v5.22.0+ minor: P1-1 `/nova:audit-self` — Nova 자체 보안 + 컨텍스트 로스트 자가 진단 통합

## Refs

- [ECC Adversarial Gap Analysis](proposals/2026-04-29-ecc-adversarial-gap.md) — P0-1 항목 (이 문서 출처)
- [Measurement Infrastructure Plan](plans/measurement-infrastructure.md) — v5.20.0 측정 인프라
- [v5.20.0 Baseline Snapshot](baselines/v5.20.0-baseline.md) — 본 카탈로그 도입 이전 기준선
