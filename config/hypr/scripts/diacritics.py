#!/usr/bin/env python3
"""Czech diacritics corrector via OpenRouter API.

Highlight text → Super+Ctrl+V → corrects diacritics and pastes in place.
Requires: wl-clipboard, wtype
"""

import os
import re
import json
import sys
import subprocess
import time
import urllib.request
from datetime import datetime

LOG_PATH = os.path.expanduser("~/.config/hypr/scripts/diacritics.log")
API_URL = "https://openrouter.ai/api/v1/chat/completions"
MODEL = "google/gemini-2.5-flash"

SYSTEM_PROMPT = (
    "You are a text processing engine for Czech. "
    "Your ONLY task is to add missing Czech diacritics (á, é, í, ó, ú, ů, ě, š, č, ř, ž, ý, ď, ť, ň) "
    "and fix obvious spelling errors. "
    "Do NOT change meaning, tone, formatting, or punctuation. "
    "If the text already has correct diacritics, return it unchanged. "
    "IMPORTANT: Output ONLY the corrected text. No explanations, no prefixes, no markdown fences."
)


def log(msg, level="INFO"):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] [{level}] {msg}"
    print(line, file=sys.stderr)
    try:
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def notify(title, message, urgency="normal"):
    log(f"notify: {title}: {message}")
    try:
        subprocess.run(["notify-send", "-u", urgency, title, message], timeout=5)
    except Exception:
        pass


def load_api_key():
    candidates = [
        os.path.expanduser("~/.config/hypr/.secrets"),
        os.path.expanduser("~/.secrets"),
    ]
    for path in candidates:
        try:
            with open(path) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("OPENROUTER_API_KEY="):
                        key = line.split("=", 1)[1].strip().strip('"').strip("'")
                        if key:
                            log(f"Loaded API key from {path}")
                            return key
        except FileNotFoundError:
            continue
        except Exception as e:
            log(f"Error reading {path}: {e}", "WARN")

    env_key = os.environ.get("OPENROUTER_API_KEY")
    if env_key:
        log("Using OPENROUTER_API_KEY from environment")
    return env_key


def get_selected_text():
    """Read PRIMARY selection (highlighted text)."""
    try:
        result = subprocess.run(
            ["wl-paste", "--primary", "--no-newline"],
            capture_output=True, text=True, timeout=5
        )
        log(f"PRIMARY selection read: {len(result.stdout)} chars, exit code {result.returncode}")
        return result.stdout if result.returncode == 0 else ""
    except FileNotFoundError:
        log("wl-paste not found!", "ERROR")
        notify("Czech Diacritics", "wl-paste not found", "critical")
        sys.exit(1)
    except Exception as e:
        log(f"PRIMARY read failed: {e}", "ERROR")
        return ""


def set_clipboard(text):
    """Write corrected text to clipboard."""
    try:
        result = subprocess.run(
            ["wl-copy"],
            input=text, text=True, timeout=5
        )
        log(f"Clipboard write: {len(text)} chars, exit code {result.returncode}")
        return result.returncode == 0
    except Exception as e:
        log(f"Clipboard write failed: {e}", "ERROR")
        return False


def paste():
    """Simulate Ctrl+V to paste corrected text into focused window."""
    try:
        time.sleep(0.05)
        result = subprocess.run(["wtype", "-M", "ctrl", "v"], timeout=5)
        log(f"Paste via wtype: exit code {result.returncode}")
        return result.returncode == 0
    except FileNotFoundError:
        log("wtype not found — cannot auto-paste. Install: sudo pacman -S wtype", "ERROR")
        return False
    except Exception as e:
        log(f"wtype failed: {e}", "ERROR")
        return False


def clean_response(text):
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL)
    text = re.sub(r"^```(?:czech|text)?\n", "", text)
    text = re.sub(r"\n```$", "", text)
    return text.strip()


def query_api(text):
    api_key = load_api_key()
    if not api_key:
        log("No API key found!", "ERROR")
        notify("Czech Diacritics", "No API key — set OPENROUTER_API_KEY in ~/.config/hypr/.secrets", "critical")
        return None

    payload = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": text},
        ],
        "temperature": 0.1,
        "max_tokens": 4096,
    }).encode("utf-8")

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }

    log(f"Sending {len(text)} chars to OpenRouter ({MODEL})")

    try:
        req = urllib.request.Request(API_URL, data=payload, headers=headers)
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read().decode("utf-8")
            log(f"API response: HTTP {resp.status}, {len(raw)} bytes")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        log(f"API HTTP error {e.code}: {body[:500]}", "ERROR")
        notify("Czech Diacritics", f"API error {e.code}", "critical")
        return None
    except Exception as e:
        log(f"API request failed: {e}", "ERROR")
        notify("Czech Diacritics", f"API failed: {e}", "critical")
        return None

    try:
        result = json.loads(raw)
        content = result["choices"][0]["message"]["content"]
        corrected = clean_response(content)
        log(f"Corrected: {len(corrected)} chars")
        return corrected
    except (json.JSONDecodeError, KeyError, IndexError) as e:
        log(f"Failed to parse response: {e}", "ERROR")
        log(f"Raw (first 500): {raw[:500]}", "ERROR")
        notify("Czech Diacritics", "Failed to parse response", "critical")
        return None


def main():
    log("--- Started ---")

    text = get_selected_text()
    if not text or text.strip() == "":
        log("No text selected")
        notify("Czech Diacritics", "No text selected")
        return

    corrected = query_api(text)
    if not corrected:
        return

    if corrected == text:
        log("Text unchanged (diacritics already correct)")
        notify("Czech Diacritics", "Already correct ✓")
        return

    if set_clipboard(corrected):
        if paste():
            notify("Czech Diacritics", "✓ Corrected & pasted")
        else:
            notify("Czech Diacritics", "Corrected — paste manually with Ctrl+V")
    else:
        notify("Czech Diacritics", "Clipboard write failed", "critical")

    log("--- Done ---")


if __name__ == "__main__":
    main()
