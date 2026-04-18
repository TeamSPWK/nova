#!/usr/bin/env bash
# Nova Sprint B — 캐시 hit 검증
# 동일 변경 재호출 시 cache_hit=true, 다른 변경 시 cache_hit=false

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DETECT_SCRIPT="$ROOT_DIR/scripts/detect-ui-change.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

assert() {
  local desc="$1"
  local cond="$2"
  if eval "$cond" > /dev/null 2>&1; then
    echo -e "  ${GREEN}OK${NC}  $desc"
    ((PASS++)) || true
  else
    echo -e "  ${RED}FAIL${NC} $desc"
    ((FAIL++)) || true
  fi
}

echo "━━━ test-cache-hit.sh ━━━━━━━━━━━━━━━━━━━━━━━━━"

# 임시 git 저장소 생성
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init -q
git config user.email "test@nova"
git config user.name "Nova Test"

# 초기 커밋
mkdir -p src
cat > src/Button.tsx << 'EOFILE'
import React from 'react';
const Button = () => <button className="btn" style={{color:'#fff',background:'#007'}}>Click</button>;
export default Button;
EOFILE
git add -A
git commit -q -m "initial"

# 변경 커밋 (UI 변경: className, style, color 포함 — 20줄 이상 diff 확보)
cat > src/Button.tsx << 'EOFILE'
import React from 'react';

interface ButtonProps {
  label?: string;
  variant?: 'primary' | 'secondary';
}

const Button: React.FC<ButtonProps> = ({ label = 'Click', variant = 'primary' }) => (
  <button
    className={`btn btn--${variant}`}
    style={{
      color: '#ffffff',
      background: variant === 'primary' ? '#0070f3' : '#6c757d',
      padding: '8px 16px',
      borderRadius: '4px',
      fontWeight: 600,
      fontSize: '14px',
      border: 'none',
      cursor: 'pointer',
      display: 'inline-flex',
      gap: '4px',
    }}
  >
    {label}
  </button>
);

export default Button;
EOFILE
git add -A
git commit -q -m "update button style"

# 1차 호출: cache_hit=false 기대
RESULT1=$(bash "$DETECT_SCRIPT" --post-impl 2>/dev/null || echo '{"error":"script failed","is_ui":false}')
assert "1차 호출: valid JSON" "echo '$RESULT1' | jq -e . > /dev/null 2>&1"
IS_UI=$(echo "$RESULT1" | jq -r '.is_ui' 2>/dev/null || echo "false")
CACHE1=$(echo "$RESULT1" | jq -r '.cache_hit' 2>/dev/null || echo "true")
HASH1=$(echo "$RESULT1" | jq -r '.hash' 2>/dev/null || echo "")
assert "1차 호출: is_ui=true" "[ '$IS_UI' = 'true' ]"
assert "1차 호출: cache_hit=false" "[ '$CACHE1' = 'false' ]"

# last-audit.json에 hash 기록 (PASS 결과로)
mkdir -p .nova
TS=$(date '+%Y-%m-%dT%H:%M:%S+09:00' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "{\"hash\":\"$HASH1\",\"ts\":\"$TS\",\"result\":\"PASS\",\"files\":[],\"stats\":{\"critical\":0,\"high\":0,\"medium\":0,\"low\":0}}" > .nova/last-audit.json

# 2차 호출 (동일 변경): cache_hit=true 기대
RESULT2=$(bash "$DETECT_SCRIPT" --post-impl 2>/dev/null || echo '{"error":"script failed","is_ui":false}')
CACHE2=$(echo "$RESULT2" | jq -r '.cache_hit' 2>/dev/null || echo "false")
assert "2차 호출(동일 변경): cache_hit=true" "[ '$CACHE2' = 'true' ]"

# 3차 호출: 다른 내용으로 변경 → cache_hit=false
cat > src/Button.tsx << 'EOFILE'
import React from 'react';

interface ButtonProps {
  label?: string;
  size?: 'sm' | 'md' | 'lg';
}

const Button: React.FC<ButtonProps> = ({ label = 'Submit', size = 'md' }) => {
  const sizes = { sm: '6px 12px', md: '8px 16px', lg: '12px 24px' };
  return (
    <button
      className={`btn btn--size-${size}`}
      style={{
        color: '#0070f3',
        background: '#ffffff',
        border: '1px solid #0070f3',
        padding: sizes[size],
        borderRadius: '4px',
        fontWeight: 500,
        fontSize: size === 'lg' ? '16px' : '14px',
        cursor: 'pointer',
        display: 'inline-flex',
        gap: '8px',
      }}
    >
      {label}
    </button>
  );
};

export default Button;
EOFILE
git add -A
git commit -q -m "change button style again"

RESULT3=$(bash "$DETECT_SCRIPT" --post-impl 2>/dev/null || echo '{"error":"script failed","is_ui":false}')
CACHE3=$(echo "$RESULT3" | jq -r '.cache_hit' 2>/dev/null || echo "true")
HASH3=$(echo "$RESULT3" | jq -r '.hash' 2>/dev/null || echo "")
assert "3차 호출(다른 변경): cache_hit=false" "[ '$CACHE3' = 'false' ]"
assert "3차 호출: 새 hash != 이전 hash" "[ '$HASH3' != '$HASH1' ] || [ -z '$HASH1' ]"

# 정리
cd /tmp
rm -rf "$TMPDIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}ALL PASS${NC}: ${PASS}/${TOTAL}"
  exit 0
else
  echo -e "  ${RED}FAIL${NC}: ${PASS}/${TOTAL} 통과, ${FAIL}개 실패"
  exit 1
fi
