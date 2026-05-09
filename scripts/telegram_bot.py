#!/usr/bin/env python3
"""NiederClaude Telegram bot — responds to all messages, not just commands."""

import os
import sys
import time
import logging
import requests
import anthropic

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
PAIRED_USERNAME = os.environ.get("PAIRED_USERNAME", "niederme")

if not BOT_TOKEN:
    sys.exit("TELEGRAM_BOT_TOKEN is not set")
if not ANTHROPIC_API_KEY:
    sys.exit("ANTHROPIC_API_KEY is not set")

API = f"https://api.telegram.org/bot{BOT_TOKEN}"
claude = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

conversation_history: dict[int, list[dict]] = {}


def api(method: str, **kwargs) -> dict:
    r = requests.post(f"{API}/{method}", json=kwargs, timeout=30)
    r.raise_for_status()
    return r.json()


def send(chat_id: int, text: str) -> None:
    api("sendMessage", chat_id=chat_id, text=text, parse_mode="Markdown")


def reply_to_text(chat_id: int, user_text: str) -> str:
    history = conversation_history.setdefault(chat_id, [])
    history.append({"role": "user", "content": user_text})

    response = claude.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1024,
        system=(
            "You are NiederClaude, a personal assistant for @niederme. "
            "Be concise and helpful. You can discuss analytics, websites, "
            "projects, or anything the user asks about."
        ),
        messages=history,
    )

    reply_text = response.content[0].text
    history.append({"role": "assistant", "content": reply_text})

    # Keep context window manageable
    if len(history) > 20:
        conversation_history[chat_id] = history[-20:]

    return reply_text


def handle_update(update: dict) -> None:
    message = update.get("message") or update.get("edited_message")
    if not message:
        return

    chat_id: int = message["chat"]["id"]
    text: str = message.get("text", "")

    if not text:
        return

    log.info("chat=%s text=%r", chat_id, text[:80])

    if text.startswith("/start"):
        send(chat_id, f"👋 Hey! I'm NiederClaude, paired as @{PAIRED_USERNAME}. Send me anything.")
        return

    if text.startswith("/status"):
        send(chat_id, f"Paired as @{PAIRED_USERNAME}.")
        return

    if text.startswith("/reset"):
        conversation_history.pop(chat_id, None)
        send(chat_id, "Conversation reset.")
        return

    # All other messages — including plain text — go to Claude
    try:
        reply = reply_to_text(chat_id, text)
        send(chat_id, reply)
    except Exception as exc:
        log.error("Claude error: %s", exc)
        send(chat_id, "Sorry, something went wrong. Try again.")


def poll() -> None:
    offset = 0
    log.info("Polling for updates…")
    while True:
        try:
            data = api("getUpdates", offset=offset, timeout=25, allowed_updates=["message", "edited_message"])
            for update in data.get("result", []):
                handle_update(update)
                offset = update["update_id"] + 1
        except requests.exceptions.Timeout:
            pass
        except requests.exceptions.RequestException as exc:
            log.warning("Telegram error: %s — retrying in 5s", exc)
            time.sleep(5)
        except Exception as exc:
            log.error("Unexpected error: %s — retrying in 5s", exc)
            time.sleep(5)


if __name__ == "__main__":
    poll()
