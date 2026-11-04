"""User Corrections: words the model should spell a given way, kept in a private file written by Settings.

    {"entries": [{"typed": "uzdraveni", "correct": "uzdravení", "always": false}, ...]}

`typed` is what the user types (no marks), `correct` the form wanted; each is a word or a short phrase. The file is read at
every request (cached by mtime); a missing or malformed file, or a bad entry, means no entries and never an error. An entry
is dropped when a field is empty, longer than MAX_FIELD characters, not text, or holds a control character (a newline would
break the prompt); fields are trimmed. At most MAX_ENTRIES entries are read.

relevant(): the entries whose `typed` occurs in the input as whole words, ignoring case and diacritics on both sides (phrases:
any whitespace between the words). prompt_block(): the hints appended to the system prompt, at most MAX_HINTS of them.
apply_always(): the `always` entries applied to the model's reply, deterministically (see there). User text is never logged.
"""
from __future__ import annotations

import html as html_lib
import json
import os
import re
import threading
import unicodedata
from dataclasses import dataclass, field

from . import paths

MAX_ENTRIES = 500   # entries read from the file
MAX_HINTS = 30      # relevant entries that reach the prompt
MAX_FIELD = 80      # characters per field; a longer field drops the entry (truncating a correct form would corrupt it)


@dataclass(frozen=True)
class Entry:
    typed: str
    correct: str
    always: bool = False
    typed_re: re.Pattern = field(default=None, compare=False, repr=False)
    correct_re: re.Pattern = field(default=None, compare=False, repr=False)


def fold(s: str) -> str:
    """Lower case without diacritics, exactly as long as `s` (so a match in it is a match in `s`)."""
    out = []
    for c in s:
        d = "".join(x for x in unicodedata.normalize("NFD", c) if not unicodedata.combining(x))
        if len(d) != 1:
            out.append(c)
            continue
        low = d.lower()
        out.append(low if len(low) == 1 else d)
    return "".join(out)


def _pattern(text: str) -> re.Pattern:
    """Whole-word pattern for the folded text; whitespace between its words matches any whitespace."""
    body = ""
    for piece in re.findall(r"\w+|\W+", fold(text)):
        if piece[0].isalnum() or piece[0] == "_":
            body += re.escape(piece)
        else:
            body += "".join(r"\s+" if p[:1].isspace() else re.escape(p) for p in re.split(r"(\s+)", piece) if p)
    return re.compile(r"(?<!\w)" + body + r"(?!\w)")


def _field(v) -> str | None:
    if not isinstance(v, str):
        return None
    v = v.strip()
    if not v or len(v) > MAX_FIELD or any(unicodedata.category(c).startswith("C") for c in v):
        return None
    return v


def parse(data) -> tuple:
    if not isinstance(data, dict) or not isinstance(data.get("entries"), list):
        return ()
    out = []
    for e in data["entries"][:MAX_ENTRIES]:
        if not isinstance(e, dict):
            continue
        typed, correct = _field(e.get("typed")), _field(e.get("correct"))
        if typed is None or correct is None or not re.search(r"\w", typed):
            continue
        try:
            out.append(Entry(typed, correct, e.get("always") is True, _pattern(typed), _pattern(correct)))
        except re.error:
            continue
    return tuple(out)


_cache: dict = {}
_lock = threading.Lock()


def load(path: str | None = None) -> tuple:
    """The entries of the file; read again when its mtime, size or inode changed."""
    path = path or paths.words_file()
    try:
        st = os.stat(path)
    except OSError:
        return ()
    stamp = (st.st_mtime_ns, st.st_size, st.st_ino)
    with _lock:
        hit = _cache.get(path)
        if hit and hit[0] == stamp:
            return hit[1]
    try:
        with open(path, encoding="utf-8") as f:
            entries = parse(json.load(f))
    except (OSError, ValueError, RecursionError):
        entries = ()
    with _lock:
        _cache[path] = (stamp, entries)
    return entries


def relevant(entries, text: str) -> list:
    """The entries whose `typed` occurs in `text` as whole words (case and diacritics ignored)."""
    if not entries or not text:
        return []
    folded = fold(text)
    return [e for e in entries if e.typed_re.search(folded)]


def prompt_block(entries, html: bool = False) -> str:
    """The hints appended to the system prompt; "" for no entries (the prompt stays byte-identical)."""
    entries = list(entries)[:MAX_HINTS]
    if not entries:
        return ""
    return (FORMAT_HEAD + "".join(FORMAT_LINE.format(typed=e.typed, correct=e.correct) for e in entries))


FORMAT_HEAD = "\n\nKnown spellings of this user. When the text contains the left form (any capitalization, with or without marks), write it exactly as the right form:\n"
FORMAT_LINE = "{typed} -> {correct}\n"


# always ---------------------------------------------------------------------------------------------------------------


def copy_case(original: str, correct: str) -> str:
    """`correct` in the capitalization of the replaced `original`: ALL CAPS, Capitalized, else as stored. A form with a capital after its
    first letter (iOS, GitHub) is the user's spelling and never changes."""
    letters_c = [c for c in correct if c.isalpha()]
    if any(c.isupper() for c in letters_c[1:]) and any(c.islower() for c in letters_c):
        return correct
    letters = [c for c in original if c.isalpha()]
    if len(letters) >= 2 and all(c.isupper() for c in letters):
        return correct.upper()
    if letters and letters[0].isupper():
        for i, c in enumerate(correct):
            if c.isalpha():
                return correct[:i] + c.upper() + correct[i + 1:]
    return correct


def _spans(text: str, entries, left_blocked: bool = False, right_blocked: bool = False) -> list:
    """Non-overlapping (start, end, replacement) for the `always` entries in `text`: the leftmost match wins, then the longest,
    then the earlier entry. Both the typed form and the correct form (other case, other marks) are matched."""
    folded = fold(text)
    found = []
    for i, e in enumerate(entries):
        if not e.always:
            continue
        for rx in (e.typed_re, e.correct_re):
            for m in rx.finditer(folded):
                if (m.start() == 0 and left_blocked) or (m.end() == len(text) and right_blocked):
                    continue
                found.append((m.start(), -(m.end() - m.start()), i, m.end()))
    found.sort()
    out, end = [], 0
    for start, _, i, stop in found:
        if start < end:
            continue
        new = copy_case(text[start:stop], entries[i].correct)
        if new != text[start:stop]:
            out.append((start, stop, new))
        end = stop
    return out


def _splice(text: str, spans: list) -> str:
    for start, stop, new in reversed(spans):
        text = text[:start] + new + text[stop:]
    return text


_MARKUP = re.compile(r"(<!--.*?-->|<(script|style)\b.*?</\2\s*>|<[^>]*>|&#?\w+;)", re.S | re.I)


def _is_letter_ref(piece: str) -> bool:
    """A character reference that decodes to a letter or digit (&eacute;): it continues the word next to it."""
    if not piece.startswith("&"):
        return False
    c = html_lib.unescape(piece)
    return len(c) == 1 and (c.isalnum() or c == "_")


def apply_always(text: str, entries, html: bool = False) -> str:
    """The reply with every `always` entry applied: whole words, case and diacritics ignored, replaced by `correct` with the
    first-letter capital carried over; everything else stays byte for byte. HTML: only text between tags is touched, one run at a
    time (a phrase does not span a tag or an entity; a word next to a letter reference such as &eacute; is not whole), never a tag, attribute,
    comment, script, style or entity."""
    entries = [e for e in entries if e.always]
    if not entries or not text:
        return text
    if not html:
        return _splice(text, _spans(text, entries))
    parts = _MARKUP.split(text)
    # split() with 2 groups yields text, tag, name, text, tag, name, ...
    pieces = []
    for k in range(0, len(parts), 3):
        pieces.append((False, parts[k]))
        if k + 1 < len(parts):
            pieces.append((True, parts[k + 1]))
    out = []
    for k, (is_markup, piece) in enumerate(pieces):
        if is_markup or not piece:
            out.append(piece)
            continue
        lb = k > 0 and _is_letter_ref(pieces[k - 1][1])
        rb = k + 1 < len(pieces) and _is_letter_ref(pieces[k + 1][1])
        out.append(_splice(piece, _spans(piece, entries, lb, rb)))
    return "".join(out)
