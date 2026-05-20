# Installation Guide — Second Brain

> Этот документ нужен один раз. После установки работай через UI.

Выбери свою платформу:
- [Windows 11](#windows-11)
- [macOS (Apple Silicon)](#macos-apple-silicon)

---

## Windows 11

### Требования

- Windows 11 (22H2+)
- 16 GB RAM рекомендуется (минимум 8 GB)
- Python 3.10+ — [python.org](https://www.python.org/downloads/) или `winget install Python.Python.3.12`
- Git — [git-scm.com](https://git-scm.com/download/win) или `winget install Git.Git`
- GitHub аккаунт — для синхронизации knowledge base

> Все команды выполняются в **Git Bash** (устанавливается вместе с Git для Windows). PowerShell и CMD не поддерживаются.

---

### Шаг 1 — Установка зависимостей

```bash
# Node.js (v18+)
winget install OpenJS.NodeJS.LTS

# Pandoc — конвертация документов
winget install JohnMacFarlane.Pandoc

# Tesseract OCR — распознавание текста на сканах
winget install UB-Mannheim.TesseractOCR

# ImageMagick
winget install ImageMagick.ImageMagick

# jq — обработка JSON в скриптах
winget install jqlang.jq

# Ollama — локальные LLM
winget install Ollama.Ollama
```

> После установки **перезапусти Git Bash** чтобы новые пути подхватились.

#### poppler (для pdftotext)

Скачай готовую сборку: [poppler-windows releases](https://github.com/oschwartz10612/poppler-windows/releases)

Распакуй в `C:\poppler\` и добавь в PATH:

```bash
# В Git Bash добавь в ~/.bashrc:
export PATH="$PATH:/c/poppler/Library/bin"
source ~/.bashrc
```

Проверка:
```bash
pdftotext -v
```

#### Проверка всех зависимостей

```bash
node --version && python --version && pandoc --version | head -1 && tesseract --version 2>&1 | head -1 && jq --version && ollama --version
```

---

### Шаг 2 — Языковая модель

```bash
# Запускаем Ollama (или через системный трей после winget-установки)
ollama serve &
```

| Модель | Размер | Качество | Скорость |
|--------|--------|----------|----------|
| `llama3.1:8b` | 4.7 GB | хорошее | быстро |
| `qwen2.5:7b` | 4.4 GB | отлично (кириллица) | быстро |
| `qwen2.5:14b` | 9 GB | лучше | средне |
| `gemma3:12b` | 8 GB | лучше | средне |

**Рекомендация для Windows с 16 GB:** `qwen2.5:7b` — лучшая поддержка русского языка.

```bash
ollama pull qwen2.5:7b
# Проверка:
ollama run qwen2.5:7b "Привет, скажи OK"
```

---

### Шаг 3 — Клонирование репозитория

```bash
cd ~/projects   # или выбери любую папку

git clone https://github.com/galeonad-analytics/arch-win-second-brain.git second-brain
cd second-brain
```

---

### Шаг 4 — Настройка

```bash
# Создаём структуру папок
mkdir -p raw knowledge/projects logs

# Создаём .env (опционально — только если используешь Claude API)
cat > .env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_MODEL=claude-sonnet-4-6
EOF
```

---

### Шаг 5 — Запуск UI

```bash
node server.js
```

Открой в браузере: **http://localhost:3030**

Для автозапуска добавь алиас в `~/.bashrc`:

```bash
echo 'alias brain="cd ~/projects/second-brain && node server.js"' >> ~/.bashrc
source ~/.bashrc
```

Теперь достаточно написать `brain` в Git Bash.

---

### Шаг 6 — Настройка моделей в UI

Открой **⚙ Настройки** → выбери Ollama модель из списка установленных → сохрани.

Для Claude API: введи ключ и выбери модель. Ключ сохраняется в `.env` локально.

---

### Решение проблем (Windows)

**`python3` не найден:**
На Windows `python3` — стаб Microsoft Store. Система автоматически использует `python`. Убедись что Python добавлен в PATH при установке (галочка "Add Python to PATH").

**Ollama не запускается:**
```bash
# Проверь что сервис запущен:
curl http://localhost:11434/api/version
# Или запусти вручную:
ollama serve &
```

**PDF не конвертируется:**
Убедись что `pdftotext` доступен: `pdftotext -v`. Если нет — проверь PATH для poppler.

**Файлы с кириллицей в имени не грузятся:**
Убедись что Git Bash запущен с UTF-8 локалью. Добавь в `~/.bashrc`:
```bash
export LANG=ru_RU.UTF-8
export PYTHONUTF8=1
```

**Сервер не стартует:**
```bash
node --version  # нужен v18+
# Порт занят?
netstat -ano | findstr :3030
```

---

## macOS (Apple Silicon)

### Требования

- macOS с Apple Silicon (M1/M2/M3) — рекомендуется 16GB+ unified memory
- Homebrew — если нет: `https://brew.sh`
- GitHub аккаунт — для синхронизации knowledge base

---

### Шаг 1 — Установка зависимостей

```bash
brew install node pandoc tesseract imagemagick ollama jq gh poppler

# Claude Code CLI
npm install -g @anthropic-ai/claude-code

# Obsidian (UI для базы знаний)
brew install --cask obsidian
```

Проверка:
```bash
node --version && pandoc --version | head -1 && tesseract --version 2>&1 | head -1 && ollama --version
```

---

### Шаг 2 — Языковая модель

```bash
ollama serve &
```

| Модель | Размер | Контекст | Качество | Скорость |
|--------|--------|----------|----------|----------|
| `llama3.1:8b` | 4.7 GB | 8K | хорошее | быстро |
| `gemma3:12b` | 8 GB | 128K | лучше | средне |
| `qwen2.5:14b` | 9 GB | 128K | отлично (русский) | медленнее |

**Рекомендация для M3 Pro 18GB:** `gemma3:12b` — оптимальный баланс.

```bash
ollama pull gemma3:12b
ollama run gemma3:12b "Привет, скажи OK"
```

---

### Шаг 3 — Создание репозитория

```bash
gh auth login

mkdir -p ~/projects/second-brain/{raw/inbox,knowledge/{projects,stakeholders,risks,decisions,patterns},references,scripts,templates,ui}
cd ~/projects/second-brain

git init
echo "raw/" > .gitignore
echo ".obsidian/" >> .gitignore
echo ".env" >> .gitignore
git add .gitignore
git commit -m "init: second-brain vault"
gh repo create second-brain --private --source=. --remote=origin --push
```

---

### Шаг 4 — Настройка Obsidian

1. Открой Obsidian
2. **Open folder as vault** → выбери `~/projects/second-brain`
3. Settings (⌘,) → Files & Links:
   - New link format → `Shortest path when possible`
   - Use Wikilinks → включить
4. Core plugins → включить: Backlinks, Graph view, Tags view

---

### Шаг 5 — Настройка VS Code

```bash
code --install-extension anthropic.claude-code
code ~/projects/second-brain
```

---

### Шаг 6 — Запуск UI

```bash
cd ~/projects/second-brain
node server.js
```

Открой: **http://localhost:3030**

Алиас для автозапуска:
```bash
echo 'alias brain="cd ~/projects/second-brain && node server.js"' >> ~/.zshrc
source ~/.zshrc
```

---

### Шаг 7 — Настройка моделей в UI

Открой **⚙ Настройки** → Ollama модель → выбери из списка → сохрани.

**Claude API (опционально):**
1. Зарегистрируйся на **https://console.anthropic.com**
2. Создай ключ: Settings → API Keys → Create Key
3. Пополни баланс (минимум $5)
4. **⚙ Настройки** в UI → введи ключ → сохрани

Ключ хранится в `.env` локально.

---

### Шаг 8 — Шаблоны артефактов

В папку `templates/` положи шаблоны в формате `.md`:

| Файл | Артефакт |
|------|---------|
| `HLD.md` | High Level Design |
| `HLIS.md` | High Level Integration Specification |
| `AN-Pre-Analysis.md` | Architectural Note Pre-Analysis |
| `AN-Post-Analysis.md` | Architectural Note Post-Analysis |
| `SPFA.md` | Software Product Full Assessment |
| `BRD.md` | Business Requirements Document |

---

### Шаг 9 — Скиллы (опционально)

**Из PDF книги:**
```bash
./scripts/process_book.sh ~/Downloads/clean-architecture.pdf clean-architecture
```

**Из базы знаний проекта:**
```bash
./scripts/create_skill_from_knowledge.sh ARCH-123
```

---

### Решение проблем (macOS)

**Ollama не запускается:**
```bash
ollama serve &
curl http://localhost:11434/api/version
```

**Сервер не стартует:**
```bash
node --version  # нужен v18+
lsof -i :3030   # порт занят?
```

**PDF не читается:**
Скопируй текст вручную → сохрани как `.md` → загрузи через **⚠ Пропущенные файлы → ⇪ Заменить**

**Claude API ошибка:**
Проверь баланс: https://console.anthropic.com/settings/billing

---

## Структура проекта

```
second-brain/
├── raw/                   ← конвертированные документы (не в git)
│   └── ARCH-123/
├── knowledge/             ← база знаний (в git)
│   └── projects/ARCH-123/
│       ├── business-context.md
│       ├── requirements.md
│       ├── architecture.md
│       ├── adrs.md
│       ├── risks.md
│       ├── open-questions.md
│       └── stakeholders.md
├── templates/             ← шаблоны артефактов
├── skills/                ← доменные скиллы (в git)
├── scripts/
│   ├── ingest.sh                        ← конвертация документов
│   ├── process.sh                       ← обработка через Ollama
│   ├── process_book.sh                  ← создание скилла из PDF книги
│   └── create_skill_from_knowledge.sh   ← создание скилла из базы знаний
├── server.js              ← Node.js сервер (порт 3030)
├── CLAUDE.md              ← системный промпт (встроенный скилл)
├── .env                   ← API ключи (не в git)
└── .gitignore
```

---

## Поддерживаемые форматы файлов

| Формат | Конвертация | Примечание |
|--------|------------|------------|
| `.pdf` | pandoc → md, fallback OCR | Сканы через tesseract |
| `.docx`, `.doc` | pandoc → md | |
| `.pptx`, `.ppt` | pandoc → md | |
| `.xlsx`, `.xls`, `.csv` | pandoc → md | |
| `.epub`, `.fb2` | pandoc → md | Электронные книги |
| `.md`, `.txt`, `.log` | копирование | |
| `.png`, `.jpg`, `.jpeg` | tesseract OCR | |
| `.yaml`, `.yml` | как code block | |
| `.sql` | как code block | |
| `.puml`, `.plantuml` | как code block | |
| `.drawio` | как XML | компоненты и связи |
| `.bpmn` | как XML | процессы и роли |
| `.html`, `.htm` | pandoc → md | |
