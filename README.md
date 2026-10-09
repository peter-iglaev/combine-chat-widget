# ChatBar

A macOS menu bar app that shows one searchable list of your AI chats from **Claude**, **Claude Code**, **Cowork**, **ChatGPT**, **ChatGPT Work** and **Codex**. Press the hotkey (default **⌘Y**), type a few letters, hit **Enter**, and the chat opens in its desktop app.

The list is built from the apps' local data only. ChatBar makes no network requests.

## Install

Run in Terminal (Apple Silicon only):

```bash
curl -fsSL https://raw.githubusercontent.com/peter-iglaev/combine-chat-widget/main/install.sh | bash
```

The script downloads the latest DMG from [Releases](../../releases), verifies its SHA-256, installs ChatBar into `/Applications` and launches it. Run the same command to update.

A 💬 icon appears in the menu bar. Press **⌘Y**.

> **Why a script and not just the DMG?** ChatBar is not signed with an Apple Developer ID, so macOS rejects it when it comes from a browser download (Gatekeeper quarantine): the app won't launch normally and is hidden from Spotlight. Files fetched with `curl` are not quarantined, so the script install works out of the box.

## Usage

| Key | Action |
|---|---|
| ⌘Y (configurable) | Show / hide the panel |
| Type | Filter by title or source (e.g. `code deploy`) |
| ↑ ↓ | Move selection |
| Enter | Open the chat in its app |
| Esc | Close |

### Settings

Menu bar icon → **Настройки…** (Settings):

- **Hotkey**: click the shortcut button and press a new combination (needs ⌘, ⌥ or ⌃). **Сбросить** restores ⌘Y.
- **Launch at login** toggle.
- **ChatGPT**: shows whether ChatGPT runs with the debugging port and lets you (re)launch it with the port (see below).

## Sources

| Type | Where the list comes from | How it opens |
|---|---|---|
| Codex, ChatGPT Work | `~/.codex/state_5.sqlite` | `codex://threads/<id>` in ChatGPT.app |
| Claude Code (local) | `~/Library/Application Support/Claude/claude-code-sessions/**/local_*.json` | `claude://code/continue?session=…` |
| Cowork (local) | `…/Claude/local-agent-mode-sessions/**/local_*.json` | `claude://claude.ai/local_sessions/…` |
| Claude chats, cloud Code/Cowork | IndexedDB blobs of `claude-conversation-store` | `claude://claude.ai/chat/…`, `claude://code/cse_…`, `claude://claude.ai/cowork/cse_…` |
| ChatGPT chats | Live ChatGPT sidebar via the debugging port, falling back to the `codex.chatgpt-conversations` Local Storage cache | Debugging port: navigate the ChatGPT window to `/c/<id>` |

## ChatGPT and the debugging port

ChatGPT.app has no deep link for regular chats (only for Codex and Work threads), and it keeps the current chat list in memory only. To open ChatGPT chats by id and see the up-to-date list, ChatGPT.app must run with a local debugging port (`127.0.0.1:9333`).

- **Settings → ChatGPT → Перезапустить ChatGPT с портом**, or the same item in the menu bar menu, quits ChatGPT and relaunches it with the port. Running Codex tasks in ChatGPT are interrupted.
- When you open a ChatGPT chat while the port is off, ChatBar offers the relaunch.
- If you start ChatGPT normally (Dock, Spotlight), Codex and Work still open, but ChatGPT chats won't open by id and the list falls back to an older cache.

## Security

- **No network.** ChatBar and its collector only read local files and talk to `127.0.0.1`.
- **Debugging port exposure.** Verified on macOS 26:
  - ChatGPT binds the port to `127.0.0.1` only; connecting via the LAN address is refused.
  - Requests with a foreign `Host` header are rejected (DNS-rebinding protection).
  - WebSocket connections from any origin other than `http://127.0.0.1:9333` are rejected with 403, so web pages cannot attach.
  - **Remaining risk:** any program running on this Mac (under any user account) can connect to the port and control ChatGPT as you: read chats, send messages. If that is unacceptable, run ChatGPT normally; everything except ChatGPT chats keeps working.
- **Cache.** Chat titles are cached in `~/Library/Application Support/ChatBar/` with owner-only permissions (0600).
- **Dependencies.** The embedded CPython build is pinned and checked by SHA-256; Python packages are pinned to exact commits/versions in `collector/requirements.txt`.
- **Hotkey.** Registered via Carbon `RegisterEventHotKey`; no Accessibility permission required.

## Build from source

Requires Xcode (Swift 6) on Apple Silicon.

```bash
./scripts/build.sh      # build/ChatBar.app with embedded Python and collector
./scripts/make-dmg.sh   # build/ChatBar-<version>.dmg and .sha256
```

Pushing a `v*` tag runs `.github/workflows/release.yml`, which builds the DMG and attaches it to a GitHub release.

The collector can be run on its own:

```bash
APP=build/ChatBar.app/Contents/Resources
$APP/python/bin/python3 -I -B $APP/collector/chatbar.py list
```

## Limitations

- Claude cloud chats appear only if they were opened on this Mac.
- Without the debugging port, ChatGPT shows only what the app last cached (~40 recent + pinned).
- Everything relies on undocumented internals of Claude and ChatGPT; an app update can break a source.
- Apple Silicon only; the build is ad-hoc signed and not notarized (install via the script above).
