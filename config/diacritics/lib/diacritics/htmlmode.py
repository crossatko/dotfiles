"""HTML mode helpers for the key flow: decide whether a copied text/html holds real markup, cut the browser wrapper
off before the fix, put it back after, and derive a plain-text fallback.

Rich-text sources put text/html next to text/plain. Chromium prefixes `<meta charset='utf-8'>` and wraps even plain page
text in one styled <span>; Firefox/GTK/Windows-style sources wrap a fragment in <html><body><!--StartFragment-->. A
copy whose only tag is one such wrapper (span/div/p) is plain text for our purpose: the plain flow handles it.
"""
from __future__ import annotations

import re
from html.parser import HTMLParser

META_PREFIX = "<meta charset='utf-8'>"  # Chromium reads text/html as UTF-8 only with this
_WRAPPER_TAGS = {"meta", "html", "head", "body"}
_TRIVIAL_TAGS = {"span", "div", "p"}
_BLOCK = {"p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "blockquote", "pre", "table"}
_FRAG = re.compile(r"<!--\s*StartFragment\s*-->(.*)<!--\s*EndFragment\s*-->", re.S | re.I)
_META = re.compile(r"^\s*(?:<meta\b[^>]*>\s*)+", re.I)


class _Tags(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.tags: list = []

    def handle_starttag(self, tag, attrs):
        if tag not in _WRAPPER_TAGS:
            self.tags.append(tag)

    handle_startendtag = handle_starttag


def has_real_markup(html: str) -> bool:
    """True when the HTML has tags beyond a lone span/div/p wrapper (and meta/html/head/body)."""
    p = _Tags()
    try:
        p.feed(html)
        p.close()
    except Exception:  # noqa: BLE001 - broken markup: treat as plain
        return False
    tags = p.tags
    return len(tags) > 1 or (len(tags) == 1 and tags[0] not in _TRIVIAL_TAGS)


# Chromium dumps ~500 characters of computed style on every block it copies: no formatting, only noise for the model
_CHROMIUM_STYLE = re.compile(r"""\s+style=(["'])color: rgb\([^"']*?-webkit-text-stroke-width[^"']*?\1""")


def strip_wrapper(html: str) -> str:
    """The fragment without the leading <meta>, the StartFragment/EndFragment document wrapper and Chromium's
    computed-style dump. Real inline styles (a colour, a font weight) stay."""
    m = _FRAG.search(html)
    if m:
        html = m.group(1)
    return _CHROMIUM_STYLE.sub("", _META.sub("", html).strip())


def wrap(fragment: str) -> str:
    return META_PREFIX + fragment


class _Plain(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.out: list = []
        self.skip = 0

    def _nl(self) -> None:
        if self.out and not self.out[-1].endswith("\n"):
            self.out.append("\n")

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "head"):
            self.skip += 1
        elif tag == "br":
            self.out.append("\n")
        elif tag in _BLOCK:
            self._nl()
            if tag == "li":
                self.out.append("- ")

    def handle_startendtag(self, tag, attrs):
        if tag == "br":
            self.out.append("\n")

    def handle_endtag(self, tag):
        if tag in ("script", "style", "head"):
            self.skip = max(0, self.skip - 1)
        elif tag in _BLOCK:
            self._nl()

    def handle_data(self, data):
        if not self.skip:
            self.out.append(re.sub(r"[ \t\r\n]+", " ", data))


def to_plain(html: str) -> str:
    """Readable plain text from HTML: <br> and block ends become newlines, list items get "- "."""
    p = _Plain()
    try:
        p.feed(html)
        p.close()
    except Exception:  # noqa: BLE001
        return re.sub(r"<[^>]*>", "", html)
    text = "".join(p.out)
    return re.sub(r"\n[ ]+", "\n", re.sub(r"[ ]+\n", "\n", text)).strip("\n")


class _Sequence(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.seq: list = []

    def handle_starttag(self, tag, attrs):
        self.seq.append(("start", tag, tuple(attrs)))

    def handle_startendtag(self, tag, attrs):
        self.seq.append(("startend", tag, tuple(attrs)))

    def handle_endtag(self, tag):
        self.seq.append(("end", tag))


def tag_sequence(html: str) -> list:
    """Every tag of the fragment in order (kind, name, attributes), for checking that a fix left the markup alone."""
    p = _Sequence()
    p.feed(html)
    p.close()
    return p.seq


def same_markup(before: str, after: str) -> bool:
    try:
        return tag_sequence(before) == tag_sequence(after)
    except Exception:  # noqa: BLE001 - unparsable: do not trust it
        return False
