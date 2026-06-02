#!/usr/bin/env bash

# Nova Engineering — PreCompact Hook
# 컴팩션 직전에 NOVA-STATE.md를 보호한다.
# v2 (schema_version: 2): ## 📊 Recent Activity 표에 row 삽입
# v1 legacy:              ## Last Activity 라인 추가 (deprecated, session-start가 자동 마이그레이션)
# Spec: docs/specs/nova-state-schema-v2.md §4 (본문 섹션)

# NOVA_COEXIST=1 — OMC 등 다른 오케스트레이션 플러그인과 공존 시 생략 (게이트만 유지).
[ "${NOVA_COEXIST:-0}" = "1" ] && exit 0

# -t 1: inherited 빈 stdin(EOF 미도달) 시 read가 블로킹되는 것을 방지 (PAYLOAD 미사용, 타임아웃 fallback)
read -r -t 1 PAYLOAD 2>/dev/null || PAYLOAD="{}"

STATE_FILE="NOVA-STATE.md"

if [ -f "$STATE_FILE" ]; then
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  DATE_SHORT=$(date -u +"%Y-%m-%d")

  # v2 감지: schema_version: 2 (frontmatter 첫 10줄 내)
  if head -10 "$STATE_FILE" | grep -q "^schema_version: *2"; then
    # v2: ## 📊 Recent Activity 표 헤더 다음에 row 삽입, 기존 context compacted row는 제거
    if grep -q "^## 📊 Recent Activity" "$STATE_FILE"; then
      TMP=$(mktemp)
      awk -v date="$DATE_SHORT" '
        /^## 📊 Recent Activity/ { print; in_section=1; next }
        in_section && /^\|[ \-:]+\|[ \-:]+\|[ \-:]+\|/ {
          print
          print "| " date " | context compacted | ✅ |"
          inserted=1
          in_section=0
          next
        }
        # 기존 context compacted row 1건 제거 (중복 방지)
        inserted && /^\| *[0-9\-]+ *\| *context compacted/ { inserted=0; next }
        { print }
      ' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
    fi
  else
    # v1 legacy fallback (deprecated — session-start가 다음 세션에 자동 마이그레이션)
    MARKER="- context compacted | $TIMESTAMP"
    if grep -q "^## Last Activity" "$STATE_FILE"; then
      TMP=$(mktemp)
      awk -v marker="$MARKER" '
        /^## Last Activity/ { print; print marker; skip=1; next }
        skip && /^- context compacted/ { next }
        { skip=0; print }
      ' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
    fi
  fi
fi

# 컴팩션 허용 (exit 0). 차단하려면 exit 2.
exit 0
