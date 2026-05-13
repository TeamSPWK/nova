---
roadmap_id: example-project
title: Example Project — 인프라 + 비용 두 축
created: 2026-04-01
current_phase: P13
phases:
  - id: P12
    title: Phase 12 — AXIS Autonomous Ops (v1.0)
    status: done
    summary: AO-1~7 + V4 PASS — Kanban·Nudge·Retro·Meeting·Notion·GitHub·메가존 Recon 완주
  - id: P13
    title: Phase 13 — 인프라 + 비용 두 축
    status: in_progress
    summary: AO-8~13 prod 운영 + AO-12 흡수형 enrichment
    range_months: 3
  - id: P14
    title: Phase 14 — 인프라 + 비용 축 (장기)
    status: pending
    summary: 자율 조치 (제한적, 인프라 축) + 협업 자동화 후순위
    range_months: 6
external_pending:
  - id: EXT-josh-admin
    title: Anthropic Org Admin 권한
    blocker: env 1~2줄 주입만 하면 즉시 활성화
    activation: ANTHROPIC_ADMIN_KEY 환경변수
    phase: P13
  - id: EXT-google-workspace
    title: Google Workspace 도메인 위임
    blocker: IT 관리자 승인 대기
    activation: GOOGLE_WORKSPACE_DELEGATION_KEY 환경변수
    phase: P13
links:
  - {title: GitHub repository, url: https://github.com/example/project}
  - {title: 운영 대시보드, url: https://grafana.example.com/d/ops}
---

# Example Project Roadmap

> ROADMAP frontmatter v1.0 fixture — `/nova:status` Phase 2 회귀 가드용.
> 실 프로젝트에서는 본문에 자세한 Phase 설명·결정 근거·외부 자료 링크 등을 자유롭게 작성.

## 🎯 새 우선순위 (2026-04-01 결정)

**향후 두 축 = 인프라 관리 + 비용 관리.** 협업 자동화는 Phase 14로 후순위.

## 📍 Phase 13 (현재)

진행 중 — AO-8~13 prod 운영, 비용 절감 -$1,149/월 누적.

## 🚀 Phase 14 (장기 3~6개월)

자율 조치 (제한적, 인프라 축) + 협업 자동화 (회의록·회고·세션 공유).
Phase 13 완주 후 재평가.

## 🔓 외부 승인 대기

- Anthropic Org Admin — env 활성화만 남음
- Google Workspace 위임 — IT 관리자 승인 대기

## ✅ 이미 해결된 것 (Phase 12)

- AO-1 Kanban Sync — 2025-Q4
- AO-2 Nudge L1~L3 — 2026-01
- ...

---

> 📊 `/nova:status`로 progress dashboard 보기:
> `./scripts/render-status.sh --plan docs/plans/<active>.md --open`
