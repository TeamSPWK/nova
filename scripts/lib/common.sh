#!/bin/bash
# AXIS Kit — 공통 쉘 유틸리티
# Usage: source "$(dirname "$0")/lib/common.sh"

# 색상
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# .env 로드
load_env() {
  local env_file="${1:-.env}"
  if [[ -f "$env_file" ]]; then
    set -a
    source "$env_file"
    set +a
  fi
}

# 필수 명령어 검사
require_commands() {
  for cmd in "$@"; do
    if ! command -v "$cmd" &> /dev/null; then
      echo -e "${RED}ERROR: '${BOLD}$cmd${NC}${RED}'이 설치되어 있지 않습니다.${NC}"
      echo -e "  ${YELLOW}\$ brew install $cmd${NC}  (macOS)"
      echo -e "  ${YELLOW}\$ apt install $cmd${NC}   (Ubuntu)"
      exit 1
    fi
  done
}

# 배너 출력
banner() {
  local title="$1"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}  ${title}${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 구분선만 출력
divider() {
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 업데이트 체크 (하루 1회, 백그라운드, 실패 무시)
check_update() {
  local version_file
  # common.sh 기준으로 scripts/.axis-version 찾기
  version_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.axis-version"
  [[ -f "$version_file" ]] || return 0

  local cache_file="/tmp/.axis-update-check"
  local now
  now=$(date +%s)

  # 24시간 이내 체크했으면 스킵
  if [[ -f "$cache_file" ]]; then
    local last_check
    last_check=$(cat "$cache_file" 2>/dev/null || echo "0")
    if (( now - last_check < 86400 )); then
      # 캐시에 업데이트 안내가 있으면 출력
      if [[ -f "${cache_file}.msg" ]]; then
        cat "${cache_file}.msg"
      fi
      return 0
    fi
  fi

  # 백그라운드에서 체크
  (
    local local_ver
    local_ver=$(cat "$version_file" 2>/dev/null | tr -d '[:space:]')
    local remote_ver
    remote_ver=$(curl -fsSL --max-time 3 "https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/scripts/.axis-version" 2>/dev/null | tr -d '[:space:]')

    echo "$now" > "$cache_file"

    if [[ -n "$remote_ver" && "$local_ver" != "$remote_ver" ]]; then
      local msg
      msg=$(echo -e "  ${YELLOW}🔄 AXIS Kit 업데이트 가능 (${local_ver} → ${remote_ver})${NC}")
      msg+=$'\n'
      msg+=$(echo -e "     ${CYAN}curl -fsSL https://raw.githubusercontent.com/TeamSPWK/axis-kit/main/install.sh | bash -s -- --update${NC}")
      echo "$msg" > "${cache_file}.msg"
      echo ""
      echo "$msg"
      echo ""
    else
      rm -f "${cache_file}.msg"
    fi
  ) &
}
