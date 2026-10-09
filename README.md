# ChatBar

Плашка по хоткею (по умолчанию ⌘Y) со списком чатов из Claude, Claude Code, Cowork, ChatGPT, ChatGPT Work и Codex. Enter открывает чат в его десктопном приложении. Список собирается только из локальных данных, без сети.

## Установка

```bash
./scripts/setup.sh   # Python-окружение для сборщика
./scripts/build.sh   # собирает build/ChatBar.app
open build/ChatBar.app
```

## Источники и способ открытия

| Тип | Откуда список | Как открывается |
|---|---|---|
| Codex, ChatGPT Work | `~/.codex/state_5.sqlite` | `codex://threads/<id>` в ChatGPT.app |
| Claude Code (локальный) | `Claude/claude-code-sessions/**/local_*.json` | `claude://code/continue?session=…` |
| Cowork (локальный) | `Claude/local-agent-mode-sessions/**/local_*.json` | `claude://claude.ai/local_sessions/…` |
| Чаты Claude, облачные Code/Cowork | blob-файлы IndexedDB `claude-conversation-store` | `claude://claude.ai/chat/…`, `claude://code/cse_…`, `claude://claude.ai/cowork/cse_…` |
| Чаты ChatGPT | Local Storage `codex.chatgpt-conversations` | CDP: `navigate-to-route` → `/c/<id>` |

## ChatGPT и отладочный порт

У ChatGPT.app нет deep link для обычных чатов (только для тредов Codex и Work), а актуальный список чатов он держит только в памяти. Поэтому для чатов ChatGPT нужен запуск с отладочным портом:

```bash
./scripts/start-chatgpt.sh
```

Скрипт запускает ChatGPT.app с `--remote-debugging-port=9333`. Если ChatGPT уже открыт без порта, скрипт закроет его и откроет заново. Через порт ChatBar читает список чатов из сайдбара и переводит окно на выбранный чат. Если открыть чат ChatGPT из плашки, когда порта нет, ChatBar сам предложит перезапуск.

Если запустить ChatGPT обычным способом (из Dock или Spotlight), порта не будет: Codex и Work откроются, а в списке чатов ChatGPT будут только старые записи из кэша.

## Безопасность

- **Сеть.** ChatBar и сборщик никуда не ходят. Всё читается из локальных файлов приложений и через локальный порт.
- **Отладочный порт.** Слушает только `127.0.0.1`, WebSocket принимает только origin `http://127.0.0.1:9333`, так что веб-страницы подключиться не могут. Но любая локальная программа на этом Маке может через порт управлять окном ChatGPT от твоего имени: читать чаты, писать сообщения. Если это неприемлемо, запускай ChatGPT обычным способом: всё, кроме обычных чатов ChatGPT, продолжит работать.
- **Кэш.** Названия чатов хранятся в `~/Library/Application Support/ChatBar/`, доступ только владельцу (600).
- **Зависимости.** Зафиксированы на конкретных коммитах в `collector/requirements.txt`.
- **Хоткей.** Регистрируется через Carbon `RegisterEventHotKey`, права Accessibility не нужны.

## Ограничения

- Облачные чаты Claude видны только те, что открывались на этом Маке.
- Чаты ChatGPT: последние ~40 и закреплённые (то, что кэширует приложение).
- Всё держится на внутренних форматах приложений: обновление Claude или ChatGPT может что-то сломать.
