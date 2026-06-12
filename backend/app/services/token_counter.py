"""Token counting for context-window budgeting.

Ollama exposes no tokenize endpoint, so exact counts only exist after a
generation (``prompt_eval_count``). This service provides the best
*pre-send* estimate available: tiktoken's BPE when importable (within
~10-15% of llama-family tokenizers), otherwise a word/char heuristic.
Counts from here must be treated as estimates and reconciled against the
provider-reported counts when those arrive.
"""

import logging
import threading
from typing import Any

logger = logging.getLogger(__name__)

# Chat templates wrap every message in role/separator tokens; 4 is the
# conventional per-message overhead (matches OpenAI's cookbook numbers and
# is close enough for llama-family templates).
_PER_MESSAGE_OVERHEAD = 4


class TokenCounter:
    """Estimates token counts for text and chat messages."""

    def __init__(self) -> None:
        self._encoder: Any | None = None
        self._encoder_failed = False
        self._lock = threading.Lock()

    def _get_encoder(self) -> Any | None:
        if self._encoder is not None or self._encoder_failed:
            return self._encoder
        with self._lock:
            if self._encoder is not None or self._encoder_failed:
                return self._encoder
            try:
                import tiktoken

                # cl100k_base is the closest widely-cached vocabulary to the
                # llama-family tokenizers Ollama models use. tiktoken fetches
                # the BPE file over the network on first use; in an offline
                # deployment that raises and we fall back to the heuristic.
                self._encoder = tiktoken.get_encoding("cl100k_base")
            except Exception as e:
                logger.info(
                    "tiktoken unavailable (%s); falling back to heuristic token counting",
                    e,
                )
                self._encoder_failed = True
        return self._encoder

    def count_text(self, text: str) -> int:
        """Estimate the number of tokens in ``text``."""
        if not text:
            return 0
        encoder = self._get_encoder()
        if encoder is not None:
            try:
                return len(encoder.encode(text, disallowed_special=()))
            except Exception:
                pass
        return self._heuristic(text)

    @staticmethod
    def _heuristic(text: str) -> int:
        # English prose averages ~1.3 tokens/word; code and dense text run
        # closer to 1 token / 4 chars. Take the max so neither shape is
        # underestimated (under-counting risks blowing the context window).
        words = len(text.split())
        return max(int(words * 1.3), len(text) // 4, 1)

    def count_message(self, content: str) -> int:
        """Estimate tokens for one chat message including template overhead."""
        return self.count_text(content) + _PER_MESSAGE_OVERHEAD

    def count_messages(self, contents: list[str]) -> int:
        """Estimate tokens for a list of message contents."""
        return sum(self.count_message(c) for c in contents)


_default_counter: TokenCounter | None = None


def get_token_counter() -> TokenCounter:
    """Process-wide singleton (the encoder is expensive to construct)."""
    global _default_counter
    if _default_counter is None:
        _default_counter = TokenCounter()
    return _default_counter
