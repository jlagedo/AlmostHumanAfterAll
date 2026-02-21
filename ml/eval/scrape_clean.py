"""Clean web-scraping artifacts from context JSONL files.

Fixes:
- Malformed JSON (concatenated objects on one line)
- Zero-width / invisible Unicode chars (ZWSP, ZWJ, ZWNJ, LRM, RLM, BOM)
- HTML tags (<i>, <b>, <a href>, etc.) — strips them, keeps inner text
- HTML entities (&amp; &lt; &gt; &quot; &nbsp; &#NNN;)
- Unicode line/paragraph separators (U+2028, U+2029)
- Soft hyphens (U+00AD)
- Unicode replacement char (U+FFFD)
- Collapsed multiple spaces
- Normalized to NFC form
"""

import json
import re
import sys
import unicodedata
from pathlib import Path

# Zero-width and invisible characters to strip
PHANTOM_CHARS = re.compile(
    "[\u200b\u200c\u200d\u200e\u200f"  # ZWSP, ZWNJ, ZWJ, LRM, RLM
    "\ufeff"  # BOM
    "\u00ad"  # soft hyphen
    "\ufffd"  # replacement char
    "\u2028\u2029"  # line/paragraph separators
    "\u200a\u2009\u2008\u2007\u2006\u2005\u2004\u2003\u2002"  # various spaces
    "\u202a\u202b\u202c\u202d\u202e"  # bidi overrides
    "\u2066\u2067\u2068\u2069"  # bidi isolates
    "\u061c\ufffe\uffff]"
)

# HTML tags — strip them, keep inner text
HTML_TAG = re.compile(r"</?[a-zA-Z][^>]*>")

# HTML entities
HTML_ENTITY_MAP = {
    "&amp;": "&",
    "&lt;": "<",
    "&gt;": ">",
    "&quot;": '"',
    "&apos;": "'",
    "&nbsp;": " ",
}
HTML_ENTITY = re.compile(r"&(?:amp|lt|gt|quot|apos|nbsp|#(\d+)|#x([0-9a-fA-F]+));")

# Control characters (except tab \x09 and newline \x0a)
CONTROL_CHARS = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

# Multiple spaces
MULTI_SPACE = re.compile(r"  +")

# Emoji spam (3+ consecutive emoji-style chars)
EMOJI_SPAM = re.compile(
    "(?:[\U0001f300-\U0001f9ff\u2600-\u27bf\u200d\ufe0f]\\s*){3,}"
)

# Genius boilerplate — truncate everything from these markers onward.
# They appear as tails appended to otherwise valid bios and wiki summaries.
GENIUS_JUNK_MARKERS = [
    # English release calendars
    "WELCOME TO GENIUS",
    "RELEASE CALENDAR",
    "HOW CAN YOU HELP",
    # Korean/Japanese release calendars
    "발매 달력",  # Korean "release calendar"
    "This page highlights all notable",
    "This page highlights the notable",
    # Social / CTA
    "Follow us on Twitter",
    "Follow us on Instagram",
    "If you would like to learn more about this endeavor",
    "consider checking out these helpful pages",
    # Genius self-descriptions
    "Genius is the world's biggest",
    "Genius is the ultimate source",
    "Screen Genius is the TV and movie tag",
    # Genius community/editorial boilerplate
    "Learn more about Genius Romanization",
    "GJ Essentials",
    "Genius English Translations by visiting",
    "This artist page is to be used as the primary artist",
    "For more information on how to add movie",
    # Editorial instructions leaked into content
    "Singles are listed with a hyperlink",
    "Adding songs:",
    "Adding lyrics:",
    "edit the lyrics or add a comment",
    "don't forget to hit that like button",
    # Interview CTAs
    "To read Genius' full interview, click here",
    # Non-English / variant release calendars
    "Singles Release Calendar!",
    "Album Release Calendar!",
    "album releases, visit this page",
    # More editorial instructions
    "Do not edit the lyrics",
    "Edit the lyrics to add",
    "the suggestion box to discuss",
    # YouTube-style CTAs
    "don't forget to hit that like button",
    "subscribe for more music",
    # Social media CTAs
    "follow @",
    "Follow @",
    # Misc editorial leaks
    "For a full list of Norwegian contestants in the MGP, click here",
    "Click here to see passages from",
    "Please don't edit the lyrics",
    # Turkish Genius translation boilerplate
    "Genius'ta çeviri yapmaya",
    "Genius'ta Şarkı Nasıl",
    # Genius-Apple Music partnership boilerplate (mid-bio)
    "which allowed for smarter lyrics in the Apple Music",
    "embedded music player on Genius pages",
    "lyrics in the Apple Music & Genius apps",
    # Misc mid-text junk
    "Please don\u2019t edit the lyrics",
    "Please don't edit the lyrics",
    "If you enjoyed this deep dive",
    # Genius Romanizations in credits
    "by Genius Romanizations",
    # Genius community project CTA
    "If you would like to join the project, check out",
    # Theatre/cast page CTA
    "Learn more about their jobs in the theatre here",
    # Book promo (wikiSummary is a book ad, not track description)
    "Buy the Book",
    # Phone/ticket/linktree promo spam
    "linktr.ee/",
    "Tickets Tour",
]


def decode_html_entity(m: re.Match) -> str:
    full = m.group(0)
    if full in HTML_ENTITY_MAP:
        return HTML_ENTITY_MAP[full]
    if m.group(1):  # &#NNN;
        try:
            return chr(int(m.group(1)))
        except (ValueError, OverflowError):
            return ""
    if m.group(2):  # &#xHH;
        try:
            return chr(int(m.group(2), 16))
        except (ValueError, OverflowError):
            return ""
    return full


# Genius fake artist bios — entire field is platform boilerplate, not an artist bio.
# These appear when the "artist" on Genius is a community/aggregate page.
GENIUS_FAKE_BIO_OPENERS = [
    "Founded in 2009, Genius is",
    "Genius is a unique multimedia",
    "Genius Romanizations is the place",
    "Genius English Translations",
    "Genius Korean Translations",
    "Genius Romanizations",
    "Als Teil der Screen Genius",  # German Screen Genius community bio
    "Every single episode of this classic sitcom is now housed on Genius",
]


def strip_genius_junk(s: str) -> str:
    """Truncate Genius boilerplate tails (calendars, CTAs, self-promo).

    Also returns empty string for fields that are entirely Genius platform
    descriptions rather than real artist bios.
    """
    # Nuke entire fake bios
    for opener in GENIUS_FAKE_BIO_OPENERS:
        if s.lstrip().startswith(opener):
            return ""

    # Truncate boilerplate tails
    earliest = len(s)
    for marker in GENIUS_JUNK_MARKERS:
        idx = s.find(marker)
        if idx != -1 and idx < earliest:
            earliest = idx
    if earliest < len(s):
        s = s[:earliest]
    return s


def strip_urls(s: str) -> str:
    """Remove inline URLs (common in Genius scraped text)."""
    return re.sub(r"https?://\S+", "", s)


def clean_string(s: str) -> str:
    s = unicodedata.normalize("NFC", s)
    s = PHANTOM_CHARS.sub("", s)
    s = HTML_TAG.sub("", s)
    s = HTML_ENTITY.sub(decode_html_entity, s)
    s = CONTROL_CHARS.sub("", s)
    s = strip_genius_junk(s)
    s = strip_urls(s)
    s = EMOJI_SPAM.sub("", s)
    s = MULTI_SPACE.sub(" ", s)
    s = s.strip()
    return s


def clean_value(v):
    if isinstance(v, str):
        return clean_string(v)
    if isinstance(v, list):
        return [clean_value(item) for item in v]
    if isinstance(v, dict):
        return {k: clean_value(val) for k, val in v.items()}
    return v


def split_concatenated_json(line: str) -> list[dict]:
    """Handle lines with multiple JSON objects concatenated (no separator).

    Uses raw_decode first, then falls back to scanning for '{' to recover
    objects even when the break point corrupted surrounding JSON.
    """
    objects = []
    decoder = json.JSONDecoder()
    idx = 0
    line = line.strip()

    while idx < len(line):
        # Try decoding at current position
        try:
            obj, end = decoder.raw_decode(line, idx)
            if isinstance(obj, dict):
                objects.append(obj)
            idx = end
            while idx < len(line) and line[idx] in " \t":
                idx += 1
            continue
        except json.JSONDecodeError:
            pass

        # Skip to next '{' and try again
        next_brace = line.find("{", idx + 1)
        if next_brace == -1:
            break
        idx = next_brace

    return objects


def clean_file(input_path: Path) -> Path:
    output_path = input_path.with_stem(input_path.stem + "_cleaned")

    stats = {
        "total_lines": 0,
        "output_records": 0,
        "split_lines": 0,
        "skipped_lines": 0,
        "cleaned_strings": 0,
    }

    with open(input_path, encoding="utf-8", errors="replace") as fin, open(
        output_path, "w", encoding="utf-8"
    ) as fout:
        for line in fin:
            stats["total_lines"] += 1
            line = line.strip()
            if not line:
                continue

            # Try normal parse first
            try:
                obj = json.loads(line)
                objects = [obj]
            except json.JSONDecodeError:
                objects = split_concatenated_json(line)
                if not objects:
                    stats["skipped_lines"] += 1
                    print(
                        f"  skip line {stats['total_lines']}: unparseable",
                        file=sys.stderr,
                    )
                    continue
                if len(objects) > 1:
                    stats["split_lines"] += 1

            for obj in objects:
                cleaned = clean_value(obj)
                fout.write(json.dumps(cleaned, ensure_ascii=False) + "\n")
                stats["output_records"] += 1

    print(f"Input:   {input_path}")
    print(f"Output:  {output_path}")
    print(f"Lines read:      {stats['total_lines']}")
    print(f"Records written: {stats['output_records']}")
    if stats["split_lines"]:
        print(f"Split lines:     {stats['split_lines']} (had concatenated objects)")
    if stats["skipped_lines"]:
        print(f"Skipped:         {stats['skipped_lines']} (unparseable)")

    return output_path


if __name__ == "__main__":
    default = Path(__file__).resolve().parent.parent / "data" / "training" / "context_17k.jsonl"
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        sys.exit(1)
    clean_file(path)
