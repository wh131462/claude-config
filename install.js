#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
const readline = require("readline");

const REPO_PATH = "wh131462/claude-config";
const REPO_MIRRORS = [
  `https://github.com/${REPO_PATH}.git`,
  `https://gh-proxy.com/https://github.com/${REPO_PATH}.git`,
  `https://ghproxy.net/https://github.com/${REPO_PATH}.git`,
  `https://gitclone.com/github.com/${REPO_PATH}.git`,
];
const CLONE_TIMEOUT = 60;

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

function safeCopy(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function safeCopyDir(src, dest) {
  rmDirSync(dest);
  copyDirSync(src, dest);
}

// ---------- clone with timeout ----------
function cloneWithTimeout(url, dest, timeoutSec) {
  const timeoutCmd = process.platform === "darwin" ? "gtimeout" : "timeout";
  let hasTimeout = false;
  try {
    execSync(`command -v ${timeoutCmd}`, { stdio: "ignore" });
    hasTimeout = true;
  } catch {}
  if (!hasTimeout && process.platform === "darwin") {
    try {
      execSync("command -v timeout", { stdio: "ignore" });
      hasTimeout = true;
    } catch {}
  }

  const gitEnv = { ...process.env, GIT_TERMINAL_PROMPT: "0" };
  const cmd = hasTimeout
    ? `${timeoutCmd} ${timeoutSec} git clone --depth 1 "${url}" "${dest}"`
    : `git clone --depth 1 "${url}" "${dest}"`;
  execSync(cmd, { stdio: "ignore", env: gitEnv });
}

// ---------- detect source ----------
function detectSource(scriptDir) {
  const skillsDir = path.join(scriptDir, ".claude", "skills");
  if (fs.existsSync(skillsDir)) {
    return { sourceDir: scriptDir, cleanup: false };
  }
  info("未检测到本地 skill 文件，尝试从远程克隆...");
  const tmpDir = fs.mkdtempSync(path.join(require("os").tmpdir(), "claude-config-"));
  for (const repoUrl of REPO_MIRRORS) {
    info(`尝试镜像: ${repoUrl}`);
    try {
      rmDirSync(tmpDir);
      fs.mkdirSync(tmpDir, { recursive: true });
      cloneWithTimeout(repoUrl, tmpDir, CLONE_TIMEOUT);
      ok(`克隆成功: ${repoUrl}`);
      return { sourceDir: tmpDir, cleanup: true };
    } catch {
      warn("镜像不可用，切换下一个...");
    }
  }
  rmDirSync(tmpDir);
  err("所有镜像源均克隆失败，请检查网络或手动克隆后再执行");
  process.exit(1);
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
  return new Promise((resolve) => {
    const items = [{ name: "All", desc: "全选所有 skills" }, ...skills];
    const selected = new Array(items.length).fill(false);
    let cursor = 0;

    const draw = () => {
      console.log(`\n${c.bold("可用的 Skills:")}\n`);
      console.log(c.yellow("  [↑/↓] 移动光标  [空格] 切换选中  [回车] 确认\n"));
      items.forEach((item, i) => {
        const check = selected[i] ? c.green("◉") : "◯";
        const arrow = cursor === i ? c.cyan("→") : " ";
        const name = item.name.padEnd(20);
        console.log(`  ${arrow} ${check} ${name} ${item.desc}`);
      });
    };

    const clearLines = (n) => {
      for (let i = 0; i < n; i++) {
        process.stdout.write("\x1b[1A\x1b[2K");
      }
    };

    const redraw = () => {
      clearLines(items.length + 4);
      draw();
    };

    draw();

    readline.emitKeypressEvents(process.stdin);
    if (process.stdin.isTTY) {
      process.stdin.setRawMode(true);
    }

    const onKeypress = (str, key) => {
      if (key.name === "up") {
        cursor = cursor > 0 ? cursor - 1 : items.length - 1;
        redraw();
      } else if (key.name === "down") {
        cursor = (cursor + 1) % items.length;
        redraw();
      } else if (key.name === "space") {
        if (cursor === 0) {
          const allSelected = !selected[0];
          selected.fill(allSelected);
        } else {
          selected[cursor] = !selected[cursor];
          selected[0] = selected.slice(1).every((s) => s);
        }
        redraw();
      } else if (key.name === "return") {
        process.stdin.setRawMode(false);
        process.stdin.removeListener("keypress", onKeypress);
        process.stdin.pause();

        const result = [];
        if (selected[0]) {
          result.push(...skills.map((s) => s.name));
        } else {
          for (let i = 1; i < items.length; i++) {
            if (selected[i]) result.push(skills[i - 1].name);
          }
        }

        if (result.length === 0) {
          console.log("");
          err("未选择任何 skill");
          process.exit(1);
        }

        console.log("");
        resolve(result);
      } else if (key.ctrl && key.name === "c") {
        process.stdin.setRawMode(false);
        process.exit(0);
      }
    };

    process.stdin.on("keypress", onKeypress);
  });
}

// ---------- parse args ----------
function parseArgs(argv) {
  const opts = {
    mode: "project",
    modeExplicit: false,
    all: false,
    yes: false,
    installClaudeMd: true,
    targetDir: "",
  };
  let i = 0;
  while (i < argv.length) {
    switch (argv[i]) {
      case "--global":
        opts.mode = "global";
        opts.modeExplicit = true;
        break;
      case "--project":
        opts.mode = "project";
        opts.modeExplicit = true;
        break;
      case "--target":
        opts.mode = "custom";
        opts.modeExplicit = true;
        opts.targetDir = argv[++i];
        break;
      case "--all":
        opts.all = true;
        opts.yes = true;
        break;
      case "--yes":
      case "-y":
        opts.yes = true;
        break;
      case "--no-claude-md":
        opts.installClaudeMd = false;
        break;
      case "--force":
        opts.yes = true;
        break; // 兼容旧参数
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
  --all             安装所有 skills，跳过交互选择 (隐含 --yes)
  --yes, -y         跳过覆盖确认，直接覆盖已存在的文件
  --no-claude-md    不安装 CLAUDE.md
  --help            显示此帮助信息

注意: 已存在的文件/目录会被直接覆盖，不会备份。
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

// ---------- interactive mode selection ----------
async function interactiveMode(opts) {
  const home = require("os").homedir();
  console.log(`\n${c.bold("请选择安装位置:")}\n`);
  console.log(`  ${c.cyan("1)")} 全局         ${path.join(home, ".claude")}/`);
  console.log(`  ${c.cyan("2)")} 当前项目     ${path.join(process.cwd(), ".claude")}/`);
  console.log(`  ${c.cyan("3)")} 自定义路径`);
  const choice = (await prompt("\n请输入编号 [默认 2]: ")) || "2";
  switch (choice) {
    case "1":
      opts.mode = "global";
      break;
    case "2":
      opts.mode = "project";
      break;
    case "3": {
      const dir = await prompt("请输入自定义路径: ");
      if (!dir) {
        err("自定义路径不能为空");
        process.exit(1);
      }
      opts.mode = "custom";
      opts.targetDir = dir;
      break;
    }
    default:
      err(`无效编号: ${choice}`);
      process.exit(1);
  }
}

// ---------- confirm overwrite ----------
async function confirmOverwrite(opts, claudeMdDest, destSkills, selectedSkills) {
  const conflicts = [];
  if (opts.installClaudeMd && fs.existsSync(claudeMdDest)) {
    conflicts.push(claudeMdDest);
  }
  for (const name of selectedSkills) {
    const p = path.join(destSkills, name);
    if (fs.existsSync(p)) conflicts.push(p);
  }

  if (conflicts.length === 0) return;
  if (opts.yes) return;

  console.log(`\n${c.yellow("以下文件/目录已存在，将被覆盖:")}`);
  for (const p of conflicts) console.log(`  - ${p}`);
  const ans = await prompt("\n是否继续? [y/N]: ");
  if (!/^(y|yes)$/i.test(ans)) {
    info("已取消安装");
    process.exit(0);
  }
}

// ---------- main ----------
async function main() {
  const args = process.argv.slice(2);
  const opts = parseArgs(args);

  if (!opts.modeExplicit && !opts.all) {
    await interactiveMode(opts);
  }

  const scriptDir = __dirname;
  const { sourceDir, cleanup } = detectSource(scriptDir);
  const { destDir, destSkills, claudeMdDest } = resolveDest(opts);

  console.log(`\n${c.bold("========== claude-config 安装 ==========")}\n`);
  info(`安装模式: ${opts.mode}`);
  info(`目标目录: ${destDir}\n`);

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

  await confirmOverwrite(opts, claudeMdDest, destSkills, selected);

  // CLAUDE.md
  const claudeMdSrc = path.join(sourceDir, "CLAUDE.md");
  if (opts.installClaudeMd && fs.existsSync(claudeMdSrc)) {
    safeCopy(claudeMdSrc, claudeMdDest);
    ok(`CLAUDE.md -> ${claudeMdDest}`);
  }

  fs.mkdirSync(destSkills, { recursive: true });

  for (const name of selected) {
    const src = path.join(sourceDir, ".claude", "skills", name);
    const dest = path.join(destSkills, name);
    safeCopyDir(src, dest);
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
