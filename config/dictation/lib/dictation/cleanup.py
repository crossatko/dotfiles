"""Cleanup stage: filler filter and replacement list, applied to every pass hypothesis before the stability check, so
a removed or replaced word is never typed and then erased.

Interface (the engine's `cleanup=` seam):
    c = Cleanup()                        # word lists from words_file(), built-in defaults from default-words.json
    prompt = c.begin("cs", False)        # at every session start: re-reads the file when it changed; returns the
                                         # recognizer's vocabulary-hint prompt ("" = none; never in translate mode)
    segments, hold = c.apply([["Um,", "so"], ...], "en")
                                         # per-segment words in, cleaned per-segment words out, plus how many
                                         # trailing words may still turn into a longer phrase (live passes hold them)

Word file (written by Settings > Voice), every part optional:
    {"version": 1, "fillers": {"cs": [...], "en": [...]}, "hints": false,
     "replacements": [{"heard": "pull requests", "typed": "PRs", "lang": "any" | "cs" | "en"}]}
The hint switch itself lives in the voice prefs (prefs_file(), "prompt_hints", written by the same page); the
words file's "hints" is its mirror and counts only when the prefs have no "prompt_hints".
A language missing from "fillers" keeps the built-in list; a present list (even empty) replaces it. A missing,
empty or malformed file means the built-in fillers and no replacements; bad entries are skipped one by one.
"""
from __future__ import annotations

import json
import os
import re
import unicodedata
from dataclasses import dataclass, field

DEFAULTS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "default-words.json")
LANGUAGES = ("cs", "en")
MAX_HINT_TERMS = 12  # keep the prompt short: a long prompt drags the decode towards it
MAX_HINT_CHARS = 160

_SENTENCE_END = ".?!…"
_OPENING = "\"'([{„‚“‘«¿¡"
_CLOSING = ")]}"
_SOFT = set(".,;:!?…\"'()[]{}„‚“”‘’«»¿¡-–—")  # edge punctuation a heard word may carry (C++ or C# may not)
_RUN3 = re.compile(r"(.)\1\1+")
_RUN = re.compile(r"(.)\1+")


def words_file() -> str:
    return os.environ.get("DICTATION_WORDS_FILE") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "quickshell", "dictation-words.json")


def prefs_file() -> str:
    return os.environ.get("DICTATION_PREFS_FILE") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "quickshell", "dictation-prefs.json")


# --- words ----------------------------------------------------------------------------------------------------------


def _split(word: str) -> tuple:
    """(leading punctuation, core, trailing punctuation); the core starts and ends with a letter or digit."""
    i, j = 0, len(word)
    while i < j and not word[i].isalnum():
        i += 1
    while j > i and not word[j - 1].isalnum():
        j -= 1
    return word[:i], word[i:j], word[j:]


def _key(core: str) -> str:
    """Comparison key: no case, no diacritics."""
    return "".join(c for c in unicodedata.normalize("NFKD", core) if not unicodedata.combining(c)).casefold()


def _is_filler(key: str, fillers, drawn_out) -> bool:
    """A filler entry exactly, or a drawn-out one: a letter repeated three times or more ("hmmm", "eeee") matches an
    entry with every run collapsed. A doubled letter alone is not a drawn-out sound ("err" is a word, never the
    filler "er")."""
    return key in fillers or (_RUN3.search(key) is not None and _RUN.sub(r"\1", key) in drawn_out)


def _copy_case(original: str, typed: str) -> str:
    """The replacement in the original's capitalization: ALL CAPS, Capitalized, or as the user typed it. A typed form
    that mixes cases (iOS, GitHub, PRs) is the user's spelling and never changes."""
    typed_letters = [c for c in typed if c.isalpha()]
    if any(c.isupper() for c in typed_letters) and any(c.islower() for c in typed_letters):
        return typed
    letters = [c for c in original if c.isalpha()]
    if len(letters) >= 2 and all(c.isupper() for c in letters):
        return typed.upper()
    if letters and letters[0].isupper():
        for i, c in enumerate(typed):
            if c.isalpha():
                return typed[:i] + c.upper() + typed[i + 1 :]
    return typed


def _capitalize(word: str) -> str:
    """Upper-case the first letter, unless the word already mixes cases (iPhone, eBay stay as they are)."""
    lead, core, trail = _split(word)
    if not core or not core[0].islower() or any(c.isupper() for c in core):
        return word
    return lead + core[0].upper() + core[1:] + trail


# --- rules ----------------------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Replacement:
    heard: tuple  # keys of the heard words
    typed: str
    lang: str  # "any", "cs" or "en"


@dataclass
class Rules:
    fillers: dict = field(default_factory=dict)  # language -> frozenset of filler keys
    replacements: list = field(default_factory=list)
    hints: bool = False

    def for_language(self, language: str) -> tuple:
        """(filler keys, {first key: [replacements, longest first]}) for one language."""
        table: dict = {}
        for r in self.replacements:
            if r.lang in ("any", language):
                table.setdefault(r.heard[0], []).append(r)
        for entries in table.values():
            entries.sort(key=lambda r: -len(r.heard))  # stable: the first entry wins among equal lengths
        return self.fillers.get(language, frozenset()), table


def _read(path: str):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("version", 1) != 1:
        return None
    return data


def _fillers(data) -> dict:
    out = {}
    raw = data.get("fillers") if isinstance(data, dict) else None
    if not isinstance(raw, dict):
        return out
    for lang in LANGUAGES:
        entries = raw.get(lang)
        if isinstance(entries, list):
            keys = set()
            for e in entries:
                if isinstance(e, str):
                    _, core, _ = _split(e.strip())
                    if core and " " not in core:
                        keys.add(_key(core))
            out[lang] = frozenset(keys)
    return out


def _replacements(data) -> list:
    out, seen = [], set()
    raw = data.get("replacements") if isinstance(data, dict) else None
    if not isinstance(raw, list):
        return out
    for e in raw:
        if not isinstance(e, dict):
            continue
        heard, typed, lang = e.get("heard"), e.get("typed"), e.get("lang", "any")
        if not isinstance(heard, str) or not isinstance(typed, str) or lang not in ("any",) + LANGUAGES:
            continue
        parts = [_split(w) for w in heard.split()]
        if any(set(lead + trail) - _SOFT for lead, _, trail in parts):
            continue  # "C++": the key would be "c" and replace every lone c
        keys = tuple(_key(core) for _, core, _ in parts)
        typed = " ".join("".join(c for c in typed if unicodedata.category(c) not in ("Cc", "Cf", "Cs")).split())
        if not keys or not all(keys) or not typed or (keys, lang) in seen:
            continue
        seen.add((keys, lang))
        out.append(Replacement(keys, typed, lang))
    return out


def load_rules(path: str | None = None, defaults: str = DEFAULTS_FILE, prefs: str | None = None) -> Rules:
    """Never raises: whatever is unreadable falls back to the built-in defaults (hints off)."""
    base = _read(defaults) or {}
    user = _read(path or words_file()) or {}
    fillers = _fillers(base)
    fillers.update(_fillers(user))
    switch = (_read(prefs or prefs_file()) or {}).get("prompt_hints")
    hints = switch if isinstance(switch, bool) else user.get("hints") is True
    return Rules(fillers, _replacements(user), hints)


# --- the stage ------------------------------------------------------------------------------------------------------


def remove_fillers(tokens: list, fillers) -> list:
    """tokens: [(segment index, word)]. Drops filler words and tidies what they leave behind: their trailing comma
    goes with them, a sentence end moves to the previous word, a filler where a sentence starts passes the capital
    on to the next word, brackets stay paired, and a comma left dangling at the very end is dropped."""
    if not fillers:
        return tokens
    drawn_out = {_RUN.sub(r"\1", k) for k in fillers}
    out: list = []
    capitalize_next, opening, removed_last = False, "", False
    for seg, word in tokens:
        lead, core, trail = _split(word)
        if core and _is_filler(_key(core), fillers, drawn_out):
            removed_last = True
            opening += "".join(c for c in lead if c in _OPENING)
            for c in trail:
                if c in _CLOSING:
                    if opening:  # "(um)": the pair goes with the filler
                        opening = opening[:-1]
                    elif out:
                        out[-1] = (out[-1][0], out[-1][1] + c)
            end = "".join(c for c in trail if c in _SENTENCE_END)
            if end and out:
                pseg, prev = out[-1]
                if prev[-1:] not in _SENTENCE_END:
                    out[-1] = (pseg, prev.rstrip(",;:—–-") + end)
            # a filler where a sentence starts passes the capital on: at the very start only when it had one (the
            # window may start mid-sentence), after a sentence end always
            if (not out and core[0].isupper()) or (out and out[-1][1][-1:] in _SENTENCE_END):
                capitalize_next = True
            continue
        removed_last = False
        if capitalize_next:
            word = _capitalize(word)
            capitalize_next = False
        if opening:
            word, opening = opening + word, ""
        out.append((seg, word))
    if removed_last and out:
        pseg, prev = out[-1]
        stripped = prev.rstrip(",;:")
        if stripped:
            out[-1] = (pseg, stripped)
    return out


def _joinable(tokens: list, i: int, n: int) -> bool:
    """tokens[i:i+n] can be one phrase: no punctuation between its words."""
    for k in range(i, i + n):
        lead, _, trail = _split(tokens[k][1])
        if (k > i and lead) or (k < i + n - 1 and trail):
            return False
    return True


def replace(tokens: list, table: dict) -> tuple:
    """Longest phrase first, left to right, never re-matching replaced text. Returns (tokens, hold): hold = how many
    trailing output words are the start of a longer phrase that the next words may still complete."""
    if not table:
        return tokens, 0
    keys = [_key(_split(w)[1]) for _, w in tokens]
    out: list = []
    src: list = []  # input index each output word comes from
    i = 0
    while i < len(tokens):
        match = None
        for r in table.get(keys[i], ()):
            n = len(r.heard)
            if tuple(keys[i : i + n]) == r.heard and _joinable(tokens, i, n):
                match = r
                break
        if match is None:
            out.append(tokens[i])
            src.append(i)
            i += 1
            continue
        n = len(match.heard)
        lead, _, _ = _split(tokens[i][1])
        _, _, trail = _split(tokens[i + n - 1][1])
        original = " ".join(_split(w)[1] for _, w in tokens[i : i + n])
        words = (lead + _copy_case(original, match.typed) + trail).split()
        out += [(tokens[i][0], w) for w in words]
        src += [i] * len(words)
        i += n
    return out, _hold(tokens, keys, table, src)


def _hold(tokens: list, keys: list, table: dict, src: list) -> int:
    """Output words from the longest input tail that is a proper prefix of some phrase (the words after it may still
    complete that phrase)."""
    total = len(tokens)
    if not total or _split(tokens[-1][1])[2]:
        return 0  # punctuation after the last word: no phrase continues across it
    for k in range(min(total, max((len(r.heard) for rs in table.values() for r in rs), default=1) - 1), 0, -1):
        start = total - k
        tail = tuple(keys[start:])
        if not _joinable(tokens, start, k):
            continue
        if any(len(r.heard) > k and r.heard[:k] == tail for r in table.get(tail[0], ())):
            return sum(1 for s in src if s >= start)
    return 0


class Cleanup:
    def __init__(self, path: str | None = None, defaults: str = DEFAULTS_FILE, prefs: str | None = None):
        self._path = path
        self._defaults = defaults
        self._prefs = prefs
        self._lang_cache = (None, None, None)
        self._stamp = self._file_stamp()  # before reading: a change while reading is picked up next time
        self.rules = load_rules(path, defaults, prefs)

    def _file_stamp(self):
        stamps = []
        for path in (self._path or words_file(), self._prefs or prefs_file()):
            try:
                st = os.stat(path)
                stamps.append((st.st_mtime_ns, st.st_size, st.st_ino))
            except OSError:
                stamps.append(None)
        return tuple(stamps)

    def begin(self, language: str, translate: bool) -> str:
        """Session start: reload the word file when it changed. Returns the vocabulary-hint prompt for the
        recognizer: the replacement targets, only when hints are on and only when transcribing (hints hurt
        translation quality in the benchmark)."""
        stamp = self._file_stamp()
        if stamp != self._stamp:
            self.rules = load_rules(self._path, self._defaults, self._prefs)
            self._stamp = stamp
        if translate or not self.rules.hints:
            return ""
        return self.prompt(language)

    def prompt(self, language: str) -> str:
        terms: list = []
        for r in self.rules.replacements:
            if r.lang in ("any", language) and r.typed not in terms:
                if len(terms) >= MAX_HINT_TERMS or len(", ".join(terms + [r.typed])) > MAX_HINT_CHARS:
                    break
                terms.append(r.typed)
        return ", ".join(terms) + "." if terms else ""

    def apply(self, segments: list, language: str) -> tuple:
        """segments: [[word, ...], ...] (one list per recognised segment, phrases may span them). Returns the cleaned
        lists (same count, possibly empty) and the number of trailing words a live pass must not type yet."""
        if self._lang_cache[0] is not self.rules or self._lang_cache[1] != language:
            self._lang_cache = (self.rules, language, self.rules.for_language(language))
        fillers, table = self._lang_cache[2]
        tokens = [(i, w) for i, ws in enumerate(segments) for w in ws]
        tokens = remove_fillers(tokens, fillers)
        tokens, hold = replace(tokens, table)
        out: list = [[] for _ in segments]
        for i, w in tokens:
            out[i].append(w)
        return out, hold
