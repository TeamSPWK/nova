#!/usr/bin/env bash
# dev/install.sh — Nova 개발자 전용 커맨드/스킬을 사용자 글로벌(~/.claude)에 심볼릭 링크
#
# Nova 자체를 개발할 때만 의미 있는 커맨드/스킬을 사용자 글로벌 영역에 노출시킨다.
# 플러그인 배포 패키지(.claude/)에는 포함되지 않으므로 일반 Nova 사용자에게는 영향 없음.
#
# 설치 대상:
#   ~/.claude/commands/nova-dev/evolve.md        → dev/commands/evolve.md
#   ~/.claude/commands/nova-dev/audit-self.md    → dev/commands/audit-self.md
#   ~/.claude/skills/nova-dev-evolution/         → dev/skills/evolution/
#   ~/.claude/skills/nova-dev-field-test/        → dev/skills/field-test/
#
# 호출: bash dev/install.sh
#       bash dev/install.sh --uninstall   # 링크 제거

set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEV_DIR="$ROOT_DIR/dev"
USER_CMD_DIR="$HOME/.claude/commands/nova-dev"
USER_SKILL_PREFIX="$HOME/.claude/skills/nova-dev-"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

if [[ "${1:-}" == "--uninstall" ]]; then
  echo "[uninstall] nova-dev 링크 제거"
  rm -rf "$USER_CMD_DIR"
  for skill in evolution field-test; do
    target="${USER_SKILL_PREFIX}${skill}"
    if [[ -L "$target" ]]; then
      rm -f "$target" && echo "  removed: $target"
    elif [[ -e "$target" ]]; then
      echo "  ⚠️  skip: $target — 실제 디렉토리 존재 (수동 정리 필요)"
    fi
  done
  echo "✅ uninstall 완료"
  exit 0
fi

mkdir -p "$USER_CMD_DIR"
mkdir -p "$HOME/.claude/skills"

echo "[install] Nova 개발자 도구 → $HOME/.claude/"
echo "  source: $DEV_DIR"
echo ""

# 커맨드 링크
for cmd_file in "$DEV_DIR/commands/"*.md; do
  cmd_name=$(basename "$cmd_file")
  target="$USER_CMD_DIR/$cmd_name"
  ln -sf "$cmd_file" "$target"
  echo "  command: /nova-dev:${cmd_name%.md} → $cmd_file"
done

# 스킬 링크 (디렉토리 단위, 충돌 회피용 prefix)
for skill_dir in "$DEV_DIR/skills/"*/; do
  skill_name=$(basename "$skill_dir")
  target="${USER_SKILL_PREFIX}${skill_name}"
  if [[ -e "$target" && ! -L "$target" ]]; then
    echo "  ⚠️  skip: $target — 실제 디렉토리 존재 (수동 정리 필요)"
    continue
  fi
  ln -sfn "$skill_dir" "$target"
  echo "  skill:   nova-dev-${skill_name} → $skill_dir"
done

echo ""
echo "✅ install 완료. Claude Code 재시작 후 다음 사용 가능:"
echo "    /nova-dev:evolve"
echo "    /nova-dev:audit-self"
echo "    (스킬은 SKILL.md description 트리거로 자동 활성화)"
echo ""
echo "제거: bash dev/install.sh --uninstall"
