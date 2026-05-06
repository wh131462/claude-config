# claude-config

个人常用的 Claude Code 配置集合，包含自定义 Skills 和 CLAUDE.md 规则文件。

通过安装脚本可以快速将配置部署到任意项目或全局环境。

## 包含内容

### CLAUDE.md

Claude Code 的核心行为规则，包括：简体中文输出、最小改动原则、安全编码约束、网络访问规则等。

### Skills

| Skill | 说明 |
|-------|------|
| `smart-commit` | 智能分组提交代码，按功能/模块划分 |
| `skill-creator` | 创建新的 Skill 模板 |
| `frontend-design` | 前端设计辅助 |
| `docker-helper` | Docker 相关操作辅助 |
| `xlsx` | Excel (.xlsx) 文件处理 |
| `docx` | Word (.docx) 文件处理 |
| `pptx` | PowerPoint (.pptx) 文件处理 |
| `pdf` | PDF 文件处理（表单提取、转图片等） |

## 安装

### 方式一：克隆后执行 (推荐)

```bash
git clone https://github.com/wh131462/claude-config.git
cd claude-config
./install.sh
```

### 方式二：一行命令远程安装

```bash
curl -fsSL https://raw.githubusercontent.com/wh131462/claude-config/master/install.sh | bash
```

脚本会自动下载到临时目录后以本地模式重新执行，支持完整的交互式选择。

### 方式三：Node 版本

```bash
git clone https://github.com/wh131462/claude-config.git
cd claude-config
node install.js
```

## 参数说明

Bash 和 Node 版本支持相同的参数：

| 参数 | 说明 | 默认 |
|------|------|------|
| `--project` | 安装到当前项目 `./.claude/` | **默认** |
| `--global` | 安装到用户全局 `~/.claude/` | - |
| `--target <path>` | 安装到指定目录 | - |
| `--all` | 安装所有 skills，跳过交互选择 | - |
| `--force` | 已存在文件直接覆盖，不备份 | 备份后覆盖 |
| `--no-claude-md` | 不安装 CLAUDE.md | - |

## 示例

```bash
# 交互式安装到当前项目 (默认)
./install.sh

# 全部 skills 安装到全局
./install.sh --global --all

# 只安装 skills，不安装 CLAUDE.md
./install.sh --no-claude-md

# 强制覆盖已有文件，不备份
./install.sh --force --all

# Node 版本等价操作
node install.js --global --all
```

## 冲突处理

默认行为：当目标位置已存在同名文件/目录时，脚本会先将旧文件备份为 `xxx.bak.<时间戳>`，再写入新内容。

使用 `--force` 可跳过备份，直接覆盖。

## 目录结构

```
claude-config/
├── CLAUDE.md              # Claude Code 核心规则
├── install.sh             # Bash 安装脚本
├── install.js             # Node 安装脚本
├── README.md
└── .claude/
    └── skills/
        ├── smart-commit/
        ├── skill-creator/
        ├── frontend-design/
        ├── docker-helper/
        ├── xlsx/
        ├── docx/
        ├── pptx/
        └── pdf/
```

## License

MIT
