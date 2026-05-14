---
goal: "v5.37.0 릴리스 완료 — 다음 AO 선택 대기"
active_ao: null
handoff:
  from: null
  to: null
  outputs: []
  assumptions: []
  next_objective: "다음 AO 선택 (draft 검수 / dogfooding / 정확도 개선 중 택1)"
  blockers: []
schema_version: 2
---

# 🚀 Nova State

## 🎯 Current
**v5.37.0 릴리스 완료 — 다음 AO 선택 대기**

> [!NOTE]
> **다음 세션 진입점** (택1)
> - (a) `swk-gc` / `planreview` drafts 사용자 검수 후 apply 결정
> - (b) `zippit` / `spwk-product` 추가 dogfooding
> - (c) draft 검수 비율 측정 후 정확도 개선

## 🌳 Active Tree

> 진행 중인 AO 없음. 다음 AO 선택 대기.

```
(empty — 새 AO 시작 시 여기에 트리가 그려짐)
```

## 🤝 Handoff

> 활성 핸드오프 없음.

## 📊 Recent Activity

| 시각 | 작업 | 결과 |
|------|------|:----:|
| 05-14 | v5.37.0 셸 단독 auto-fill (heuristic + api dual) | ✅ |
| 05-14 | v5.36.1 R34aj test 부작용 차단 | ✅ |
| 05-14 | v5.36.0 status-dashboard 보안+부채 묶음 | ✅ |
| 05-13 | v5.35.2 PATH 기반 `nova-status` 호출 전환 | ✅ |
| 05-13 | v5.35.1 핫픽스 (`$CLAUDE_PLUGIN_ROOT` 빈문자열) | ✅ |

## ⚠️ Risks & Gaps

| 항목 | 심각도 | 상태 |
|------|:------:|------|
| PreToolUse exit 2가 세션 hooks.json 구조에 의존 | 🟢 Resolved | v5.18.3 100% 작동 |
| `/nova:review` + Evaluator가 release.sh 통합 안 됨 | 🟢 Resolved | v5.22.3 위생 게이트 4종 |
| status-dashboard Agent enrich 정확도 한계 | 🟡 Mitigated | dry-run + low/unsure 명시 + 사용자 검수 |
| MCP 도구 입출력 자동화 테스트 | 🟡 Med | Known Gap |
| status-dashboard swk-gc/planreview draft 실제 apply | 🟡 Med | 사용자 결정 영역 |

<details>
<summary>📦 <b>Archive</b> — 완료된 AO (6개)</summary>

| AO | 결과 | 핵심 산출물 |
|----|:----:|------------|
| status-dashboard **Phase 1** (S1~S4) | ✅ PASS | `scripts/build·render-status` + 템플릿 + R31×17 + 3 프로젝트 dogfooding |
| status-dashboard **Phase 2** (S5~S8) | ✅ PASS | ROADMAP frontmatter v1.0 + 멀티 plan 통합 + stale + init wizard + R32×16 |
| status-dashboard **Phase 3** (S9~S12) | ✅ PASS | enrich-plans 3 모드 + 5중 안전 가드 + Agent subagent 패턴 + R33×14 |
| status-dashboard **Phase 4** (S13~S16) | ✅ PASS | Claude 우회 차단 + `bin/nova-status` + R34×10. 783/783 |
| visual-intent-verify **Sprint A3** | ✅ PASS | session-start 3 모드 동기화 + R36×16 (628/628) |
| Tier 4 — Cross-harness | ⏸️ Deferred | Claude Code 안정화까지 보류 |

</details>

## 🔗 Refs

- **Plan/Design**: [`docs/plans/status-dashboard.md`](../plans/status-dashboard.md) ↔ [`docs/designs/status-dashboard.md`](../designs/status-dashboard.md)
- **Guide**: [`docs/guides/status-dashboard.md`](../guides/status-dashboard.md) (§1~§9)
- **Latest Verification**: [`2026-05-14--NOVA-STATE-md-스키마-재설계-자문`](../verifications/2026-05-14--NOVA-STATE-md-스키마-재설계-자문-Context.md) — 멀티 AI 합의 95%
- **Scripts**: `build-status` / `render-status` / `init-roadmap` / `enrich-plans`
- **Releases**: v5.37.0 (셸 단독 auto-fill) · v5.33.0 (status-dashboard) · v5.32.0 (§16 Self-Enforcement)

---

<sub>📐 schema_version: 2 · 🔧 v1→v2 마이그레이션: `/nova:migrate-state` (예정)</sub>
