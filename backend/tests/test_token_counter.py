"""Tests for TokenCounter — pre-send token estimation."""

from app.services.token_counter import TokenCounter, get_token_counter


class TestTokenCounter:
    def test_empty_text_is_zero(self):
        assert TokenCounter().count_text("") == 0

    def test_short_text_counts_at_least_one(self):
        assert TokenCounter().count_text("hi") >= 1

    def test_prose_count_is_plausible(self):
        counter = TokenCounter()
        text = "The quick brown fox jumps over the lazy dog. " * 20
        count = counter.count_text(text)
        words = len(text.split())
        # Whether via tiktoken or the heuristic, prose should land in
        # roughly 0.7–2 tokens per word.
        assert words * 0.7 <= count <= words * 2

    def test_longer_text_counts_more(self):
        counter = TokenCounter()
        short = counter.count_text("hello world")
        long = counter.count_text("hello world " * 100)
        assert long > short

    def test_message_adds_template_overhead(self):
        counter = TokenCounter()
        assert counter.count_message("hello") > counter.count_text("hello")

    def test_count_messages_sums_all(self):
        counter = TokenCounter()
        total = counter.count_messages(["hello", "world"])
        assert total == counter.count_message("hello") + counter.count_message("world")

    def test_heuristic_fallback_when_encoder_unavailable(self):
        counter = TokenCounter()
        counter._encoder_failed = True  # simulate offline / no tiktoken
        text = "some plain text that should still be counted"
        count = counter.count_text(text)
        assert count >= len(text) // 4

    def test_heuristic_code_density(self):
        # Dense code with few spaces should be driven by the char/4 floor.
        dense = "x" * 400
        assert TokenCounter._heuristic(dense) >= 100

    def test_singleton(self):
        assert get_token_counter() is get_token_counter()
