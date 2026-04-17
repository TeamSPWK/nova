#!/usr/bin/env bash

# Nova Engineering — PreToolUse Hook (Write|Edit)
# Write/Edit 호출 시 세션 내 편집 파일 수 누적 → 3파일 초과 시 Plan 승격 경고 주입.
# Sprint 1: 경고만, 차단 없음 (exit 0 유지).

INPUT="${TOOL_INPUT:-$(cat)}"

# tool_name 추출 — NOVA_HOOK_INPUT 환경변수로 전달해 따옴표 포함 JSON 안전 처리
TOOL_NAME=$(NOVA_HOOK_INPUT="$INPUT" python3 -c "
import json, os, sys
try:
    raw = os.environ.get('NOVA_HOOK_INPUT', '')
    data = json.loads(raw)
    print(data.get('tool_name', ''))
except Exception:
    sys.exit(0)
" 2>/dev/null || echo "")

# Write 또는 Edit 아니면 종료
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  exit 0
fi

# file_path 추출 — NOVA_HOOK_INPUT 환경변수로 전달해 따옴표 포함 JSON 안전 처리
FILE_PATH=$(NOVA_HOOK_INPUT="$INPUT" python3 -c "
import json, os, sys
try:
    raw = os.environ.get('NOVA_HOOK_INPUT', '')
    data = json.loads(raw)
    print(data.get('tool_input', {}).get('file_path', ''))
except Exception:
    sys.exit(0)
" 2>/dev/null || echo "")

# file_path 빈 문자열이면 종료
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# .nova/ 폴더 없으면 생성
if [ ! -d ".nova" ]; then
  mkdir -p .nova
fi

# .gitignore에 .nova/ 없으면 추가 (.gitignore 없을 때도 생성)
if [ ! -f ".gitignore" ]; then
  echo ".nova/" > .gitignore
elif ! grep -q "^\.nova/" .gitignore 2>/dev/null; then
  echo ".nova/" >> .gitignore
fi

STATE_FILE=".nova/session-state.json"

# state json 없으면 초기화
if [ ! -f "$STATE_FILE" ]; then
  SESSION_ID="${CLAUDE_SESSION_ID:-$(date +%Y%m%d)-$$}"
  STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
  python3 -c "
import json
state = {
    'session_id': '${SESSION_ID}',
    'started_at': '${STARTED_AT}',
    'edited_files': [],
    'warnings_emitted': {'plan_promotion': False}
}
with open('${STATE_FILE}', 'w') as f:
    json.dump(state, f, indent=2)
" 2>/dev/null || exit 0
fi

# state json 읽기
STATE=$(python3 -c "
import json, sys
try:
    with open('${STATE_FILE}') as f:
        state = json.load(f)

    file_path = '''${FILE_PATH}'''
    edited = state.get('edited_files', [])
    warned = state.get('warnings_emitted', {}).get('plan_promotion', False)

    # 이미 있으면 카운트 변경 없음
    if file_path in edited:
        print('ALREADY_TRACKED')
        sys.exit(0)

    # 추가
    edited.append(file_path)
    state['edited_files'] = edited
    count = len(edited)

    with open('${STATE_FILE}', 'w') as f:
        json.dump(state, f, indent=2)

    if count > 3 and not warned:
        file_list = '\n'.join(['  - ' + p for p in edited])
        print('WARN:' + str(count) + ':' + file_list)
    else:
        print('OK:' + str(count))
except Exception as e:
    print('ERROR:' + str(e))
" 2>/dev/null || exit 0)

# 경고 조건 확인
if echo "$STATE" | grep -q "^WARN:"; then
  COUNT=$(echo "$STATE" | python3 -c "import sys; line=sys.stdin.read().strip(); parts=line.split(':',2); print(parts[1])" 2>/dev/null || echo "4")
  FILE_LIST=$(echo "$STATE" | python3 -c "import sys; line=sys.stdin.read().strip(); parts=line.split(':',2); print(parts[2] if len(parts)>2 else '')" 2>/dev/null || echo "")

  # warnings_emitted.plan_promotion = true로 업데이트
  python3 -c "
import json
try:
    with open('${STATE_FILE}') as f:
        state = json.load(f)
    state['warnings_emitted']['plan_promotion'] = True
    with open('${STATE_FILE}', 'w') as f:
        json.dump(state, f, indent=2)
except:
    pass
" 2>/dev/null

  # 경고 JSON 출력
  ESCAPED_FILE_LIST=$(echo "$FILE_LIST" | python3 -c "import sys; s=sys.stdin.read(); print(s.replace('\\\\','\\\\\\\\').replace('\"','\\\\\"').replace(chr(10),'\\\\n').replace(chr(9),'\\\\t').rstrip())" 2>/dev/null || echo "$FILE_LIST")

  cat << NOVA_EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "[Nova Quality Gate] 편집 파일 ${COUNT}개 누적 감지.\n\n이 세션에서 수정된 파일:\n${ESCAPED_FILE_LIST}\n\n§1 규칙: 3파일 이상 변경은 Plan을 먼저 작성해야 합니다.\nPlan이 작성되지 않았다면 지금 중단하고 /nova:plan을 실행하세요.\nPlan이 이미 승인된 상태라면 계속 진행해도 됩니다."
  }
}
NOVA_EOF
fi

exit 0
