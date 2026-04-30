#!/bin/bash
# Nova — Codex recommended plugin installer
# Usage: bash scripts/install-codex-recommended-plugins.sh

set -euo pipefail

GUIDE_PATH="docs/guides/codex-plugins.md"
CODEX_CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"
CODEX_PLUGIN_CACHE_DIR="${CODEX_PLUGIN_CACHE_DIR:-$HOME/.codex/plugins/cache}"
NOVA_GIT_URL="${NOVA_GIT_URL:-https://github.com/TeamSPWK/nova.git}"
NOVA_REF="${NOVA_REF:-main}"
NOVA_INSTALL_DIR="${NOVA_INSTALL_DIR:-$HOME/.codex/marketplaces/nova}"

SKIP_MCP_BUILD=0
SKIP_MCP_FALLBACK=0
FORCE_REMOTE=0
LOCAL_ROOT=""

RECOMMENDED_PLUGINS=(
  "browser-use@openai-bundled"
  "documents@openai-primary-runtime"
  "spreadsheets@openai-primary-runtime"
  "presentations@openai-primary-runtime"
  "nova@nova-marketplace"
)

usage() {
  cat <<EOF
Nova Codex recommended plugin installer

Installs/enables:
  - Browser Use
  - Documents
  - Spreadsheets
  - Presentations
  - Nova

Usage:
  bash scripts/install-codex-recommended-plugins.sh [options]

Options:
  --local PATH          Use an existing Nova checkout as the marketplace root.
  --remote             Clone/update Nova into \$NOVA_INSTALL_DIR even when run inside a checkout.
  --skip-mcp-build     Do not run pnpm install/build for the Nova MCP server.
  --no-mcp-fallback    Do not write [mcp_servers.nova] into ~/.codex/config.toml.
  -h, --help           Show this help.

Environment:
  CODEX_CONFIG         Codex config path. Default: ~/.codex/config.toml
  CODEX_PLUGIN_CACHE_DIR
                       Codex plugin cache root. Default: ~/.codex/plugins/cache
  NOVA_GIT_URL         Nova git URL. Default: https://github.com/TeamSPWK/nova.git
  NOVA_REF             Git ref for remote install. Default: main
  NOVA_INSTALL_DIR     Remote install directory. Default: ~/.codex/marketplaces/nova

Guide:
  $GUIDE_PATH
EOF
}

log() {
  printf '==> %s\n' "$1" >&2
}

ok() {
  printf '✓ %s\n' "$1"
}

warn() {
  printf 'WARN: %s\n' "$1" >&2
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "'$1' command not found"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      [[ $# -ge 2 ]] || fail "--local requires a path"
      LOCAL_ROOT="$2"
      shift 2
      ;;
    --remote)
      FORCE_REMOTE=1
      shift
      ;;
    --skip-mcp-build)
      SKIP_MCP_BUILD=1
      shift
      ;;
    --no-mcp-fallback)
      SKIP_MCP_FALLBACK=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

repo_root_from() {
  local candidate="$1"
  if [[ -f "$candidate/.codex-plugin/plugin.json" && -f "$candidate/.agents/plugins/marketplace.json" ]]; then
    (cd "$candidate" && pwd)
    return 0
  fi
  return 1
}

script_dir_from_bash_source() {
  local source_path="${BASH_SOURCE[0]:-}"
  local source_dir=""

  [[ -n "$source_path" ]] || return 1

  source_dir="$(cd "$(dirname "$source_path")" 2>/dev/null && pwd || true)"
  [[ -n "$source_dir" ]] || return 1

  printf '%s\n' "$source_dir"
}

clone_or_update_nova() {
  require_command git

  mkdir -p "$(dirname "$NOVA_INSTALL_DIR")"

  if [[ -d "$NOVA_INSTALL_DIR/.git" ]]; then
    log "Updating Nova checkout: $NOVA_INSTALL_DIR"
    if ! git -C "$NOVA_INSTALL_DIR" diff --quiet || ! git -C "$NOVA_INSTALL_DIR" diff --cached --quiet; then
      fail "$NOVA_INSTALL_DIR has local changes. Commit/stash them or set NOVA_INSTALL_DIR to a clean path."
    fi
    git -C "$NOVA_INSTALL_DIR" fetch --depth 1 origin "$NOVA_REF"
    git -C "$NOVA_INSTALL_DIR" checkout -q FETCH_HEAD
  elif [[ -e "$NOVA_INSTALL_DIR" ]]; then
    fail "$NOVA_INSTALL_DIR exists but is not a git checkout"
  else
    log "Cloning Nova into $NOVA_INSTALL_DIR"
    git clone --depth 1 --branch "$NOVA_REF" "$NOVA_GIT_URL" "$NOVA_INSTALL_DIR"
  fi

  repo_root_from "$NOVA_INSTALL_DIR"
}

detect_nova_root() {
  if [[ -n "$LOCAL_ROOT" ]]; then
    repo_root_from "$LOCAL_ROOT" || fail "--local path is not a Nova marketplace root: $LOCAL_ROOT"
    return 0
  fi

  if [[ "$FORCE_REMOTE" -eq 0 ]]; then
    local script_dir=""
    if script_dir="$(script_dir_from_bash_source)" && repo_root_from "$script_dir/.." >/dev/null 2>&1; then
      repo_root_from "$script_dir/.."
      return 0
    fi

    if repo_root_from "$PWD" >/dev/null 2>&1; then
      repo_root_from "$PWD"
      return 0
    fi
  fi

  clone_or_update_nova
}

ensure_pnpm() {
  if command -v pnpm >/dev/null 2>&1; then
    return 0
  fi

  if command -v corepack >/dev/null 2>&1; then
    log "pnpm not found; enabling it with corepack"
    corepack enable
    corepack prepare pnpm@latest --activate
  fi

  command -v pnpm >/dev/null 2>&1 || fail "pnpm not found. Install Node.js with corepack or run: npm install -g pnpm"
}

build_mcp_server() {
  local nova_root="$1"
  local mcp_dir="$nova_root/mcp-server"

  [[ -f "$mcp_dir/package.json" ]] || fail "MCP package not found: $mcp_dir/package.json"
  require_command node
  ensure_pnpm

  log "Building Nova MCP server"
  (
    cd "$mcp_dir"
    COREPACK_ENABLE_AUTO_PIN=0 pnpm install --frozen-lockfile
    COREPACK_ENABLE_AUTO_PIN=0 pnpm build
  )
  [[ -f "$mcp_dir/dist/index.js" ]] || fail "MCP build output missing: $mcp_dir/dist/index.js"
  ok "Nova MCP server built"
}

plugin_version() {
  local nova_root="$1"
  local version

  version="$(sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$nova_root/.codex-plugin/plugin.json" | head -1)"
  [[ -n "$version" ]] || fail "Cannot read version from $nova_root/.codex-plugin/plugin.json"
  printf '%s\n' "$version"
}

materialize_nova_plugin_cache() {
  local nova_root="$1"
  local version
  local target
  local source_abs
  local target_abs

  require_command rsync

  version="$(plugin_version "$nova_root")"
  target="$CODEX_PLUGIN_CACHE_DIR/nova-marketplace/nova/$version"

  mkdir -p "$target"
  source_abs="$(cd "$nova_root" && pwd)"
  target_abs="$(cd "$target" && pwd)"

  if [[ "$source_abs" == "$target_abs" ]]; then
    ok "Nova plugin cache already materialized: $target_abs"
    return 0
  fi

  log "Materializing Nova plugin cache: $target_abs"

  # Codex loads enabled plugin skills from this cache. Keep generated runtime
  # artifacts that are needed by the plugin, but do not copy local secrets/state.
  rsync -a --delete --delete-excluded \
    --include='/.env.example' \
    --exclude='/.git/' \
    --exclude='/.env' \
    --exclude='/.env.*' \
    --exclude='/.envrc' \
    --exclude='/.npmrc' \
    --exclude='/.secret/' \
    --exclude='/NOVA-STATE.md' \
    --exclude='/.nova/' \
    --exclude='/.nova-worktrees/' \
    --exclude='/.nova-orchestration.json' \
    --exclude='/tests/.cache/' \
    --exclude='/nova-events/' \
    --exclude='/node_modules/' \
    --exclude='/mcp-server/node_modules/' \
    "$nova_root/" "$target_abs/"

  ok "Nova plugin cache materialized"
}

toml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

ensure_config_file() {
  mkdir -p "$(dirname "$CODEX_CONFIG")"
  if [[ ! -f "$CODEX_CONFIG" ]]; then
    : > "$CODEX_CONFIG"
    chmod 600 "$CODEX_CONFIG" 2>/dev/null || true
  fi
}

backup_config() {
  local backup
  backup="$CODEX_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
  cp "$CODEX_CONFIG" "$backup"
  ok "Backed up Codex config: $backup"
}

upsert_toml_block() {
  local heading="$1"
  local body="$2"
  local awk_body
  local tmp
  awk_body="${body//$'\n'/\\n}"
  tmp="$(mktemp)"

  awk -v heading="$heading" -v body="$awk_body" '
    BEGIN {
      gsub(/\\n/, "\n", body)
      in_target = 0
      found = 0
    }
    $0 == heading {
      if (!found) {
        print heading
        print body
        found = 1
      }
      in_target = 1
      next
    }
    /^\[/ {
      if (in_target) {
        in_target = 0
      }
    }
    !in_target {
      print
    }
    END {
      if (!found) {
        print ""
        print heading
        print body
      }
    }
  ' "$CODEX_CONFIG" > "$tmp"

  mv "$tmp" "$CODEX_CONFIG"
  chmod 600 "$CODEX_CONFIG" 2>/dev/null || true
}

enable_plugins() {
  log "Enabling recommended Codex plugins"

  # Built-in marketplaces may already be registered by Codex Desktop/CLI.
  # Upgrade is best-effort; config entries below are the durable activation step.
  codex plugin marketplace upgrade openai-bundled >/dev/null 2>&1 || true
  codex plugin marketplace upgrade openai-primary-runtime >/dev/null 2>&1 || true

  local plugin
  for plugin in "${RECOMMENDED_PLUGINS[@]}"; do
    upsert_toml_block "[plugins.\"$plugin\"]" "enabled = true"
    ok "enabled $plugin"
  done
}

register_nova_marketplace() {
  local nova_root="$1"

  require_command codex
  log "Registering Nova marketplace: $nova_root"

  if codex plugin marketplace add "$nova_root"; then
    ok "Nova marketplace registered"
  else
    warn "codex marketplace add failed; continuing in case nova-marketplace is already registered"
    codex plugin marketplace upgrade nova-marketplace >/dev/null 2>&1 || true
  fi
}

write_mcp_fallback() {
  local nova_root="$1"
  local entrypoint
  local escaped_entrypoint
  entrypoint="$nova_root/mcp-server/dist/index.js"
  escaped_entrypoint="$(toml_escape "$entrypoint")"

  [[ -f "$entrypoint" ]] || warn "MCP entrypoint not found yet: $entrypoint"

  upsert_toml_block "[mcp_servers.nova]" "$(printf 'command = "node"\nargs = ["%s"]' "$escaped_entrypoint")"
  ok "registered Nova MCP fallback"
}

verify_install() {
  local nova_root="$1"
  local plugin

  log "Verifying config"
  for plugin in "${RECOMMENDED_PLUGINS[@]}"; do
    grep -F "[plugins.\"$plugin\"]" "$CODEX_CONFIG" >/dev/null || fail "missing config block for $plugin"
  done

  if [[ "$SKIP_MCP_FALLBACK" -eq 0 ]]; then
    grep -F "[mcp_servers.nova]" "$CODEX_CONFIG" >/dev/null || fail "missing Nova MCP fallback config"
  fi

  if [[ "$SKIP_MCP_BUILD" -eq 0 ]]; then
    [[ -f "$nova_root/mcp-server/dist/index.js" ]] || fail "missing Nova MCP build output"
  fi

  ok "Codex recommended plugins are configured"
}

main() {
  require_command codex

  local nova_root
  nova_root="$(detect_nova_root)"
  log "Using Nova root: $nova_root"

  ensure_config_file
  backup_config

  register_nova_marketplace "$nova_root"

  if [[ "$SKIP_MCP_BUILD" -eq 0 ]]; then
    build_mcp_server "$nova_root"
  else
    warn "Skipping MCP build"
  fi

  materialize_nova_plugin_cache "$nova_root"

  enable_plugins

  if [[ "$SKIP_MCP_FALLBACK" -eq 0 ]]; then
    write_mcp_fallback "$nova_root"
  else
    warn "Skipping MCP fallback config"
  fi

  verify_install "$nova_root"

  cat <<EOF

Done. Restart Codex so the plugin list and MCP server reload.

Install one-liner:
  curl -fsSL https://raw.githubusercontent.com/TeamSPWK/nova/main/scripts/install-codex-recommended-plugins.sh | bash

Guide:
  $GUIDE_PATH
EOF
}

main "$@"
