#!/usr/bin/env bash
# Nova 메타데이터 생성 스크립트
# 소스 파일에서 커맨드/스킬/에이전트/버전을 추출하여 nova-meta.json 생성
#
# 사용법: bash scripts/generate-meta.sh
# 출력:   docs/nova-meta.json

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/nova-meta.json"

# ── 버전 ──
VERSION=$(tr -d '[:space:]' < "$ROOT/scripts/.nova-version")

# ── frontmatter에서 description 추출 ──
# description: "..." 또는 description: ... (따옴표 유무 모두 지원)
extract_desc() {
  local file="$1"
  sed -n '/^---$/,/^---$/p' "$file" \
    | grep -m1 '^description:' \
    | sed 's/^description: *//; s/^"//; s/"$//'
}

# ── frontmatter에서 name 추출 ──
extract_name() {
  local file="$1"
  sed -n '/^---$/,/^---$/p' "$file" \
    | grep -m1 '^name:' \
    | sed 's/^name: *//; s/^"//; s/"$//'
}

# ── frontmatter에서 tools 추출 ──
extract_tools() {
  local file="$1"
  sed -n '/^---$/,/^---$/p' "$file" \
    | grep -m1 '^tools:' \
    | sed 's/^tools: *//'
}

# ── JSON 문자열 이스케이프 ──
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

# ── 커맨드 수집 ──
COMMANDS_JSON="["
FIRST=true
for f in "$ROOT/.claude/commands/"*.md; do
  [ -f "$f" ] || continue
  CMD_NAME=$(basename "$f" .md)
  CMD_DESC=$(extract_desc "$f")
  CMD_DESC_ESC=$(json_escape "$CMD_DESC")

  if [ "$FIRST" = true ]; then FIRST=false; else COMMANDS_JSON+=","; fi
  COMMANDS_JSON+=$(printf '\n    {"cmd": "/nova:%s", "description": "%s"}' "$CMD_NAME" "$CMD_DESC_ESC")
done
COMMANDS_JSON+=$'\n  ]'

# ── 스킬 수집 ──
SKILLS_JSON="["
FIRST=true
for f in "$ROOT/.claude/skills/"*/SKILL.md; do
  [ -f "$f" ] || continue
  SKILL_NAME=$(extract_name "$f")
  [ -z "$SKILL_NAME" ] && SKILL_NAME=$(basename "$(dirname "$f")")
  SKILL_DESC=$(extract_desc "$f")
  SKILL_DESC_ESC=$(json_escape "$SKILL_DESC")

  if [ "$FIRST" = true ]; then FIRST=false; else SKILLS_JSON+=","; fi
  SKILLS_JSON+=$(printf '\n    {"name": "%s", "description": "%s"}' "$SKILL_NAME" "$SKILL_DESC_ESC")
done
SKILLS_JSON+=$'\n  ]'

# ── 에이전트 수집 ──
AGENTS_JSON="["
FIRST=true
for f in "$ROOT/.claude/agents/"*.md; do
  [ -f "$f" ] || continue
  AGENT_NAME=$(extract_name "$f")
  [ -z "$AGENT_NAME" ] && AGENT_NAME=$(basename "$f" .md)
  AGENT_DESC=$(extract_desc "$f")
  AGENT_DESC_ESC=$(json_escape "$AGENT_DESC")
  AGENT_TOOLS=$(extract_tools "$f")

  if [ "$FIRST" = true ]; then FIRST=false; else AGENTS_JSON+=","; fi
  AGENTS_JSON+=$(printf '\n    {"name": "%s", "description": "%s", "tools": "%s"}' "$AGENT_NAME" "$AGENT_DESC_ESC" "$AGENT_TOOLS")
done
AGENTS_JSON+=$'\n  ]'

# ── 통계 ──
CMD_COUNT=$(ls -1 "$ROOT/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
SKILL_COUNT=$(ls -1d "$ROOT/.claude/skills/"*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
AGENT_COUNT=$(ls -1 "$ROOT/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')

# ── MCP 도구 수집 ──
MCP_TOOLS_COUNT=0
if [ -d "$ROOT/mcp-server/src/tools" ]; then
  MCP_TOOLS_COUNT=$(ls -1 "$ROOT/mcp-server/src/tools/"*.ts 2>/dev/null | grep -v index | wc -l | tr -d ' ')
fi

# ── 생성 일시 ──
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── JSON 출력 ──
cat > "$OUT" << METAEOF
{
  "version": "$VERSION",
  "generatedAt": "$GENERATED_AT",
  "stats": {
    "commands": $CMD_COUNT,
    "skills": $SKILL_COUNT,
    "agents": $AGENT_COUNT,
    "rules": 10,
    "mcpTools": $MCP_TOOLS_COUNT
  },
  "commands": $COMMANDS_JSON,
  "skills": $SKILLS_JSON,
  "agents": $AGENTS_JSON
}
METAEOF

# ── 검증 ──
if ! python3 -m json.tool "$OUT" > /dev/null 2>&1; then
  echo "❌ nova-meta.json JSON 유효성 검증 실패"
  exit 1
fi

# ── README 마커 기반 자동 교체 ──
# <!-- AUTO-GEN:commands --> ~ <!-- /AUTO-GEN:commands --> 사이를 교체

update_readme_section() {
  local readme="$1"
  local marker="$2"
  local content_file="$3"

  [ -f "$readme" ] || return 0

  local start_marker="<!-- AUTO-GEN:${marker} -->"
  local end_marker="<!-- /AUTO-GEN:${marker} -->"

  # 마커가 없으면 스킵
  grep -q "$start_marker" "$readme" || return 0

  # macOS/Linux 호환: content를 임시 파일로 전달
  awk -v start="$start_marker" -v end="$end_marker" -v cf="$content_file" '
    $0 == start { print; while ((getline line < cf) > 0) print line; close(cf); skip=1; next }
    $0 == end   { print; skip=0; next }
    !skip       { print }
  ' "$readme" > "${readme}.tmp" && mv "${readme}.tmp" "$readme"
}

# 커맨드 테이블 생성
CMD_TABLE="| Command | Description |\n|---------|------------|"
for f in "$ROOT/.claude/commands/"*.md; do
  [ -f "$f" ] || continue
  CMD_NAME=$(basename "$f" .md)
  CMD_DESC=$(extract_desc "$f")
  # 테이블용으로 MUST TRIGGER 이후 제거 (간결화)
  CMD_DESC_SHORT=$(echo "$CMD_DESC" | sed 's/ — MUST TRIGGER:.*//')
  CMD_TABLE+="\n| \`/nova:${CMD_NAME}\` | ${CMD_DESC_SHORT} |"
done

# 스킬 테이블 생성
SKILL_TABLE="| Skill | Description |\n|-------|------------|"
for f in "$ROOT/.claude/skills/"*/SKILL.md; do
  [ -f "$f" ] || continue
  SKILL_NAME=$(extract_name "$f")
  [ -z "$SKILL_NAME" ] && SKILL_NAME=$(basename "$(dirname "$f")")
  SKILL_DESC=$(extract_desc "$f")
  SKILL_DESC_SHORT=$(echo "$SKILL_DESC" | sed 's/ — MUST TRIGGER:.*//')
  SKILL_TABLE+="\n| **${SKILL_NAME}** | ${SKILL_DESC_SHORT} |"
done

# 에이전트 테이블 생성
AGENT_TABLE="| Agent | Description |\n|-------|------------|"
for f in "$ROOT/.claude/agents/"*.md; do
  [ -f "$f" ] || continue
  AGENT_NAME=$(extract_name "$f")
  [ -z "$AGENT_NAME" ] && AGENT_NAME=$(basename "$f" .md)
  AGENT_DESC=$(extract_desc "$f")
  # 간결화: 첫 문장만
  AGENT_DESC_SHORT=$(echo "$AGENT_DESC" | sed 's/\. .*//' | sed 's/에 적합$//')
  AGENT_TABLE+="\n| \`${AGENT_NAME}\` | ${AGENT_DESC_SHORT} |"
done

# 임시 파일로 테이블 저장
TMPDIR_META=$(mktemp -d)
echo -e "$CMD_TABLE" > "$TMPDIR_META/commands.md"
echo -e "$SKILL_TABLE" > "$TMPDIR_META/skills.md"
echo -e "$AGENT_TABLE" > "$TMPDIR_META/agents.md"

# README.md, README.ko.md 모두 교체
for readme in "$ROOT/README.md" "$ROOT/README.ko.md"; do
  update_readme_section "$readme" "commands" "$TMPDIR_META/commands.md"
  update_readme_section "$readme" "skills" "$TMPDIR_META/skills.md"
  update_readme_section "$readme" "agents" "$TMPDIR_META/agents.md"
done

rm -rf "$TMPDIR_META"

echo "✅ nova-meta.json 생성 + README 동기화 완료: $VERSION (commands:$CMD_COUNT skills:$SKILL_COUNT agents:$AGENT_COUNT)"
