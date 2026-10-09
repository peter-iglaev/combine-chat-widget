#!/usr/bin/env python3
"""Сборщик списка чатов для ChatBar. Читает только локальные данные приложений.

Команды:
  list                     -> JSON-массив чатов в stdout
  launch-gpt               -> (пере)запускает ChatGPT.app с отладочным портом
  open-gpt <id> [--relaunch]
      Открывает чат ChatGPT в ChatGPT.app через отладочный порт (CDP).
      Код выхода 3: ChatGPT.app запущен без порта, нужен перезапуск (--relaunch).
"""
import io
import json
import os
import pathlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.request
from datetime import datetime

HOME = pathlib.Path.home()
APP_SUPPORT = HOME / "Library/Application Support"
CLAUDE_DIR = APP_SUPPORT / "Claude"
CODEX_STATE_DB = HOME / ".codex/state_5.sqlite"
GPT_LOCAL_STORAGE = APP_SUPPORT / "Codex/Default/Local Storage/leveldb"
CLAUDE_IDB_BLOBS = CLAUDE_DIR / "IndexedDB/https_claude.ai_0.indexeddb.blob"
CACHE_DIR = APP_SUPPORT / "ChatBar"

CHATGPT_APP = "/Applications/ChatGPT.app"
CHATGPT_BIN = CHATGPT_APP + "/Contents/MacOS/ChatGPT"
CDP_PORT = 9333


def log(msg):
    print(msg, file=sys.stderr)


def iso_to_ms(s):
    if not s:
        return 0
    if isinstance(s, (int, float)):  # секунды или миллисекунды
        return int(s * 1000 if s < 1e12 else s)
    try:
        return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return 0


def item(source, id_, title, updated, url=None, gpt_id=None, app="claude"):
    return {
        "id": f"{source}:{id_}",
        "source": source,
        "title": (title or "").strip() or "Без названия",
        "updated": int(updated or 0),
        "url": url,
        "gptId": gpt_id,
        "app": app,
    }


# ---------- Codex и ChatGPT Work ----------

def collect_codex():
    if not CODEX_STATE_DB.exists():
        return []
    con = sqlite3.connect(f"file:{CODEX_STATE_DB}?mode=ro", uri=True)
    rows = con.execute(
        """
        select id, thread_source,
               coalesce(nullif(name, ''), nullif(title, ''), first_user_message, ''),
               coalesce(updated_at_ms, updated_at * 1000)
        from threads
        where archived = 0
          and source not like '{%'
          and coalesce(thread_source, '') not in ('subagent', 'guardian_review')
        """
    ).fetchall()
    con.close()
    out = []
    for tid, tsource, title, updated in rows:
        source = "work" if tsource == "chatgpt_handoff" else "codex"
        title = title.splitlines()[0] if title else ""
        out.append(item(source, tid, title[:200], updated, url=f"codex://threads/{tid}", app="chatgpt"))
    return out


# ---------- Claude Code и Cowork (локальные сессии) ----------

def collect_claude_local():
    out = []
    for sub, source, make_url in (
        ("claude-code-sessions", "claude_code", lambda sid: f"claude://code/continue?session={sid}"),
        ("local-agent-mode-sessions", "cowork", lambda sid: f"claude://claude.ai/local_sessions/{sid}"),
    ):
        base = CLAUDE_DIR / sub
        if not base.exists():
            continue
        for f in base.glob("*/*/local_*.json"):
            if f.name.startswith("local_ditto_"):
                continue
            try:
                d = json.loads(f.read_text())
            except (OSError, ValueError):
                continue
            sid = d.get("sessionId")
            if not sid or d.get("isArchived"):
                continue
            updated = d.get("lastActivityAt") or d.get("createdAt") or 0
            out.append(item(source, sid, d.get("title"), updated, url=make_url(sid)))
    return out


# ---------- Облачные чаты Claude (кэш IndexedDB) ----------

def _read_claude_blob(path):
    from ccl_chromium_reader.serialization_formats import ccl_blink_value_deserializer as blink
    from ccl_chromium_reader.serialization_formats import ccl_v8_value_deserializer as v8
    from ccl_simplesnappy import ccl_simplesnappy as snappy

    data = path.read_bytes()
    if data[:3] == b"\xff\x11\x02":  # значение сжато snappy
        data = snappy.decompress(io.BytesIO(data[3:]))
    for off in range(6):
        try:
            return v8.Deserializer(io.BytesIO(data[off:]), host_object_delegate=blink.BlinkV8Deserializer().read).read()
        except Exception:
            continue
    return None


def _content_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        for part in content:
            if isinstance(part, dict) and part.get("type") == "text" and part.get("text"):
                return part["text"]
    return ""


def _first_user_text(tree):
    """Первая реплика пользователя в облачной сессии Code/Cowork: у них нет заголовка."""
    for ev in tree.get("messages") or tree.get("events") or []:
        if not isinstance(ev, dict):
            continue
        msg = ev.get("message") if isinstance(ev.get("message"), dict) else ev
        if ev.get("type") == "user" or msg.get("role") == "user":
            text = _content_text(msg.get("content")).strip()
            if text and not text.startswith("<"):
                return text.splitlines()[0][:120]
    return ""


def collect_claude_cloud():
    if not CLAUDE_IDB_BLOBS.exists():
        return []
    cache_file = CACHE_DIR / "claude-blob-cache.json"
    try:
        cache = json.loads(cache_file.read_text())
    except (OSError, ValueError):
        cache = {}
    new_cache = {}
    best = {}
    for f in CLAUDE_IDB_BLOBS.glob("*/*/*"):
        if not f.is_file():
            continue
        key = str(f)
        mtime = f.stat().st_mtime
        rec = cache.get(key)
        if not rec or rec.get("mtime") != mtime:
            rec = {"mtime": mtime, "conv": None}
            try:
                v = _read_claude_blob(f)
            except Exception as e:
                log(f"claude blob {f}: {e}")
                v = None
            if isinstance(v, dict) and v.get("conversationUuid") and isinstance(v.get("tree"), dict):
                t = v["tree"]
                rec["conv"] = {
                    "uuid": v["conversationUuid"],
                    "product": v.get("product"),
                    "name": t.get("name") or _first_user_text(t),
                    "updated": v.get("conversationUpdatedAt") or iso_to_ms(t.get("updated_at")),
                    "written": v.get("writtenAt") or 0,
                    "archived": bool(t.get("is_archived")),
                }
        new_cache[key] = rec
        c = rec["conv"]
        if c and (c["uuid"] not in best or c["written"] > best[c["uuid"]]["written"]):
            best[c["uuid"]] = c
    CACHE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    cache_file.write_text(json.dumps(new_cache))
    cache_file.chmod(0o600)

    out = []
    for c in best.values():
        if c["archived"]:
            continue
        uuid = c["uuid"]
        if uuid.startswith("cowork:"):
            sid = uuid.split(":", 1)[1]
            out.append(item("cowork", sid, c["name"], c["updated"], url=f"claude://claude.ai/cowork/{sid}"))
        elif uuid.startswith("code:"):
            sid = uuid.split(":", 1)[1]
            out.append(item("claude_code", sid, c["name"], c["updated"], url=f"claude://code/{sid}"))
        else:
            out.append(item("claude_chat", uuid, c["name"], c["updated"], url=f"claude://claude.ai/chat/{uuid}"))
    return out


# ---------- Обычные чаты ChatGPT (кэш Local Storage) ----------

def collect_chatgpt():
    if not GPT_LOCAL_STORAGE.exists():
        return []
    from ccl_chromium_reader import ccl_chromium_localstorage as ls

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="chatbar-ls-"))
    try:
        dst = tmp / "leveldb"
        shutil.copytree(GPT_LOCAL_STORAGE, dst, ignore=shutil.ignore_patterns("LOCK"))
        db = ls.LocalStoreDb(dst)
        latest = {}
        for r in db.iter_all_records():
            if r.script_key in ("codex.chatgpt-conversations", "codex.chatgpt-pinned-conversations"):
                prev = latest.get(r.script_key)
                if prev is None or r.leveldb_seq_number > prev[0]:
                    latest[r.script_key] = (r.leveldb_seq_number, r.value)
        db.close()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    convs = []
    if "codex.chatgpt-conversations" in latest:
        d = json.loads(latest["codex.chatgpt-conversations"][1])
        for page in d.get("pages", []):
            convs.extend(page.get("items", []))
    if "codex.chatgpt-pinned-conversations" in latest:
        d = json.loads(latest["codex.chatgpt-pinned-conversations"][1])
        convs.extend(x.get("item", {}) for x in d.get("items", []) if x.get("item_type") == "conversation")

    # Кэш Local Storage приложение обновляет редко, поэтому сверху кладём живой сайдбар.
    convs.extend(_chatgpt_sidebar_live())

    out = {}
    for c in convs:
        cid = c.get("id")
        if not cid or c.get("is_archived") or c.get("is_temporary_chat"):
            continue
        out[cid] = item("chatgpt", cid, c.get("title"), iso_to_ms(c.get("update_time")), gpt_id=cid, app="chatgpt")
    return list(out.values())


# Берём объекты conversation из React-пропсов строк сайдбара открытого окна ChatGPT.
SIDEBAR_JS = r"""
(() => {
  const out = [];
  for (const el of document.querySelectorAll('[data-sidebar-chatgpt-conversation-key^="chatgpt:conversation:"]')) {
    const start = el.querySelector('[data-thread-title]') || el;
    const fk = Object.keys(start).find(k => k.startsWith('__reactFiber'));
    let f = fk ? start[fk] : null, conv = null;
    for (let i = 0; i < 30 && f && !conv; i++, f = f.return) {
      const c = f.memoizedProps && f.memoizedProps.conversation;
      if (c && c.id) conv = c;
    }
    const id = el.getAttribute('data-sidebar-chatgpt-conversation-key').split(':').pop();
    const title = conv ? conv.title : (el.querySelector('[data-thread-title]') || {}).textContent;
    out.push({id, title, update_time: conv && conv.update_time, is_archived: !!(conv && conv.is_archived)});
  }
  return out;
})()
"""


def _chatgpt_sidebar_live():
    page = cdp_main_page()
    if page is None:
        return []
    try:
        return cdp_eval(page, SIDEBAR_JS) or []
    except Exception as e:
        log(f"chatgpt sidebar: {e!r}")
        return []


def cmd_list():
    items = []
    for fn in (collect_codex, collect_claude_local, collect_claude_cloud, collect_chatgpt):
        try:
            items.extend(fn())
        except Exception as e:
            log(f"{fn.__name__}: {e!r}")
    items.sort(key=lambda x: x["updated"], reverse=True)
    json.dump(items, sys.stdout, ensure_ascii=False)


# ---------- Открытие чата ChatGPT через CDP ----------

def cdp_get(path):
    with urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}{path}", timeout=1) as r:
        return json.load(r)


def cdp_main_page():
    try:
        pages = cdp_get("/json/list")
    except OSError:
        return None
    return next((p for p in pages if p.get("type") == "page" and p.get("url") == "app://-/index.html"), None)


def cdp_eval(page, expr):
    import websocket

    ws = websocket.create_connection(page["webSocketDebuggerUrl"], origin=f"http://127.0.0.1:{CDP_PORT}", timeout=5)
    try:
        ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {"expression": expr, "returnByValue": True}}))
        while True:
            m = json.loads(ws.recv())
            if m.get("id") == 1:
                return m.get("result", {}).get("result", {}).get("value")
    finally:
        ws.close()


def chatgpt_running():
    return subprocess.run(["pgrep", "-f", CHATGPT_BIN], capture_output=True).returncode == 0


def launch_chatgpt_with_port():
    if chatgpt_running():
        subprocess.run(["osascript", "-e", f'tell application "{CHATGPT_APP}" to quit'], capture_output=True)
        for _ in range(40):
            if not chatgpt_running():
                break
            time.sleep(0.5)
    subprocess.run([
        "open", "-a", CHATGPT_APP, "--args",
        f"--remote-debugging-port={CDP_PORT}",
        f"--remote-allow-origins=http://127.0.0.1:{CDP_PORT}",
    ])
    deadline = time.time() + 40
    while time.time() < deadline:
        page = cdp_main_page()
        if page:
            try:
                if cdp_eval(page, "document.readyState === 'complete' && document.body.innerText.length > 50"):
                    time.sleep(1.5)  # даём приложению подписаться на сообщения
                    return page
            except Exception:
                pass
        time.sleep(0.5)
    return None


def cmd_open_gpt(conv_id, relaunch):
    page = cdp_main_page()
    if page is None:
        if chatgpt_running() and not relaunch:
            return 3
        page = launch_chatgpt_with_port()
        if page is None:
            log("ChatGPT.app не поднял отладочный порт")
            return 1
    path = "/c/" + conv_id
    cdp_eval(page, 'window.postMessage({type:"navigate-to-route",path:%s},"*"); true' % json.dumps(path))
    subprocess.run(["open", "-a", CHATGPT_APP])
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "list":
        cmd_list()
        return 0
    if len(argv) >= 2 and argv[1] == "launch-gpt":
        if cdp_main_page():
            print("ChatGPT уже запущен с отладочным портом")
            return 0
        return 0 if launch_chatgpt_with_port() else 1
    if len(argv) >= 3 and argv[1] == "open-gpt":
        return cmd_open_gpt(argv[2], "--relaunch" in argv[3:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
