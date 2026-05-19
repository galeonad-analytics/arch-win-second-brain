#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# process.sh v2 — оптимизированный: 1 запрос вместо 7, таймаут, фильтр мусора
# Использование: ./scripts/process.sh ARCH-123
# =============================================================================

# Загружаем .env если есть
if [[ -f "$(dirname "$0")/../.env" ]]; then
  set -a
  source "$(dirname "$0")/../.env"
  set +a
fi

JIRA="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_DIR="$(dirname "$SCRIPT_DIR")"
RAW_DIR="$BRAIN_DIR/raw"
KNOWLEDGE_DIR="$BRAIN_DIR/knowledge"
CLAUDE_MD="$BRAIN_DIR/CLAUDE.md"
MODEL="${OLLAMA_MODEL:-llama3.1:8b}"
OLLAMA_URL="http://localhost:11434/api/generate"
TIMEOUT=180        # секунд на один запрос

# --- Авто-определение MAX_CHARS по модели и ОЗУ ---
_get_ram_gb() {
  local ram=8
  case "$(uname -s)" in
    Linux)  ram=$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null) ;;
    Darwin) ram=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 8589934592) / 1073741824 )) ;;
    *)      # Windows / MSYS
      local b
      b=$(powershell.exe -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory" 2>/dev/null | tr -d '\r\n ')
      [[ "$b" =~ ^[0-9]+$ ]] && ram=$(( b / 1073741824 ))
      ;;
  esac
  echo "${ram:-8}"
}

_get_model_b() {
  local m; m="$(echo "$MODEL" | tr '[:upper:]' '[:lower:]')"
  if   [[ "$m" =~ 70b|72b ]]; then echo 70
  elif [[ "$m" =~ 34b|30b ]]; then echo 34
  elif [[ "$m" =~ 27b     ]]; then echo 27
  elif [[ "$m" =~ 12b|13b ]]; then echo 13
  elif [[ "$m" =~ 3b|4b   ]]; then echo 3
  else echo 8; fi
}

_auto_max_chars() {
  local ram b
  ram=$(_get_ram_gb); b=$(_get_model_b)
  if   (( b >= 70 )); then (( ram >= 64 )) && echo 24000 || echo 16000
  elif (( b >= 27 )); then
    if   (( ram >= 64 )); then echo 20000
    elif (( ram >= 32 )); then echo 14000
    elif (( ram >= 16 )); then echo 8000
    else echo 4000; fi
  elif (( b >= 12 )); then
    if   (( ram >= 32 )); then echo 14000
    elif (( ram >= 16 )); then echo 10000
    elif (( ram >= 8  )); then echo 6000
    else echo 4000; fi
  else
    if   (( ram >= 32 )); then echo 10000
    elif (( ram >= 16 )); then echo 7000
    elif (( ram >= 8  )); then echo 5000
    else echo 3000; fi
  fi
}

# Если передан из server.js — используем; иначе вычисляем
MAX_CHARS="${MAX_CHARS:-$(_auto_max_chars)}"
# num_ctx: chars + 2048 overhead, кратно 512
NUM_CTX=$(( (MAX_CHARS + 2048 + 511) / 512 * 512 ))

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

# --- лог-файл для постмортемов ---
LOG_DIR="$BRAIN_DIR/logs"
mkdir -p "$LOG_DIR"
RUN_TS="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="$LOG_DIR/process-${JIRA}-${RUN_TS}.log"

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

tee_log() {
  # пишет строку и в терминал, и в лог (без ANSI-цветов в файле)
  local msg="$*"
  local clean="${msg//$'\033'[*m/}"
  clean="$(printf '%s' "$clean" | sed 's/\x1b\[[0-9;]*m//g')"
  printf '[%s] %s\n' "$(_ts)" "$clean" >> "$LOG_FILE"
}

log()  { local m="${GREEN}[process]${NC} $*"; echo -e "$m"; tee_log "[OK]  $*"; }
info() { local m="${BLUE}[process]${NC} $*";  echo -e "$m"; tee_log "[INFO] $*"; }
warn() { local m="${YELLOW}[warn]${NC}    $*"; echo -e "$m"; tee_log "[WARN] $*"; }
err()  { local m="${RED}[error]${NC}   $*";  echo -e "$m" >&2; tee_log "[ERR]  $*"; }

if [[ -z "$JIRA" ]]; then
  err "Использование: $0 <JIRA-ID>"
  exit 1
fi

RAW_JIRA="$RAW_DIR/$JIRA"
KNOWLEDGE_JIRA="$KNOWLEDGE_DIR/projects/$JIRA"

[[ ! -d "$RAW_JIRA" ]] && { err "Папка не найдена: $RAW_JIRA"; exit 1; }
curl -s --max-time 5 "$OLLAMA_URL" > /dev/null 2>&1 || { err "Ollama не запущена. Запусти: ollama serve &"; exit 1; }
[[ ! -f "$CLAUDE_MD" ]] && { err "CLAUDE.md не найден"; exit 1; }

mkdir -p "$KNOWLEDGE_JIRA"
# Для локальных моделей используем короткий системный промпт вместо полного CLAUDE.md
SYSTEM_PROMPT="Ты извлекаешь знания из документов в структурированный JSON. Отвечай ТОЛЬКО валидным JSON без пояснений."
COUNT_OK=0; COUNT_SKIP=0; COUNT_ERR=0

log "Тикет: $JIRA | Модель: $MODEL | Лимит: ${MAX_CHARS} символов | Таймаут: ${TIMEOUT}с"
info "Лог: $LOG_FILE"
echo ""

# --- файлы без архитектурного смысла — пропускаем ---
is_noise() {
  local name
  name="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$name" in
    *zoom*|*git-setup*|*quick-start*|*howto*|\
    *project-info*|*project-structure*|\
    *index.md*) return 0 ;;
  esac
  return 1
}

mark_processed() {
  local tmp
  tmp="$(mktemp)"
  sed 's/^processed: false/processed: true/' "$1" > "$tmp" && mv "$tmp" "$1"
}

get_frontmatter() {
  grep "^${2}:" "$1" | head -1 | sed "s/^${2}: *//" | tr -d '"'
}

# --- один запрос → JSON со всеми измерениями ---
call_ollama_single() {
  local content="$1"
  local ref="$2"
  local doc_type="$3"

  local spfa_instruction=""
  [[ "$doc_type" == "spfa" ]] && spfa_instruction='
8. "spfa": массив SPFA оценок вендора (если есть): [{id, vendor, status, findings, tco, source}]'

  local prompt="Проанализируй текст документа и заполни JSON-структуру.
Каждый элемент массива ДОЛЖЕН быть объектом с полями как в примере ниже.
Если данных для категории нет — верни пустой массив [].
Используй только роли людей, не имена.

ПРИМЕР (заполни по аналогии с реальными данными из документа):
{
  \"business_context\": [{\"id\": \"BC-001\", \"title\": \"Название инициативы\", \"problem\": \"Какую проблему решает\", \"goals\": \"Цели\", \"source\": \"$ref\", \"tags\": \"#business-context\"}],
  \"requirements\": [{\"id\": \"BR-001\", \"title\": \"Название требования\", \"type\": \"Functional\", \"description\": \"Описание\", \"priority\": \"Must\", \"source\": \"$ref\", \"tags\": \"#requirement\"}],
  \"architecture\": [{\"id\": \"ARCH-001\", \"title\": \"Компонент или интеграция\", \"type\": \"Integration\", \"description\": \"Описание\", \"systems\": \"Система A, Система B\", \"protocol\": \"REST\", \"source\": \"$ref\", \"tags\": \"#architecture\"}],
  \"adrs\": [{\"id\": \"ADR-001\", \"title\": \"Решение\", \"status\": \"Accepted\", \"context\": \"Контекст\", \"decision\": \"Решение\", \"consequences\": \"Последствия\", \"source\": \"$ref\", \"tags\": \"#adr\"}],
  \"risks\": [{\"id\": \"R-001\", \"title\": \"Название риска\", \"category\": \"Technical\", \"impact\": \"High\", \"probability\": \"Medium\", \"mitigation\": \"Меры\", \"source\": \"$ref\", \"tags\": \"#risk\"}],
  \"open_questions\": [{\"id\": \"Q-001\", \"question\": \"Вопрос?\", \"context\": \"Контекст\", \"affects\": \"Architecture\", \"owner\": \"Роль\", \"urgency\": \"Normal\", \"source\": \"$ref\", \"tags\": \"#open-question\"}],
  \"stakeholders\": [{\"id\": \"S-001\", \"role\": \"Product Owner\", \"project\": \"$JIRA\", \"interests\": \"Интересы\", \"raci\": \"Accountable\", \"source\": \"$ref\", \"tags\": \"#stakeholder\"}]
}

ДОКУМЕНТ ($ref, тип: $doc_type):
$content"

  local payload
  payload="$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --arg prompt "$prompt" \
    --argjson num_ctx "$NUM_CTX" \
    '{model: $model, system: $system, prompt: $prompt, stream: true, format: "json", options: {temperature: 0.1, num_ctx: $num_ctx}}')"

  local full_response="" tok dots=0
  while IFS= read -r line; do
    tok="$(printf '%s' "$line" | jq -r '.response // empty' 2>/dev/null)"
    if [[ -n "$tok" ]]; then
      full_response+="$tok"
      (( ++dots % 30 == 0 )) && printf "·" >&2
    fi
  done < <(curl -s --max-time "$TIMEOUT" -X POST "$OLLAMA_URL" \
    -H "Content-Type: application/json" \
    -d "$payload")
  (( dots > 0 )) && printf "\n" >&2

  printf '%s' "$full_response"
}

# --- JSON → markdown файлы ---
json_to_files() {
  local json="$1"

  # вырезаем JSON если модель добавила текст вокруг
  json="$(echo "$json" | sed -n '/^{/,/^}/p' | head -200)"
  [[ -z "$json" ]] && return

  # функция записи секции
  write_section() {
    local key="$1" file="$2" header="$3"
    local items
    items="$(echo "$json" | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  items=d.get('$key',[])
  if not items: sys.exit(0)
  for i in items:
    print('## ' + i.get('id','?') + ' ' + (i.get('title') or i.get('role') or i.get('question','?')))
    for k,v in i.items():
      if k not in ('id','title','role','question') and v:
        print('- **' + k.capitalize() + '**: ' + str(v))
    print()
except: pass
" 2>/dev/null)"
    [[ -z "$items" ]] && return
    local target="$KNOWLEDGE_JIRA/$file"
    if [[ ! -f "$target" ]]; then
      printf "# %s — %s\n\n%s\n" "$header" "$JIRA" "$items" > "$target"
      log "Создан: $file"
    else
      printf "\n---\n\n%s\n" "$items" >> "$target"
      log "Обновлён: $file"
    fi
  }

  write_section "business_context"  "business-context.md"  "Бизнес-контекст"
  write_section "requirements"      "requirements.md"       "Требования"
  write_section "architecture"      "architecture.md"       "Архитектура решения"
  write_section "adrs"              "adrs.md"               "Architecture Decision Records"
  write_section "risks"             "risks.md"              "Риски"
  write_section "open_questions"    "open-questions.md"     "Открытые вопросы"
  write_section "stakeholders"      "stakeholders.md"       "Стейкхолдеры"
  write_section "spfa"              "spfa-assessment.md"    "SPFA Оценка вендора"
}

detect_doc_type() {
  local name
  name="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  echo "$name" | grep -qi "spfa\|feasibility\|vendor\|assessment" && echo "spfa" && return
  echo "$name" | grep -qi "hld\|high.level" && echo "hld" && return
  echo "$name" | grep -qi "bazaar\|справка\|an-" && echo "an" && return
  echo "generic"
}

# --- основной цикл ---
TOTAL="$(find "$RAW_JIRA" -name "*.md" -type f | wc -l | tr -d ' ')"
CURRENT=0

while IFS= read -r -d '' filepath; do
  filename="$(basename "$filepath")"
  ((CURRENT++))
  processed="$(get_frontmatter "$filepath" "processed")"

  if [[ "$processed" == "true" ]]; then
    info "[$CURRENT/$TOTAL] Пропускаю (обработан): $filename"
    ((COUNT_SKIP++))
    continue
  fi

  if is_noise "$filepath"; then
    info "[$CURRENT/$TOTAL] Пропускаю (не архитектурный): $filename"
    mark_processed "$filepath"
    ((COUNT_SKIP++))
    continue
  fi

  log "[$CURRENT/$TOTAL] Обрабатываю: $filename"

  content="$(awk '/^---/{found++; if(found==2){skip=0; next}} found<2{next} {print}' "$filepath" | head -c $MAX_CHARS)"

  if [[ -z "$(echo "$content" | tr -d '[:space:]')" ]]; then
    warn "Пустой контент — пропускаю"
    mark_processed "$filepath"
    ((COUNT_SKIP++))
    continue
  fi

  doc_type="$(detect_doc_type "$filepath")"
  ref="[[${filename%.md}]]"
  chars="$(printf '%s' "$content" | wc -c | tr -d ' ')"

  info "  → 1 запрос (тип: $doc_type, размер: ${chars} символов)..."
  tee_log "[START-MODEL] file=$filename doc_type=$doc_type chars=$chars model=$MODEL num_ctx=$NUM_CTX"

  t_start="$(date +%s)"
  response="$(call_ollama_single "$content" "$ref" "$doc_type")"
  t_end="$(date +%s)"
  elapsed=$(( t_end - t_start ))

  if [[ -z "$response" ]]; then
    warn "  Таймаут или пустой ответ (${elapsed}с) — пропускаю: $filename"
    tee_log "[TIMEOUT] file=$filename elapsed=${elapsed}s"
    ((COUNT_ERR++))
  else
    resp_len="${#response}"
    info "  ✓ Ответ получен за ${elapsed}с (${resp_len} символов)"
    tee_log "[END-MODEL] file=$filename elapsed=${elapsed}s response_len=${resp_len}"
    json_to_files "$response"
    ((COUNT_OK++))
  fi

  mark_processed "$filepath"
  echo ""

done < <(find "$RAW_JIRA" -name "*.md" -type f -print0)

echo ""
log "=== Готово ==="
echo -e "  ${GREEN}✓ Обработано:${NC}  $COUNT_OK"
echo -e "  ${YELLOW}⊘ Пропущено:${NC}   $COUNT_SKIP"
echo -e "  ${RED}✗ Таймауты:${NC}    $COUNT_ERR"
echo ""
log "База знаний: $KNOWLEDGE_JIRA"
ls "$KNOWLEDGE_JIRA/" 2>/dev/null | while read f; do echo "  - $f"; done
tee_log "[DONE] ok=$COUNT_OK skip=$COUNT_SKIP err=$COUNT_ERR"

if [[ "$COUNT_ERR" -eq 0 ]]; then
  rm -f "$LOG_FILE"
else
  log "Лог ошибок/таймаутов: $LOG_FILE"
fi
