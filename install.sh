#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# claude-config installer
# ============================================================

REPO_URL="https://github.com/wh131462/claude-config.git"
RAW_URL="https://raw.githubusercontent.com/wh131462/claude-config/master/install.sh"
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd || echo "")"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

# ---------- 自举: 当从管道执行时 (curl | bash)，下载脚本到临时目录后重新执行 ----------
# 这样可以让 stdin 完全自由，支持完整的交互体验。
if [[ "${CLAUDE_CONFIG_BOOTSTRAPPED:-0}" != "1" ]] && [[ ! -t 0 ]] && [[ -z "$SCRIPT_PATH" || ! -f "$SCRIPT_PATH" ]]; then
  if [[ ! -e /dev/tty ]]; then
    echo "当前环境无 /dev/tty，无法交互式安装。请使用 --all 或 git clone 后执行。" >&2
    exit 1
  fi
  TMP_SCRIPT="$(mktemp -t claude-config-install.XXXXXX)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW_URL" -o "$TMP_SCRIPT" || { echo "下载安装脚本失败" >&2; exit 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_SCRIPT" "$RAW_URL" || { echo "下载安装脚本失败" >&2; exit 1; }
  else
    echo "需要 curl 或 wget 来下载安装脚本" >&2
    exit 1
  fi
  chmod +x "$TMP_SCRIPT"
  export CLAUDE_CONFIG_BOOTSTRAPPED=1
  exec bash "$TMP_SCRIPT" "$@" </dev/tty
fi

# ---------- colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err()   { printf "${RED}[ERR]${NC}   %s\n" "$*" >&2; }

# ---------- usage ----------
usage() {
  cat <<EOF
${BOLD}claude-config installer${NC}

用法:
  ./install.sh [选项]

选项:
  --global          安装到用户全局 (~/.claude/)
  --project         安装到当前项目 (./.claude/)  [默认]
  --target <path>   安装到指定目录
  --force           已存在文件时直接覆盖 (默认备份后覆盖)
  --all             安装所有 skills，跳过交互选择
  --no-claude-md    不安装 CLAUDE.md
  --help            显示此帮助信息

示例:
  ./install.sh                     # 交互式安装到当前项目
  ./install.sh --global --all      # 全部安装到全局
  curl -fsSL <raw-url>/install.sh | bash -s -- --global
EOF
  exit 0
}

# ---------- detect source dir ----------
detect_source() {
  if [[ -d "$SCRIPT_DIR/.claude/skills" ]]; then
    SOURCE_DIR="$SCRIPT_DIR"
  else
    info "未检测到本地 skill 文件，正在从远程克隆..."
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    git clone --depth 1 "$REPO_URL" "$tmp_dir" 2>/dev/null || {
      err "克隆仓库失败，请检查网络或手动克隆后再执行"
      exit 1
    }
    SOURCE_DIR="$tmp_dir"
    CLEANUP_TMP=true
  fi
}

# ---------- parse args ----------
MODE="project"
FORCE=false
ALL=false
INSTALL_CLAUDE_MD=true
TARGET_DIR=""
CLEANUP_TMP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)       MODE="global"; shift ;;
    --project)      MODE="project"; shift ;;
    --target)       MODE="custom"; TARGET_DIR="$2"; shift 2 ;;
    --force)        FORCE=true; shift ;;
    --all)          ALL=true; shift ;;
    --no-claude-md) INSTALL_CLAUDE_MD=false; shift ;;
    --help|-h)      usage ;;
    *) err "未知参数: $1"; usage ;;
  esac
done

# ---------- resolve dest ----------
resolve_dest() {
  case "$MODE" in
    global)  DEST_DIR="$HOME/.claude" ;;
    project) DEST_DIR="$(pwd)/.claude" ;;
    custom)  DEST_DIR="$TARGET_DIR" ;;
  esac
  DEST_SKILLS="$DEST_DIR/skills"

  case "$MODE" in
    global)  CLAUDE_MD_DEST="$HOME/.claude/CLAUDE.md" ;;
    project) CLAUDE_MD_DEST="$(pwd)/CLAUDE.md" ;;
    custom)  CLAUDE_MD_DEST="$TARGET_DIR/CLAUDE.md" ;;
  esac
}

# ---------- backup helper ----------
safe_copy() {
  local src="$1" dest="$2"
  if [[ -e "$dest" ]]; then
    if $FORCE; then
      cp -f "$src" "$dest"
    else
      local bak="${dest}.bak.${TIMESTAMP}"
      cp "$dest" "$bak"
      warn "已备份: $(basename "$dest") -> $(basename "$bak")"
      cp -f "$src" "$dest"
    fi
  else
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  fi
}

safe_copy_dir() {
  local src="$1" dest="$2"
  if [[ -d "$dest" ]]; then
    if $FORCE; then
      rm -rf "$dest"
      cp -r "$src" "$dest"
    else
      local bak="${dest}.bak.${TIMESTAMP}"
      cp -r "$dest" "$bak"
      warn "已备份: $(basename "$dest") -> $(basename "$bak")"
      rm -rf "$dest"
      cp -r "$src" "$dest"
    fi
  else
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
  fi
}

# ---------- list available skills ----------
list_skills() {
  local skills_dir="$SOURCE_DIR/.claude/skills"
  local skills=()
  for d in "$skills_dir"/*/; do
    [[ -d "$d" ]] && skills+=("$(basename "$d")")
  done
  echo "${skills[@]}"
}

# ---------- interactive selection ----------
interactive_select() {
  local skills
  read -ra skills <<< "$(list_skills)"
  local count=${#skills[@]}

  if [[ $count -eq 0 ]]; then
    err "未找到可用的 skills"
    exit 1
  fi

  printf "\n${BOLD}可用的 Skills:${NC}\n\n"

  local descs=()
  for i in "${!skills[@]}"; do
    local skill="${skills[$i]}"
    local skill_file="$SOURCE_DIR/.claude/skills/$skill/SKILL.md"
    local desc=""
    if [[ -f "$skill_file" ]]; then
      desc="$(sed -n 's/^description: *//p' "$skill_file" | head -1)"
    fi
    descs+=("$desc")
    printf "  ${CYAN}%2d)${NC} %-20s %s\n" "$((i+1))" "$skill" "$desc"
  done

  printf "\n输入编号选择 (逗号分隔, a=全选, q=取消): "
  read -r selection

  if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    info "已取消安装"
    exit 0
  fi

  SELECTED_SKILLS=()
  if [[ "$selection" == "a" || "$selection" == "A" ]]; then
    SELECTED_SKILLS=("${skills[@]}")
  else
    IFS=',' read -ra indices <<< "$selection"
    for idx in "${indices[@]}"; do
      idx="$(echo "$idx" | tr -d ' ')"
      if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= count )); then
        SELECTED_SKILLS+=("${skills[$((idx-1))]}")
      else
        warn "无效编号: $idx，已跳过"
      fi
    done
  fi

  if [[ ${#SELECTED_SKILLS[@]} -eq 0 ]]; then
    err "未选择任何 skill"
    exit 1
  fi
}

# ---------- install ----------
do_install() {
  resolve_dest

  printf "\n${BOLD}========== claude-config 安装 ==========${NC}\n\n"
  info "安装模式: $MODE"
  info "目标目录: $DEST_DIR"
  printf "\n"

  # CLAUDE.md
  if $INSTALL_CLAUDE_MD && [[ -f "$SOURCE_DIR/CLAUDE.md" ]]; then
    safe_copy "$SOURCE_DIR/CLAUDE.md" "$CLAUDE_MD_DEST"
    ok "CLAUDE.md -> $CLAUDE_MD_DEST"
  fi

  # skills
  local skills_to_install=()
  if $ALL; then
    read -ra skills_to_install <<< "$(list_skills)"
  else
    interactive_select
    skills_to_install=("${SELECTED_SKILLS[@]}")
  fi

  mkdir -p "$DEST_SKILLS"

  for skill in "${skills_to_install[@]}"; do
    local src="$SOURCE_DIR/.claude/skills/$skill"
    local dest="$DEST_SKILLS/$skill"
    safe_copy_dir "$src" "$dest"
    ok "skill: $skill"
  done

  printf "\n${GREEN}${BOLD}安装完成!${NC}\n"
  printf "已安装 ${CYAN}%d${NC} 个 skills" "${#skills_to_install[@]}"
  $INSTALL_CLAUDE_MD && printf " + ${CYAN}CLAUDE.md${NC}"
  printf "\n\n"
}

# ---------- main ----------
main() {
  detect_source
  do_install

  if $CLEANUP_TMP && [[ -n "${SOURCE_DIR:-}" ]]; then
    rm -rf "$SOURCE_DIR"
  fi
}

main
