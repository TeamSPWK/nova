#!/usr/bin/env python3
"""
enrich-plans.py — docs/plans/*.md frontmatter v1.1 auto-enrich

Spec: docs/designs/status-dashboard.md §17~§19

Stages:
  1. collect — ROADMAP frontmatter + docs/plans/* 스캔 → .nova/enrich-batches/batch-N.json
              (skip already-frontmatter plans)
  2. (메인 Claude가 Agent subagent에게 batch별 위임 → .nova/enrich-batches/output-N.json)
  3. dry-run | patch | apply — output을 읽고 plans에 적용

Safety (§17.3):
  - 본문 0 byte 변경 (정규식 prepend만)
  - 기존 frontmatter 있는 plan은 skip
  - --apply 시 .bak 자동 백업
  - batch 단위 (default 10)
  - 자동 git commit 0건
"""
import argparse
import datetime as dt
import glob as glob_mod
import json
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("PyYAML required. Install: pip3 install PyYAML", file=sys.stderr)
    sys.exit(3)

ROADMAP_CANDIDATES = ["ROADMAP.md", "docs/ROADMAP.md", "docs/roadmap.md"]
BATCHES_DIR = ".nova/enrich-batches"

# ---------------------------------------------------------------- args
def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", required=True, choices=["collect", "dry-run", "patch", "apply"])
    p.add_argument("--roadmap", help="외부 ROADMAP.md 경로")
    p.add_argument("--batch-size", type=int, default=10)
    p.add_argument("--force", action="store_true")
    return p.parse_args()

# ---------------------------------------------------------------- helpers
def repo_root():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return os.getcwd()

def find_roadmap(root, override=None):
    if override:
        return override if os.path.exists(override) else None
    for cand in ROADMAP_CANDIDATES:
        p = os.path.join(root, cand)
        if os.path.exists(p):
            return p
    return None

def parse_roadmap_phases(roadmap_path):
    text = Path(roadmap_path).read_text(encoding="utf-8")
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.S)
    if not m:
        return None
    try:
        fm = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        return None
    if not fm.get("roadmap_id"):
        return None
    phases = []
    for p in (fm.get("phases") or []):
        if isinstance(p, dict) and p.get("id"):
            phases.append({
                "id": p["id"],
                "title": p.get("title", p["id"]),
                "status": p.get("status", "pending"),
            })
    return phases

def has_frontmatter(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            first = f.readline().strip()
        return first == "---"
    except Exception:
        return False

def extract_title_line(text):
    for line in text.splitlines()[:30]:
        if line.startswith("# "):
            return line[2:].strip()
    return ""

# ---------------------------------------------------------------- Stage 1: collect
def collect(root, batch_size, roadmap_override=None):
    roadmap_path = find_roadmap(root, override=roadmap_override)
    if not roadmap_path:
        print("[enrich-plans] ROADMAP.md 없음. 먼저 ./scripts/init-roadmap.sh 실행.", file=sys.stderr)
        sys.exit(5)

    phases = parse_roadmap_phases(roadmap_path)
    if not phases:
        print(f"[enrich-plans] {roadmap_path}에 유효한 ROADMAP frontmatter 없음.", file=sys.stderr)
        print("  먼저 ./scripts/init-roadmap.sh --scan 또는 --llm으로 frontmatter 추가.", file=sys.stderr)
        sys.exit(5)

    plan_paths = sorted(glob_mod.glob(os.path.join(root, "docs/plans/*.md")))
    if not plan_paths:
        print("[enrich-plans] docs/plans/*.md 0건. 작업 없음.", file=sys.stderr)
        sys.exit(0)

    skipped, targets = [], []
    for path in plan_paths:
        if has_frontmatter(path):
            skipped.append(path)
            continue
        try:
            text = Path(path).read_text(encoding="utf-8")
        except Exception:
            continue
        targets.append({
            "path": os.path.relpath(path, root),
            "filename": os.path.basename(path),
            "title_line": extract_title_line(text),
            "body_head_200": "\n".join(text.splitlines()[:200]),
        })

    batches_dir = os.path.join(root, BATCHES_DIR)
    Path(batches_dir).mkdir(parents=True, exist_ok=True)
    for old in glob_mod.glob(os.path.join(batches_dir, "batch-*.json")):
        os.remove(old)
    for old in glob_mod.glob(os.path.join(batches_dir, "output-*.json")):
        os.remove(old)

    batch_count = (len(targets) + batch_size - 1) // batch_size
    for i in range(batch_count):
        batch = {
            "$schema": "https://nova/enrich-plans-input/v1.0",
            "version": "1.0",
            "roadmap_phases": phases,
            "batch_index": i,
            "batch_size": batch_size,
            "total_plans": len(targets),
            "plans": targets[i * batch_size:(i + 1) * batch_size],
        }
        out = os.path.join(batches_dir, f"batch-{i:03d}.json")
        Path(out).write_text(json.dumps(batch, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\n✓ collect 완료")
    print(f"  ROADMAP phases:    {len(phases)} (현재 진실원)")
    print(f"  총 plan:           {len(plan_paths)}")
    print(f"  skip (frontmatter 있음): {len(skipped)}")
    print(f"  enrich 대상:       {len(targets)}")
    print(f"  batch 분할:        {batch_count}개 ({batch_size}/batch)")
    print(f"  batch 경로:        {BATCHES_DIR}/batch-*.json")
    print(f"\n다음 단계 — Claude(메인)이 Agent subagent에 위임:")
    print(f"  각 batch-N.json → Agent prompt → output-N.json")
    print(f"  Agent prompt 스키마: docs/designs/status-dashboard.md §18")
    print(f"\n  Agent 출력이 끝나면:")
    print(f"    ./scripts/enrich-plans.sh --dry-run")
    print(f"    ./scripts/enrich-plans.sh --patch")
    print(f"    ./scripts/enrich-plans.sh --apply --force")

# ---------------------------------------------------------------- Stage 3: apply
def read_outputs(root):
    batches_dir = os.path.join(root, BATCHES_DIR)
    if not os.path.isdir(batches_dir):
        print(f"[enrich-plans] {BATCHES_DIR} 없음. 먼저 --collect 실행.", file=sys.stderr)
        sys.exit(7)
    out_files = sorted(glob_mod.glob(os.path.join(batches_dir, "output-*.json")))
    if not out_files:
        print(f"[enrich-plans] output-*.json 없음. Agent가 아직 작성 안 함.", file=sys.stderr)
        sys.exit(8)
    results = []
    for of in out_files:
        try:
            data = json.loads(Path(of).read_text(encoding="utf-8"))
        except Exception as e:
            print(f"[enrich-plans] {of} 파싱 실패: {e}", file=sys.stderr)
            continue
        for r in (data.get("results") or []):
            results.append(r)
    return results

def render_frontmatter_block(fm_dict, comment_header=None):
    yaml_str = yaml.safe_dump(fm_dict, sort_keys=False, allow_unicode=True,
                              default_flow_style=False)
    lines = ["---", yaml_str.rstrip(), "---", ""]
    if comment_header:
        lines = comment_header.splitlines() + [""] + lines
    return "\n".join(lines) + "\n"

def safe_join(root, rel_path):
    """root 외부로 traversal 시도하는 plan_path 차단 (v5.36.0).

    외부 Agent가 작성한 output-*.json의 plan_path 값을 신뢰하지 않는다.
    Returns (full_path, error). error가 truthy면 호출 측이 skip해야 한다.
    """
    if rel_path is None or not isinstance(rel_path, str) or not rel_path.strip():
        return None, "plan_path 비어있음/타입 불일치"
    if os.path.isabs(rel_path):
        return None, f"plan_path 절대경로 거부: {rel_path}"
    candidate = os.path.join(root, rel_path)
    real_root = os.path.realpath(root)
    real_cand = os.path.realpath(candidate)
    if real_cand != real_root and not real_cand.startswith(real_root + os.sep):
        return None, f"plan_path 외부 경로 거부 (traversal): {rel_path} → {real_cand}"
    return candidate, None

def apply_dry_run(root, results):
    counts = {"created": 0, "skipped": 0, "low_conf": 0}
    low_conf_files = []
    for r in results:
        path, err = safe_join(root, r.get("plan_path"))
        if err:
            print(f"WARN: {err}", file=sys.stderr)
            counts["skipped"] += 1
            continue
        if r.get("skip_reason"):
            counts["skipped"] += 1
            continue
        fm = r.get("proposed_frontmatter")
        if not fm:
            counts["skipped"] += 1
            continue
        confidence = r.get("confidence", "unknown")
        unsure = r.get("unsure_fields") or []
        header = f"# Generated by enrich-plans (dry-run mode)\n# Confidence: {confidence}\n# Apply: cat <this file> <original> > /tmp/new && mv /tmp/new {r['plan_path']}"
        if unsure:
            header += f"\n# ⚠️ unsure fields: {', '.join(unsure)}"
        draft_path = path + ".frontmatter.draft"
        Path(draft_path).write_text(
            render_frontmatter_block(fm, comment_header=header), encoding="utf-8")
        counts["created"] += 1
        if confidence == "low":
            counts["low_conf"] += 1
            low_conf_files.append(r["plan_path"])
    return counts, low_conf_files

def apply_patch(root, results):
    import difflib
    counts = {"hunks": 0, "skipped": 0}
    diff_lines = []
    for r in results:
        full, err = safe_join(root, r.get("plan_path"))
        if err:
            print(f"WARN: {err}", file=sys.stderr)
            counts["skipped"] += 1
            continue
        path = r["plan_path"]
        if r.get("skip_reason") or not r.get("proposed_frontmatter"):
            counts["skipped"] += 1
            continue
        fm_block = render_frontmatter_block(r["proposed_frontmatter"]).rstrip("\n") + "\n"
        try:
            original = Path(full).read_text(encoding="utf-8")
        except Exception:
            counts["skipped"] += 1
            continue
        new_content = fm_block + original
        diff = difflib.unified_diff(
            original.splitlines(keepends=True),
            new_content.splitlines(keepends=True),
            fromfile=f"a/{path}", tofile=f"b/{path}", n=3)
        diff_text = "".join(diff)
        if diff_text:
            diff_lines.append(diff_text)
            counts["hunks"] += 1
    patch_path = os.path.join(root, ".nova/enrich-plans.patch")
    Path(patch_path).write_text("".join(diff_lines), encoding="utf-8")
    return counts, patch_path

def apply_inplace(root, results):
    counts = {"applied": 0, "skipped": 0, "errors": 0}
    for r in results:
        path, err = safe_join(root, r.get("plan_path"))
        if err:
            print(f"WARN: {err}", file=sys.stderr)
            counts["skipped"] += 1
            continue
        if r.get("skip_reason") or not r.get("proposed_frontmatter"):
            counts["skipped"] += 1
            continue
        try:
            original = Path(path).read_text(encoding="utf-8")
        except Exception:
            counts["errors"] += 1
            continue
        # safety #2 일관성: collect의 has_frontmatter()와 동일 기준
        # (외부 Agent가 output.json 수동 작성 시 중복 frontmatter 삽입 방지)
        if has_frontmatter(path):
            counts["skipped"] += 1
            continue
        Path(path + ".bak").write_text(original, encoding="utf-8")
        fm_block = render_frontmatter_block(r["proposed_frontmatter"])
        Path(path).write_text(fm_block + original, encoding="utf-8")
        counts["applied"] += 1
    return counts

def print_summary(mode, results, counts, low_conf=None, patch_path=None):
    total = len(results)
    high = sum(1 for r in results if r.get("confidence") == "high")
    medium = sum(1 for r in results if r.get("confidence") == "medium")
    low = sum(1 for r in results if r.get("confidence") == "low")
    print(f"\n=== enrich-plans ({mode}) 완료 ===")
    print(f"  총 결과:          {total}")
    print(f"  high confidence:  {high} ({high * 100 // max(total, 1)}%)")
    print(f"  medium:           {medium}")
    print(f"  low (검수 필수):  {low}")
    if mode == "dry-run":
        print(f"  draft 생성:       {counts['created']}")
        print(f"  skip:             {counts['skipped']}")
        if low_conf:
            print(f"\n  ⚠️ low confidence ({len(low_conf)}건) 우선 검수:")
            for f in low_conf[:5]:
                print(f"    - {f}.frontmatter.draft")
            if len(low_conf) > 5:
                print(f"    ... 외 {len(low_conf) - 5}건")
        print(f"\n  다음 단계:")
        print(f"    1. drafts 검수 (low 우선)")
        print(f"    2. ./scripts/enrich-plans.sh --apply --force")
        print(f"    3. git diff docs/plans/ → review → commit")
    elif mode == "patch":
        print(f"  patch hunks:      {counts['hunks']}")
        print(f"  경로:             {patch_path}")
        print(f"\n  다음 단계:")
        print(f"    git apply --check {patch_path}")
        print(f"    git apply {patch_path}")
        print(f"    git diff docs/plans/ → review → commit")
    elif mode == "apply":
        print(f"  applied:          {counts['applied']}")
        print(f"  skipped:          {counts['skipped']}")
        print(f"  errors:           {counts['errors']}")
        print(f"\n  백업: 각 plan 옆에 <plan>.md.bak 자동 생성")
        print(f"  복구: mv <plan>.md.bak <plan>.md")
        print(f"\n  다음 단계:")
        print(f"    git diff docs/plans/ → review → commit")

# ---------------------------------------------------------------- main
def main():
    args = parse_args()
    root = repo_root()

    if args.mode == "collect":
        collect(root, args.batch_size, roadmap_override=args.roadmap)
        return

    results = read_outputs(root)
    if not results:
        print("[enrich-plans] output 결과 0건.", file=sys.stderr)
        sys.exit(8)

    if args.mode == "dry-run":
        counts, low_conf = apply_dry_run(root, results)
        print_summary("dry-run", results, counts, low_conf=low_conf)
    elif args.mode == "patch":
        counts, patch_path = apply_patch(root, results)
        print_summary("patch", results, counts, patch_path=patch_path)
    elif args.mode == "apply":
        counts = apply_inplace(root, results)
        print_summary("apply", results, counts)


if __name__ == "__main__":
    main()
