"""Checks that comparison passages and statistics keep the selection reproducible."""

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parent))
from benchmark import gpu_vram_path, percentile  # noqa: E402
from download_asset import download  # noqa: E402
from listening import score  # noqa: E402
from reference import REFERENCE_TEXT  # noqa: E402


class EvaluationCorpusTests(unittest.TestCase):
    def test_languages_have_equal_distinct_passages_with_safe_unit_length(self):
        corpus = json.loads(Path(__file__).with_name("corpus.json").read_text())
        for language in ("en", "es"):
            samples = corpus[language]
            self.assertEqual(len(samples), 20)
            self.assertEqual(len(set(samples)), 20)
            self.assertTrue(all(0 < len(text) <= 300 for text in samples))
        self.assertEqual(len(corpus["mixed"]), 4)
        for language in ("en", "es"):
            self.assertNotIn(REFERENCE_TEXT[language], corpus[language])

    def test_percentile_uses_observation_at_ceil_rank(self):
        self.assertEqual(percentile([4, 1, 3, 2, 5], 0.95), 5)
        self.assertEqual(percentile([4, 1, 3, 2, 5], 0.5), 3)
        with self.assertRaises(ValueError):
            percentile([], 0.95)

    def test_gpu_memory_gate_requires_one_readable_counter(self):
        with (
            patch("benchmark.Path.glob", return_value=[]),
            self.assertRaisesRegex(RuntimeError, "Expected one AMD VRAM"),
        ):
            gpu_vram_path()
        counter = Path("/sys/class/drm/card1/device/mem_info_vram_used")
        with patch("benchmark.Path.glob", return_value=[counter]):
            self.assertEqual(gpu_vram_path(), counter)

    def test_incomplete_blind_ratings_cannot_be_scored(self):
        with tempfile.TemporaryDirectory() as directory:
            mapping = Path(directory) / "mapping.json"
            ratings = Path(directory) / "ratings.json"
            mapping.write_text(json.dumps({"clip-1": {"candidate": "A", "language": "en"}}))
            ratings.write_text(json.dumps({"ratings": {"clip-1": {"naturalness": 5}}}))
            with self.assertRaisesRegex(ValueError, "1 clips lack complete"):
                score(mapping, ratings)

    def test_verified_asset_repairs_stale_snapshot_pointer(self):
        content = b"known model bytes"
        digest = hashlib.sha256(content).hexdigest()
        revision = "a" * 40
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            repository = cache / "hub/models--example--model"
            blob = repository / "blobs" / digest
            blob.parent.mkdir(parents=True)
            blob.write_bytes(content)
            pointer = repository / "snapshots" / revision / "model.safetensors"
            pointer.parent.mkdir(parents=True)
            pointer.symlink_to("../../blobs/nonexistent")
            head = Mock(
                headers={
                    "x-linked-size": str(len(content)),
                    "x-linked-etag": digest,
                    "x-repo-commit": revision,
                }
            )
            with patch("download_asset.requests.head", return_value=head):
                result = download("example/model", revision, "model.safetensors", cache, 1)
            self.assertEqual(result.resolve(), blob.resolve())


if __name__ == "__main__":
    unittest.main()
