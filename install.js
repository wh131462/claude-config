#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
const readline = require("readline");

const REPO_URL = "https://github.com/wh131462/claude-config.git";
const TIMESTAMP = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 14);

// ---------- colors ----------
const c = {
  red: (s) => `\x1b[31m${s}\x1b[0m`,
  green: (s) => `\x1b[32m${s}\x1b[0m`,
  yellow: (s) => `\x1b[33m${s}\x1b[0m`,
  cyan: (s) => `\x1b[36m${s}\x1b[0m`,
  bold: (s) => `\x1b[1m${s}\x1b[0m`,
};

const info = (msg) => console.log(`${c.cyan("[INFO]")}  ${msg}`);
const ok = (msg) => console.log(`${c.green("[OK]")}    ${msg}`);
const warn = (msg) => console.log(`${c.yellow("[WARN]")}  ${msg}`);
const err = (msg) => console.error(`${c.red("[ERR]")}   ${msg}`);

// ---------- helpers ----------
function copyFileSync(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function copyDirSync(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDirSync(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function rmDirSync(dir) {
  if (fs.existsSync(dir)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function safeCopy(src, dest, force) {
  if (fs.existsSync(dest)) {
    if (!force) {
      const bak = `${dest}.bak.${TIMESTAMP}`;
      fs.copyFileSync(dest, bak);
      warn(`已备份: ${path.basename(dest)} -> ${path.basename(bak)}`);
    }
    fs.copyFileSync(src, dest);
  } else {
    copyFileSync(src, dest);
  }
}

function safeCopyDir(src, dest, force) {
  if (fs.existsSync(dest)) {
    if (!force) {
      const bak = `${dest}.bak.${TIMESTAMP}`;
      copyDirSync(dest, bak);
      warn(`已备份: ${path.basename(dest)} -> ${path.basename(bak)}`);
    }
    rmDirSync(dest);
  }
  copyDirSync(src, dest);
}

// ---------- detect source ----------
function detectSource(scriptDir) {
  const skillsDir = path.join(scriptDir, ".claude", "skills");
  if (fs.existsSync(skillsDir)) {
    return { sourceDir: scriptDir, cleanup: false };
  }
  info("未检测到本地 skill 文件，正在从远程克隆...");
  const tmpDir = fs.mkdtempSync(path.join(require("os").tmpdir(), "claude-config-"));
  try {
    execSync(`git clone --depth 1 ${REPO_URL} "${tmpDir}"`, { stdio: "ignore" });
  } catch {
    err("克隆仓库失败，请检查网络或手动克隆后再执行");
    process.exit(1);
  }
  return { sourceDir: tmpDir, cleanup: true };
}

// ---------- list skills ----------
function listSkills(sourceDir) {
  const skillsDir = path.join(sourceDir, ".claude", "skills");
  if (!fs.existsSync(skillsDir)) return [];
  return fs
    .readdirSync(skillsDir, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => {
      const skillFile = path.join(skillsDir, d.name, "SKILL.md");
      let desc = "";
      if (fs.existsSync(skillFile)) {
        const content = fs.readFileSync(skillFile, "utf-8");
        const match = content.match(/^description:\s*(.+)$/m);
        if (match) desc = match[1].trim();
      }
      return { name: d.name, desc };
    });
}

// ---------- interactive selection ----------
function prompt(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

async function interactiveSelect(skills) {
  console.log(`\n${c.bold("可用的 Skills:")}\n`);
  skills.forEach((s, i) => {
    console.log(`  ${c.cyan(`${(i + 1).toString().padStart(2)})`)} ${s.name.padEnd(20)} ${s.desc}`);
  });

  const answer = await prompt("\n输入编号选择 (逗号分隔, a=全选, q=取消): ");

  if (answer === "q" || answer === "Q") {
    info("已取消安装");
    process.exit(0);
  }

  if (answer === "a" || answer === "A") {
    return skills.map((s) => s.name);
  }

  const selected = [];
  for (const part of answer.split(",")) {
    const idx = parseInt(part.trim(), 10);
    if (idx >= 1 && idx <= skills.length) {
      selected.push(skills[idx - 1].name);
    } else {
      warn(`无效编号: ${part.trim()}，已跳过`);
    }
  }

  if (selected.length === 0) {
    err("未选择任何 skill");
    process.exit(1);
  }
  return selected;
}

// ---------- parse args ----------
function parseArgs(argv) {
  const opts = {
    mode: "project",
    force: false,
    all: false,
    installClaudeMd: true,
    targetDir: "",
  };
  let i = 0;
  while (i < argv.length) {
    switch (argv[i]) {
      case "--global":
        opts.mode = "global";
        break;
      case "--project":
        opts.mode = "project";
        break;
      case "--target":
        opts.mode = "custom";
        opts.targetDir = argv[++i];
        break;
      case "--force":
        opts.force = true;
        break;
      case "--all":
        opts.all = true;
        break;
      case "--no-claude-md":
        opts.installClaudeMd = false;
        break;
      case "--help":
      case "-h":
        console.log(`
${c.bold("claude-config installer (Node)")}

用法:
  npx claude-config-install [选项]
  node install.js [选项]

选项:
  --global          安装到用户全局 (~/.claude/)
  --project         安装到当前项目 (./.claude/)  [默认]
  --target <path>   安装到指定目录
  --force           已存在文件时直接覆盖 (默认备份后覆盖)
  --all             安装所有 skills，跳过交互选择
  --no-claude-md    不安装 CLAUDE.md
  --help            显示此帮助信息
`);
        process.exit(0);
        break;
      default:
        err(`未知参数: ${argv[i]}`);
        process.exit(1);
    }
    i++;
  }
  return opts;
}

// ---------- resolve dest ----------
function resolveDest(opts) {
  const home = require("os").homedir();
  let destDir, claudeMdDest;

  switch (opts.mode) {
    case "global":
      destDir = path.join(home, ".claude");
      claudeMdDest = path.join(home, ".claude", "CLAUDE.md");
      break;
    case "project":
      destDir = path.join(process.cwd(), ".claude");
      claudeMdDest = path.join(process.cwd(), "CLAUDE.md");
      break;
    case "custom":
      destDir = opts.targetDir;
      claudeMdDest = path.join(opts.targetDir, "CLAUDE.md");
      break;
  }

  return { destDir, destSkills: path.join(destDir, "skills"), claudeMdDest };
}

// ---------- main ----------
async function main() {
  const args = process.argv.slice(2);
  const opts = parseArgs(args);
  const scriptDir = __dirname;
  const { sourceDir, cleanup } = detectSource(scriptDir);
  const { destDir, destSkills, claudeMdDest } = resolveDest(opts);

  console.log(`\n${c.bold("========== claude-config 安装 ==========")}\n`);
  info(`安装模式: ${opts.mode}`);
  info(`目标目录: ${destDir}\n`);

  // CLAUDE.md
  const claudeMdSrc = path.join(sourceDir, "CLAUDE.md");
  if (opts.installClaudeMd && fs.existsSync(claudeMdSrc)) {
    safeCopy(claudeMdSrc, claudeMdDest, opts.force);
    ok(`CLAUDE.md -> ${claudeMdDest}`);
  }

  // skills
  const skills = listSkills(sourceDir);
  if (skills.length === 0) {
    err("未找到可用的 skills");
    process.exit(1);
  }

  let selected;
  if (opts.all) {
    selected = skills.map((s) => s.name);
  } else {
    selected = await interactiveSelect(skills);
  }

  fs.mkdirSync(destSkills, { recursive: true });

  for (const name of selected) {
    const src = path.join(sourceDir, ".claude", "skills", name);
    const dest = path.join(destSkills, name);
    safeCopyDir(src, dest, opts.force);
    ok(`skill: ${name}`);
  }

  console.log(`\n${c.green(c.bold("安装完成!"))}`);
  let summary = `已安装 ${c.cyan(selected.length.toString())} 个 skills`;
  if (opts.installClaudeMd) summary += ` + ${c.cyan("CLAUDE.md")}`;
  console.log(summary + "\n");

  if (cleanup) rmDirSync(sourceDir);
}

main().catch((e) => {
  err(e.message);
  process.exit(1);
});
