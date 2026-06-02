#!/usr/bin/env bash
# Nova coexist 토글 — NOVA_COEXIST를 Claude Code settings.json env에 켜고/끈다 (v5.53.0+)
#
# OMC 등 다른 "세션 소유형" 오케스트레이션 플러그인과 공존: Nova의 고유 가치(커밋 게이트)만
# 유지하고 session-start 규칙 주입·per-tool 관찰성·stop·pre-compact·pre-edit 훅을 no-op한다.
#
# 사용법:
#   bash scripts/nova-coexist.sh status            # 현재 상태
#   bash scripts/nova-coexist.sh on                # 켜기 (global ~/.claude/settings.json)
#   bash scripts/nova-coexist.sh off               # 끄기
#   bash scripts/nova-coexist.sh on --project      # 현재 프로젝트 .claude/settings.json에만
#   bash scripts/nova-coexist.sh -h                # 도움말
#
# 적용 시점: 새 Claude Code 세션부터 (env는 세션 시작 시 로드 → 현재 세션은 재시작 필요).
# 가이드: docs/guides/coexist.md
set -u

ACTION="${1:-status}"
SCOPE="global"
[ "${2:-}" = "--project" ] && SCOPE="project"

case "$ACTION" in
  -h|--help|help) sed -n '2,17p' "$0"; exit 0 ;;
  on|off|status) ;;
  *) echo "사용법: bash scripts/nova-coexist.sh on|off|status [--project]  (-h 도움말)" >&2; exit 1 ;;
esac

if [ "$SCOPE" = "project" ]; then
  SETTINGS=".claude/settings.json"
else
  SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
fi

command -v python3 >/dev/null 2>&1 || { echo "python3 필요" >&2; exit 1; }

python3 - "$SETTINGS" "$ACTION" "$SCOPE" <<'PY'
import json, os, sys
path, action, scope = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except Exception as e:
    print(f"settings.json 파싱 실패 ({path}): {e}", file=sys.stderr)
    sys.exit(1)
if not isinstance(data, dict):
    print(f"settings.json 형식 오류(객체 아님): {path}", file=sys.stderr)
    sys.exit(1)

env = data.get("env", {})
if not isinstance(env, dict):
    print("settings.json env 형식 오류(객체 아님)", file=sys.stderr)
    sys.exit(1)
cur = env.get("NOVA_COEXIST")

if action == "status":
    state = "켜짐 (게이트만 — OMC 공존)" if cur == "1" else "꺼짐 (full Nova)"
    print(f"NOVA_COEXIST = {cur!r}  [{scope}: {path}]  → {state}")
    sys.exit(0)

if action == "on":
    env["NOVA_COEXIST"] = "1"
else:  # off
    env.pop("NOVA_COEXIST", None)
data["env"] = env

os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(tmp, path)
print(f"NOVA_COEXIST {'켜짐 (게이트만)' if action == 'on' else '꺼짐 (full Nova)'} → {path}")
print("⚠️  새 Claude Code 세션부터 적용됩니다 (현재 세션은 재시작 필요).")
PY
