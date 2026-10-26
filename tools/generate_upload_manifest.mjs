#!/usr/bin/env node
/**
 * Build a single Markdown document containing every uploadable file with its
 * repository-relative path and full contents. Useful for manual GitHub web
 * uploads and code review.
 *
 * Usage:
 *   node tools/generate_upload_manifest.mjs [sourceDir] [outputFile]
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(here, "..");
const sourceRoot = path.resolve(projectRoot, process.argv[2] || ".github-upload/BeautifulHumans");
const outputFile = path.resolve(projectRoot, process.argv[3] || "GITHUB_UPLOAD.md");

const ignoredNames = new Set([
  ".git",
  "node_modules",
  ".deps",
  ".testhome",
  ".tmp",
  "test-output.txt",
]);

function walk(directory, files = []) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (ignoredNames.has(entry.name)) continue;
    if (entry.name.endsWith(".log")) continue;
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      walk(absolute, files);
    } else if (entry.isFile()) {
      files.push(absolute);
    }
  }
  return files;
}

function languageFor(file) {
  const extension = path.extname(file).toLowerCase();
  if (extension === ".lua") return "lua";
  if (extension === ".json") return "json";
  if (extension === ".yml" || extension === ".yaml") return "yaml";
  if (extension === ".md") return "markdown";
  if (extension === ".ps1") return "powershell";
  if (extension === ".mjs" || extension === ".js") return "javascript";
  return "text";
}

if (!fs.existsSync(sourceRoot)) {
  console.error(`Source directory not found: ${sourceRoot}`);
  process.exit(1);
}

const files = walk(sourceRoot).sort((left, right) => {
  return relative(left).localeCompare(relative(right));
});

function relative(file) {
  return path.relative(sourceRoot, file).replace(/\\/g, "/");
}

const lines = [];
lines.push("# Beautiful Humans — файлы для загрузки на GitHub");
lines.push("");
lines.push("Этот документ содержит все файлы репозитория, которые нужно загрузить");
lines.push("через веб-интерфейс GitHub. Пути указаны **от корня репозитория**.");
lines.push("");
lines.push(`Всего файлов: **${files.length}**`);
lines.push("");
lines.push("## Как загрузить через сайт");
lines.push("");
lines.push("1. Создайте пустой репозиторий на GitHub без README, .gitignore и лицензии.");
lines.push("2. Откройте `Add file` → `Upload files`.");
lines.push("3. Для каждого файла ниже создайте путь через `Create new file`, если");
lines.push("   браузер не сохраняет вложенные каталоги при перетаскивании.");
lines.push("4. Вставьте код в поле содержимого и закоммитьте.");
lines.push("5. Файл `.github/workflows/validate.yml` создаётся по тому же принципу:");
lines.push("   GitHub сам создаст каталоги `.github/workflows`.");
lines.push("");
lines.push("Если браузер поддерживает перетаскивание папок, проще распаковать");
lines.push("`BeautifulHumans-upload.zip` и перетащить папку `BeautifulHumans`");
lines.push("в окно `Upload files` — структура каталогов сохранится.");
lines.push("");
lines.push("## Состав");
lines.push("");
for (const file of files) {
  lines.push(`- \`${relative(file)}\``);
}
lines.push("");
lines.push("---");
lines.push("");

for (const file of files) {
  const fileRelative = relative(file);
  const content = fs.readFileSync(file, "utf8");
  const language = languageFor(file);
  lines.push(`## \`${fileRelative}\``);
  lines.push("");
  lines.push(`\`\`\`\`${language}`);
  lines.push(content.replace(/\s+$/, ""));
  lines.push("````");
  lines.push("");
}

fs.writeFileSync(outputFile, lines.join("\n") + "\n", "utf8");
console.log(`Wrote ${outputFile}`);
console.log(`Files: ${files.length}`);
