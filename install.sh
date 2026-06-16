#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# claude-config installer
# ============================================================

REPO_PATH="wh131462/claude-config"
REPO_BRANCH="master"

# 多镜像源 (按顺序尝试)
REPO_MIRRORS=(
  "https://github.com/${REPO_PATH}.git"
  "https://gh-proxy.com/https://github.com/${REPO_PATH}.git"
  "https://ghproxy.net/https://github.com/${REPO_PATH}.git"
  "https://gitclone.com/github.com/${REPO_PATH}.git"
)

RAW_MIRRORS=(
  "https://raw.githubusercontent.com/${REPO_PATH}/${REPO_BRANCH}/install.sh"
  "https://gh-proxy.com/https://raw.githubusercontent.com/${REPO_PATH}/${REPO_BRANCH}/install.sh"
  "https://ghproxy.net/https://raw.githubusercontent.com/${REPO_PATH}/${REPO_BRANCH}/install.sh"
  "https://raw.gitmirror.com/${REPO_PATH}/${REPO_BRANCH}/install.sh"
)

# 网络超时 (秒)
NET_CONNECT_TIMEOUT=5
NET_MAX_TIME=30
CLONE_TIMEOUT=60

SCRIPT_PATH="${BASH_SOURCE[0]:-}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd || echo "")"

# ---------- 自举: 当从管道执行时 (curl | bash)，下载脚本到临时目录后重新执行 ----------
# 这样可以让 stdin 完全自由，支持完整的交互体验。
if [[ "${CLAUDE_CONFIG_BOOTSTRAPPED:-0}" != "1" ]] && [[ ! -t 0 ]] && [[ -z "$SCRIPT_PATH" || ! -f "$SCRIPT_PATH" ]]; then
  if [[ ! -e /dev/tty ]]; then
    echo "当前环境无 /dev/tty，无法交互式安装。请使用 --all 或 git clone 后执行。" >&2
    exit 1
  fi
  TMP_SCRIPT="$(mktemp -t claude-config-install.XXXXXX)"
  DOWNLOAD_OK=false
  for raw_url in "${RAW_MIRRORS[@]}"; do
    echo "尝试下载: $raw_url" >&2
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --connect-timeout "$NET_CONNECT_TIMEOUT" --max-time "$NET_MAX_TIME" "$raw_url" -o "$TMP_SCRIPT" 2>/dev/null && DOWNLOAD_OK=true && break
    elif command -v wget >/dev/null 2>&1; then
      wget --timeout="$NET_MAX_TIME" --tries=1 -qO "$TMP_SCRIPT" "$raw_url" 2>/dev/null && DOWNLOAD_OK=true && break
    else
      echo "需要 curl 或 wget 来下载安装脚本" >&2
      exit 1
    fi
  done
  if ! $DOWNLOAD_OK; then
    echo "所有镜像源均下载失败，请检查网络连接" >&2
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
  --all             安装所有 skills，跳过交互选择 (隐含 --yes)
  --yes, -y         跳过覆盖确认，直接覆盖已存在的文件
  --no-claude-md    不安装 CLAUDE.md
  --help            显示此帮助信息

注意: 已存在的文件/目录会被直接覆盖，不会备份。

示例:
  ./install.sh                     # 交互式安装到当前项目
  ./install.sh --global --all      # 全部安装到全局
  curl -fsSL <raw-url>/install.sh | bash -s -- --global
EOF
  exit 0
}

# ---------- detect source dir ----------
clone_with_timeout() {
  local url="$1" dest="$2"
  if command -v timeout >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 timeout "$CLONE_TIMEOUT" git clone --depth 1 "$url" "$dest" 2>/dev/null
  elif command -v gtimeout >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 gtimeout "$CLONE_TIMEOUT" git clone --depth 1 "$url" "$dest" 2>/dev/null
  else
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$url" "$dest" 2>/dev/null
  fi
}

detect_source() {
  if [[ -d "$SCRIPT_DIR/.claude/skills" ]]; then
    SOURCE_DIR="$SCRIPT_DIR"
    return
  fi
  info "未检测到本地 skill 文件，尝试从远程克隆..."
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local cloned=false
  for repo_url in "${REPO_MIRRORS[@]}"; do
    info "尝试镜像: $repo_url"
    rm -rf "$tmp_dir" && mkdir -p "$tmp_dir"
    if clone_with_timeout "$repo_url" "$tmp_dir"; then
      cloned=true
      ok "克隆成功: $repo_url"
      break
    else
      warn "镜像不可用，切换下一个..."
    fi
  done
  if ! $cloned; then
    err "所有镜像源均克隆失败，请检查网络或手动克隆后再执行"
    rm -rf "$tmp_dir"
    exit 1
  fi
  SOURCE_DIR="$tmp_dir"
  CLEANUP_TMP=true
}

# ---------- parse args ----------
MODE="project"
MODE_EXPLICIT=false
ALL=false
YES=false
INSTALL_CLAUDE_MD=true
TARGET_DIR=""
CLEANUP_TMP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)       MODE="global"; MODE_EXPLICIT=true; shift ;;
    --project)      MODE="project"; MODE_EXPLICIT=true; shift ;;
    --target)       MODE="custom"; MODE_EXPLICIT=true; TARGET_DIR="$2"; shift 2 ;;
    --all)          ALL=true; YES=true; shift ;;
    --yes|-y)       YES=true; shift ;;
    --no-claude-md) INSTALL_CLAUDE_MD=false; shift ;;
    --force)        YES=true; shift ;;  # 兼容旧参数
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

# ---------- copy helpers ----------
safe_copy() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  cp -f "$src" "$dest"
}

safe_copy_dir() {
  local src="$1" dest="$2"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -r "$src" "$dest"
}

# ---------- interactive mode selection ----------
interactive_mode() {
  printf "\n${BOLD}请选择安装位置:${NC}\n\n"
  printf "  ${CYAN}1)${NC} 全局         %s/.claude/\n" "$HOME"
  printf "  ${CYAN}2)${NC} 当前项目     %s/.claude/\n" "$(pwd)"
  printf "  ${CYAN}3)${NC} 自定义路径\n"
  printf "\n请输入编号 [默认 2]: "
  local choice
  read -r choice
  case "${choice:-2}" in
    1) MODE="global" ;;
    2) MODE="project" ;;
    3)
       printf "请输入自定义路径: "
       read -r TARGET_DIR
       if [[ -z "$TARGET_DIR" ]]; then
         err "自定义路径不能为空"
         exit 1
       fi
       MODE="custom"
       ;;
    *) err "无效编号: $choice"; exit 1 ;;
  esac
}

# ---------- confirm overwrite ----------
confirm_overwrite() {
  local conflicts=()
  if $INSTALL_CLAUDE_MD && [[ -f "$CLAUDE_MD_DEST" ]]; then
    conflicts+=("$CLAUDE_MD_DEST")
  fi
  for skill in "$@"; do
    [[ -e "$DEST_SKILLS/$skill" ]] && conflicts+=("$DEST_SKILLS/$skill")
  done

  [[ ${#conflicts[@]} -eq 0 ]] && return 0
  $YES && return 0

  printf "\n${YELLOW}以下文件/目录已存在，将被覆盖:${NC}\n"
  for c in "${conflicts[@]}"; do
    printf "  - %s\n" "$c"
  done
  printf "\n是否继续? [y/N]: "
  local ans
  read -r ans
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) info "已取消安装"; exit 0 ;;
  esac
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
# 读取单个按键（含转义序列）
# 返回字符串: UP / DOWN / SPACE / ENTER / CTRL_C / INFO / OTHER
read_key() {
  local key rest
  IFS= read -rsn1 key
  if [[ "$key" == $'\x1b' ]]; then
    # 方向键的转义序列 ESC[A/ESC[B 会同时到达，无需小数秒超时
    # macOS bash 3.2 不支持 -t 小数，这里用 -t 1 兼容兜底
    IFS= read -rsn2 -t 1 rest 2>/dev/null || rest=""
    key+="$rest"
    case "$key" in
      $'\x1b[A') echo "UP" ;;
      $'\x1b[B') echo "DOWN" ;;
      *)         echo "OTHER" ;;
    esac
  elif [[ "$key" == "" ]]; then
    echo "ENTER"
  elif [[ "$key" == " " ]]; then
    echo "SPACE"
  elif [[ "$key" == $'\x03' ]]; then
    echo "CTRL_C"
  elif [[ "$key" == "i" || "$key" == "I" ]]; then
    echo "INFO"
  else
    echo "OTHER"
  fi
}

# 截断字符串到指定长度
truncate_str() {
  local str="$1" max="${2:-60}"
  if [[ ${#str} -le $max ]]; then
    printf "%s" "$str"
  else
    printf "%s..." "${str:0:$max}"
  fi
}

interactive_select() {
  local skills
  read -ra skills <<< "$(list_skills)"
  local count=${#skills[@]}

  if [[ $count -eq 0 ]]; then
    err "未找到可用的 skills"
    exit 1
  fi

  local descs=()
  for i in "${!skills[@]}"; do
    local skill="${skills[$i]}"
    local skill_file="$SOURCE_DIR/.claude/skills/$skill/SKILL.md"
    local desc=""
    if [[ -f "$skill_file" ]]; then
      desc="$(sed -n 's/^description: *//p' "$skill_file" | head -1)"
    fi
    descs+=("$desc")
  done

  # items: 索引 0 = All, 索引 1..count = skills
  local total=$((count + 1))
  local selected=()
  local i
  for ((i=0; i<total; i++)); do
    selected[i]=0
  done

  local cursor=0
  local first_draw=1
  local last_lines=0
  local showing_detail=0

  draw_menu() {
    if [[ $first_draw -eq 0 ]]; then
      printf "\033[%dA" "$last_lines"
      printf "\033[J"
    fi
    first_draw=0

    if [[ $showing_detail -eq 1 ]]; then
      local name desc
      if [[ $cursor -eq 0 ]]; then
        name="All"
        desc="全选所有 skills"
      else
        local idx=$((cursor - 1))
        name="${skills[$idx]}"
        desc="${descs[$idx]}"
      fi
      printf "\n${BOLD}可用的 Skills:${NC}\n\n"
      printf "${CYAN}  %s${NC}\n" "$name"
      printf "  %s\n\n" "$desc"
      printf "${YELLOW}  [按任意键返回列表]${NC}\n"
      last_lines=7
    else
      printf "\n${BOLD}可用的 Skills:${NC}\n\n"
      printf "${YELLOW}  [↑/↓] 移动  [空格] 切换  [i] 详情  [回车] 确认${NC}\n\n"

      for ((i=0; i<total; i++)); do
        local mark="◯"
        [[ "${selected[$i]}" == "1" ]] && mark="$(printf "${GREEN}◉${NC}")"
        local arrow=" "
        [[ $cursor -eq $i ]] && arrow="$(printf "${CYAN}→${NC}")"

        if [[ $i -eq 0 ]]; then
          printf "  %s %s %-22s %s\n" "$arrow" "$mark" "All" "全选所有 skills"
        else
          local idx=$((i - 1))
          local short
          short=$(truncate_str "${descs[$idx]}" 60)
          printf "  %s %s %-22s %s\n" "$arrow" "$mark" "${skills[$idx]}" "$short"
        fi
      done
      last_lines=$((total + 4))
    fi
  }

  # 同步 All 选项状态
  sync_all() {
    local all_on=1
    for ((i=1; i<total; i++)); do
      [[ "${selected[$i]}" != "1" ]] && all_on=0 && break
    done
    selected[0]=$all_on
  }

  draw_menu

  while true; do
    local key
    key=$(read_key </dev/tty)

    if [[ $showing_detail -eq 1 ]]; then
      showing_detail=0
      draw_menu
      continue
    fi

    case "$key" in
      UP)
        cursor=$((cursor - 1))
        [[ $cursor -lt 0 ]] && cursor=$((total - 1))
        draw_menu
        ;;
      DOWN)
        cursor=$(((cursor + 1) % total))
        draw_menu
        ;;
      INFO)
        showing_detail=1
        draw_menu
        ;;
      SPACE)
        if [[ $cursor -eq 0 ]]; then
          local new_state=$((1 - ${selected[0]}))
          for ((i=0; i<total; i++)); do
            selected[i]=$new_state
          done
        else
          selected[$cursor]=$((1 - ${selected[$cursor]}))
          sync_all
        fi
        draw_menu
        ;;
      ENTER)
        SELECTED_SKILLS=()
        if [[ "${selected[0]}" == "1" ]]; then
          SELECTED_SKILLS=("${skills[@]}")
        else
          for ((i=1; i<total; i++)); do
            if [[ "${selected[$i]}" == "1" ]]; then
              SELECTED_SKILLS+=("${skills[$((i-1))]}")
            fi
          done
        fi

        if [[ ${#SELECTED_SKILLS[@]} -eq 0 ]]; then
          printf "\n"
          err "未选择任何 skill"
          exit 1
        fi
        printf "\n"
        return
        ;;
      CTRL_C)
        printf "\n"
        info "已取消安装"
        exit 0
        ;;
    esac
  done
}

# ---------- install ----------
do_install() {
  if ! $MODE_EXPLICIT && ! $ALL; then
    interactive_mode
  fi

  resolve_dest

  printf "\n${BOLD}========== claude-config 安装 ==========${NC}\n\n"
  info "安装模式: $MODE"
  info "目标目录: $DEST_DIR"
  printf "\n"

  # skills
  local skills_to_install=()
  if $ALL; then
    read -ra skills_to_install <<< "$(list_skills)"
  else
    interactive_select
    skills_to_install=("${SELECTED_SKILLS[@]}")
  fi

  confirm_overwrite "${skills_to_install[@]}"

  # CLAUDE.md
  if $INSTALL_CLAUDE_MD && [[ -f "$SOURCE_DIR/CLAUDE.md" ]]; then
    safe_copy "$SOURCE_DIR/CLAUDE.md" "$CLAUDE_MD_DEST"
    ok "CLAUDE.md -> $CLAUDE_MD_DEST"
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
