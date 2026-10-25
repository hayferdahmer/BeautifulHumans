# Публикация Beautiful Humans на GitHub

Практическая инструкция для первого репозитория.  
**Корень репозитория:** папка `BeautifulHumans`, а не весь workspace
`deepseek-harness` (там лежат посторонние проекты).

---

## 1. Что коммитить

### Обязательно

```text
README.md
CHANGELOG.md
LICENSE
.gitignore
.gitattributes
docs/
src/
tests/
tools/
```

В `tools/` коммитятся только:

```text
tools/build.mjs
tools/validate.mjs
tools/run_tests.mjs
tools/package.json
```

### Для версии 0.1.0

Можно закоммитить `releases/` целиком:

```text
releases/BeautifulHumansCore/
releases/BHTestMod/
releases/BeautifulHumansCore-0.1.0.zip
releases/BHTestMod-0.1.0.zip
```

Это около 150 КБ. Плюс: пользователь может скачать репозиторий и сразу
установить мод без сборки. Минус: артефакты нужно пересобирать при каждом
изменении кода.

Для следующих версий лучше:

- не коммитить `releases/`;
- собирать мод в CI;
- прикреплять zip к GitHub Releases.

### Не коммитить

```text
tools/node_modules/
tools/.deps/
.testhome/
.tmp/
*.log
test-output.txt
server-console.txt
Zomboid/Saves/
```

Эти пути уже покрыты `.gitignore`, кроме `releases/` — его судьбу вы
выбираете сами.

### Проверить перед публикацией

1. В `docs/` не должно быть ваших личных путей и имён пользователя.
2. `LICENSE` должен быть реальной лицензией, а не `LICENSE PENDING`.
3. В репозитории не должно быть сохранений игры и логов.
4. `README.md` не должен ссылаться на файлы, которых нет в репозитории.
5. Секретов, токенов и паролей нет.

---

## 2. Создать репозиторий на GitHub

1. Откройте <https://github.com/new>.
2. Введите имя: `beautiful-humans` (или `BeautifulHumans`).
3. Описание:

   ```text
   Modular survival simulation platform for Project Zomboid Build 42
   ```

4. Выберите **Private** на время разработки. Публичным сделаете позже.
5. **Не включайте** `Add a README`, `Add .gitignore`, `Choose a license`:
   эти файлы уже есть локально, иначе будет конфликт.
6. Нажмите **Create repository**.
7. Скопируйте URL вида:

   ```text
   https://github.com/ВАШ_ЛОГИН/beautiful-humans.git
   ```

---

## 3. Установить Git

На Windows проще всего:

1. Скачать **Git for Windows**: <https://git-scm.com/download/win>
2. Установить с настройками по умолчанию.
3. Закрыть и заново открыть PowerShell.
4. Проверить:

   ```powershell
   git --version
   ```

Если не хотите работать с командной строкой, установите **GitHub Desktop**:
<https://desktop.github.com/>. Он включает Git и умеет авторизоваться в
GitHub через браузер.

### Важно про OneDrive

Сейчас проект находится в OneDrive. Синхронизация `.git` может приводить к
конфликтам, блокировкам файлов и повреждению индекса.

Варианты:

- приостановить синхронизацию OneDrive на время `git`-операций;
- исключить папку из синхронизации;
- держать рабочую копию вне OneDrive, например `C:\Dev\BeautifulHumans`.

---

## 4. Первый коммит через PowerShell

Откройте PowerShell и выполните команды по одной.

### 4.1. Перейти в корень проекта

```powershell
cd "C:\Users\hayfe\OneDrive\Документы\deepseek-harness\default-workspace\BeautifulHumans"
```

Путь замените на свой, если проект перенесён.

### 4.2. Настроить автора коммитов

```powershell
git config --global user.name "Ваше Имя"
git config --global user.email "you@example.com"
```

Если не хотите публиковать личный email, используйте GitHub noreply:

```text
12345678+username@users.noreply.github.com
```

### 4.3. Инициализировать репозиторий

```powershell
git init
git branch -M main
```

### 4.4. Проверить, что попадёт в коммит

```powershell
git add .
git status
```

В списке не должно быть `node_modules`, логов, `.testhome`, сохранений.
Если что-то лишнее попало:

```powershell
git restore --staged путь/к/файлу
```

### 4.5. Сделать первый коммит

```powershell
git commit -m "Initial commit: Beautiful Humans 0.1.0 foundation"
```

### 4.6. Привязать удалённый репозиторий

```powershell
git remote add origin https://github.com/ВАШ_ЛОГИН/beautiful-humans.git
git remote -v
```

### 4.7. Отправить на GitHub

```powershell
git push -u origin main
```

При первом push Git Credential Manager откроет браузер. Войдите в GitHub.
Пароль от аккаунта в качестве пароля Git **не используется**.

---

## 5. Вариант через GitHub Desktop

1. Установить GitHub Desktop.
2. `File` → `Add local repository`.
3. Выбрать папку `BeautifulHumans`.
4. Если Git-репозитория ещё нет, GitHub Desktop предложит создать его.
5. Ввести commit message.
6. Нажать `Commit to main`.
7. Нажать `Publish repository`.
8. Выбрать `Keep this code private` или снять галочку для публичного репозитория.

Это самый простой путь, если не хочется вводить команды.

---

## 6. Проверить репозиторий

На странице GitHub должны быть:

- `README.md` с описанием;
- `docs/`;
- `src/`;
- `tests/`;
- `tools/`;
- `.github/workflows/validate.yml`;
- `releases/` (если решили коммитить).

Проверьте, что GitHub не показывает:

- `node_modules`;
- `*.log`;
- `test-output.txt`;
- `.testhome`;
- большие zip без необходимости.

---

## 7. Теги и релизы

После стабильного коммита:

```powershell
git tag -a v0.1.0 -m "Beautiful Humans 0.1.0 - foundation"
git push origin v0.1.0
```

На GitHub:

1. `Releases` → `Draft a new release`.
2. Выбрать тег `v0.1.0`.
3. Заголовок: `Beautiful Humans 0.1.0 — foundation`.
4. Описание: кратко, что вошло и что не вошло.
5. Прикрепить:

   ```text
   BeautifulHumansCore-0.1.0.zip
   BHTestMod-0.1.0.zip
   ```

6. Опубликовать.

Даже если zip закоммичены, в Release их удобнее скачивать.

---

## 8. CI

Файл `.github/workflows/validate.yml` уже добавлен. Он на каждый push/PR:

1. ставит Node.js;
2. устанавливает `fengari`;
3. запускает `node tools/run_tests.mjs`;
4. собирает релиз;
5. запускает `node tools/validate.mjs`.

После первого push откройте вкладку **Actions** и убедитесь, что workflow
зелёный. Если нет — читайте лог шага, а не только summary.

---

## 9. Защита основной ветки

Для репозитория с несколькими участниками:

1. `Settings` → `Branches`.
2. `Add branch protection rule`.
3. Branch name pattern: `main`.
4. Включить:
   - `Require a pull request before merging`;
   - `Require status checks to pass` → выбрать `validate`;
   - `Do not allow bypassing the above settings` (по желанию).
5. Сохранить.

Для первого релиза можно не включать, чтобы не блокировать себя.

---

## 10. Частые ошибки

### `git: command not found`

Git не установлен или PowerShell не перезапущен после установки.

### `remote origin already exists`

```powershell
git remote set-url origin https://github.com/ВАШ_ЛОГИН/beautiful-humans.git
```

### `failed to push some refs`

Сначала подтянуть изменения:

```powershell
git pull --rebase origin main
git push -u origin main
```

### `src refspec main does not match any`

Вы ещё не сделали коммит. Выполните:

```powershell
git add .
git commit -m "Initial commit"
```

### GitHub просит пароль и не принимает его

Используйте Git Credential Manager, GitHub Desktop или Personal Access Token.
Пароль аккаунта для HTTPS Git не подходит.

### Слишком большой файл

Не добавляйте в Git сохранения, логи, видео и большие ассеты. Для ассетов
позже можно подключить Git LFS.

---

## 11. Рекомендуемый порядок

1. Выбрать лицензию.
2. Приостановить OneDrive или перенести проект.
3. Установить Git.
4. Создать пустой репозиторий на GitHub.
5. `git init` → `git add .` → `git commit`.
6. `git remote add origin ...` → `git push`.
7. Проверить Actions.
8. Создать тег `v0.1.0` и Release с zip.
9. Только после этого делать репозиторий публичным.

---

## 12. Что не обещать в публичном README

Не писать «полная симуляция выживания» или «1.0.0», пока не закрыты:

- реальный save/load персонажа;
- мультиплеерная авторизация лечения;
- NPC/экономика;
- профилирование;
- совместимость с другими модами.

Текущий корректный статус: **0.1.0 — фундамент платформы**.
