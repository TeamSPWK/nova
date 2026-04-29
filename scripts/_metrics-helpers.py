#!/usr/bin/env python3
"""Nova Metrics Python helpers — stdin JSONL, KPI aggregation.

Usage:
  <jsonl stream> | python3 scripts/_metrics-helpers.py <kpi_name>
    → "<numerator> <denominator>" (text mode for bash format_ratio)
  <jsonl stream> | python3 scripts/_metrics-helpers.py json_all
    → JSON array of 4 KPI objects (Sprint 2, measurement-spec.md §4)

Schema_version 분기:
  events.jsonl v1 (~v5.19.x)와 v2 (v5.20.0+) 모두 받아들인다.
  필드 누락 시 best-effort 0/0 반환 — KPI는 sufficient 판정에서 자동 gray-out.
"""
import json
import sys


# measurement-spec.md §1 — KPI 4종 정의
KPI_DEFINITIONS = [
    ("process_consistency",     "Process Consistency",      10),
    ("gap_detection_rate",      "Gap Detection Rate",       10),
    ("rule_evolution_rate",     "Rule Evolution Rate",      10),
    ("multi_perspective_impact", "Multi-Perspective Impact",  5),
]


def read_events():
    events = []
    for line in sys.stdin:
        try:
            events.append(json.loads(line))
        except Exception:
            continue
    return events


def calc_process_consistency(events):
    plans = {}
    sprints = []
    for e in events:
        extra = e.get("extra", {}) or {}
        oid = extra.get("orchestration_id", "")
        et = e.get("event_type", "")
        ts = e.get("timestamp_epoch", 0)
        if et == "plan_created":
            plans.setdefault(oid, []).append(ts)
        elif et == "sprint_completed" and extra.get("planned_files", 0) >= 3:
            sprints.append((oid, ts))
    num = 0
    for oid, sts in sprints:
        if any(pts < sts for pts in plans.get(oid, [])):
            num += 1
    return num, len(sprints)


def calc_gap_detection_rate(events):
    fails = []
    resolutions = {}
    for e in events:
        extra = e.get("extra", {}) or {}
        oid = extra.get("orchestration_id", "")
        et = e.get("event_type", "")
        ts = e.get("timestamp_epoch", 0)
        if et == "evaluator_verdict" and extra.get("verdict") == "FAIL":
            fails.append((oid, ts))
        elif (et == "sprint_completed" and extra.get("verdict") == "PASS") or \
             (et == "phase_transition" and extra.get("to_status") == "completed"):
            resolutions.setdefault(oid, []).append(ts)
    num = sum(1 for oid, fts in fails if any(rts > fts for rts in resolutions.get(oid, [])))
    return num, len(fails)


def calc_rule_evolution_rate(events):
    """KPI 3 (재정의, measurement-spec.md §6) — evolve_decision 기반.

    분모: event_type == "evolve_decision" 총수
    분자: 분모 중 extra.decision == "accept"
    """
    total = 0
    accepted = 0
    for e in events:
        if e.get("event_type") != "evolve_decision":
            continue
        total += 1
        if (e.get("extra", {}) or {}).get("decision") == "accept":
            accepted += 1
    return accepted, total


def calc_multi_perspective(events):
    total = 0
    changed = 0
    for e in events:
        if e.get("event_type") == "jury_verdict":
            total += 1
            if (e.get("extra", {}) or {}).get("changed_direction") is True:
                changed += 1
    return changed, total


def compute_one(kpi, events):
    if kpi == "process_consistency":
        return calc_process_consistency(events)
    if kpi == "gap_detection_rate":
        return calc_gap_detection_rate(events)
    if kpi == "rule_evolution_rate":
        return calc_rule_evolution_rate(events)
    if kpi == "multi_perspective_impact":
        return calc_multi_perspective(events)
    return 0, 0


def url_encode_minimal(s):
    """shields.io URL — % → %25, 공백 → %20, = → %3D만 처리 (다른 안전 문자는 그대로)."""
    return s.replace("%", "%25").replace(" ", "%20").replace("=", "%3D")


def pick_color(pct):
    if pct >= 80:
        return "green"
    if pct >= 60:
        return "yellow"
    return "red"


def make_kpi_object(kpi, label, threshold, num, den):
    """measurement-spec.md §4 baselines JSON schema 한 KPI 객체."""
    if den < threshold:
        pct = None
        status = "insufficient"
        badge_text = url_encode_minimal(f"n={den} insufficient")
        badge_color = "lightgrey"
    else:
        pct = (num * 100) // den  # 정수 절사 (spec §4)
        status = "sufficient"
        badge_text = url_encode_minimal(f"{pct}%")
        badge_color = pick_color(pct)
    badge_url = f"https://img.shields.io/badge/{kpi}-{badge_text}-{badge_color}"
    return {
        "kpi": kpi,
        "label": label,
        "pct": pct,
        "n": den,
        "n_threshold": threshold,
        "status": status,
        "delta_pct": None,  # publish-metrics.sh가 이전 baselines 비교 시 채움
        "badge_url": badge_url,
    }


def compute_json_all(events):
    out = []
    for kpi, label, threshold in KPI_DEFINITIONS:
        num, den = compute_one(kpi, events)
        out.append(make_kpi_object(kpi, label, threshold, num, den))
    return out


def main():
    if len(sys.argv) < 2:
        print("0 0")
        return 1
    mode = sys.argv[1]
    events = read_events()
    if mode == "json_all":
        print(json.dumps(compute_json_all(events), ensure_ascii=False))
        return 0
    num, den = compute_one(mode, events)
    if num == 0 and den == 0 and mode not in {k for k, _, _ in KPI_DEFINITIONS}:
        print("0 0")
        return 1
    print(f"{num} {den}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
