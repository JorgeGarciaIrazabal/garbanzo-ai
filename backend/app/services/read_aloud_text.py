"""Prepare assistant Markdown for sentence-sized English/Spanish speech units."""

from __future__ import annotations

import re
from dataclasses import dataclass

from markdown_it import MarkdownIt
from markdown_it.token import Token

MAX_MESSAGE_CHARS = 100_000
MAX_UNIT_CHARS = 300

_MARKDOWN = MarkdownIt("commonmark").enable("table")
_SENTENCE_BREAK = re.compile(r"(?<=[.!?])\s+(?=[^\s])")
_WORDS = re.compile(r"[\wÁÉÍÓÚÜÑáéíóúüñ]+", re.UNICODE)
_SPANISH_WORDS = frozenset(
    _WORDS.findall(
        "el la los las un una unos unas de del al que para por con sin entre desde hasta "
        "está están esta estas este estos eso esto es son soy somos eres estoy fue eran "
        "tengo tienes tiene tenemos había hay sí no aquí allí hola españa "
        "cuando donde como porque aunque después antes todavía pero también muy más menos "
        "gracias buenos buenas días tarde noche mañana vosotros vosotras vuestro vuestra "
        "casa calle tiempo agua voz leer otra vez necesito puedes puedes sería escuchar"
    )
)
_ENGLISH_WORDS = frozenset(
    _WORDS.findall(
        "the and for with from this that have has was were are you your our they their "
        "what when where because before after while can could would should about there "
        "then again please read listen message next previous now time no"
    )
)
_STRONG_SPANISH_WORDS = frozenset({"hola", "gracias", "españa", "vosotros", "vosotras"})


@dataclass(frozen=True, slots=True)
class SpeechUnit:
    index: int
    paragraph: int
    language: str
    text: str


def _inline_text(token: Token) -> str:
    """Use parsed Markdown labels while omitting styling and link destinations."""
    parts: list[str] = []
    for child in token.children or []:
        if child.type in {"text", "code_inline"}:
            parts.append(child.content)
        elif child.type in {"softbreak", "hardbreak"}:
            parts.append(" ")
        elif child.type == "image":
            parts.append(child.content)
    return re.sub(r"\s+", " ", "".join(parts)).strip()


def markdown_paragraphs(markdown: str) -> list[str]:
    """Keep prose and table header/value pairs; omit fenced and block code."""
    tokens = _MARKDOWN.parse(markdown)
    paragraphs: list[str] = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token.type == "table_open":
            rows: list[list[str]] = []
            row: list[str] | None = None
            index += 1
            while index < len(tokens) and tokens[index].type != "table_close":
                current = tokens[index]
                if current.type == "tr_open":
                    row = []
                elif current.type == "inline" and row is not None:
                    row.append(_inline_text(current))
                elif current.type == "tr_close" and row is not None:
                    rows.append(row)
                    row = None
                index += 1
            if rows:
                headers = rows[0]
                if len(rows) == 1:
                    paragraphs.append(". ".join(value for value in headers if value))
                else:
                    for values in rows[1:]:
                        cells = [
                            f"{headers[column]}: {value}"
                            if column < len(headers) and headers[column]
                            else value
                            for column, value in enumerate(values)
                            if value
                        ]
                        if cells:
                            paragraphs.append(". ".join(cells) + ".")
        elif token.type == "inline":
            prose = _inline_text(token)
            if prose:
                paragraphs.append(prose)
        index += 1
    return paragraphs


def detect_language(paragraph: str, mode: str) -> str:
    if mode in {"en", "es"}:
        return mode
    if mode != "auto":
        raise ValueError("language_mode must be auto, en, or es")
    words = [word.lower() for word in _WORDS.findall(paragraph)]
    spanish_score = sum(word in _SPANISH_WORDS for word in words)
    english_score = sum(word in _ENGLISH_WORDS for word in words)
    spanish_score += sum(char in "¿¡ñáéíóúü" for char in paragraph.lower())
    strong_spanish = any(word in _STRONG_SPANISH_WORDS for word in words)
    return (
        "es" if spanish_score > english_score and (spanish_score >= 2 or strong_spanish) else "en"
    )


def _bounded_pieces(sentence: str, limit: int = MAX_UNIT_CHARS) -> list[str]:
    """Split unpunctuated input by words and finally by characters."""
    pieces: list[str] = []
    current = ""
    for word in sentence.split():
        while len(word) > limit:
            if current:
                pieces.append(current)
                current = ""
            pieces.append(word[:limit])
            word = word[limit:]
        if not word:
            continue
        if current and len(current) + len(word) + 1 > limit:
            pieces.append(current)
            current = ""
        current = f"{current} {word}" if current else word
    if current:
        pieces.append(current)
    return pieces


def prepare_speech_units(markdown: str, language_mode: str = "auto") -> list[SpeechUnit]:
    if not markdown.strip():
        raise ValueError("Read-aloud text is empty")
    if len(markdown) > MAX_MESSAGE_CHARS:
        raise ValueError(f"Read-aloud text exceeds {MAX_MESSAGE_CHARS:,} characters")
    units: list[SpeechUnit] = []
    for paragraph_number, paragraph in enumerate(markdown_paragraphs(markdown)):
        language = detect_language(paragraph, language_mode)
        sentences = [part.strip() for part in _SENTENCE_BREAK.split(paragraph) if part.strip()]
        if not units and sentences:
            opening = _bounded_pieces(sentences[0], 120)[0]
            units.append(SpeechUnit(0, paragraph_number, language, opening))
            remainder = sentences[0][len(opening) :].strip()
            sentences = ([remainder] if remainder else []) + sentences[1:]
        current = ""
        for sentence in sentences:
            for piece in _bounded_pieces(sentence):
                if current and len(current) + len(piece) + 1 > MAX_UNIT_CHARS:
                    units.append(SpeechUnit(len(units), paragraph_number, language, current))
                    current = ""
                current = f"{current} {piece}" if current else piece
        if current:
            units.append(SpeechUnit(len(units), paragraph_number, language, current))
    if not units:
        raise ValueError("The message has no prose to read aloud")
    return units
