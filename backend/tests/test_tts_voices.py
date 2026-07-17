"""Voice catalog + language→voice resolution (idea 13.3).

Pure-function tests — no Kokoro model load involved.
"""

from app.services.tts_service import (
    _VOICES,
    default_voice_for_language,
    resolve_voice_for_language,
)

# KPipeline derives its lang_code from the voice ID's first letter — each
# catalog entry's declared ISO code must agree with its ID prefix, or the
# voice would synthesize with the wrong G2P.
_PREFIX_TO_ISO = {
    "a": "en",  # US English
    "b": "en",  # British English
    "e": "es",
    "f": "fr",
    "h": "hi",
    "i": "it",
    "p": "pt",  # Brazilian Portuguese
}


class TestVoiceCatalog:
    def test_lang_code_matches_voice_id_prefix(self):
        for v in _VOICES:
            assert v.lang_code == _PREFIX_TO_ISO[v.id[0]], v.id

    def test_ids_are_unique(self):
        ids = [v.id for v in _VOICES]
        assert len(ids) == len(set(ids))

    def test_every_supported_language_has_a_default(self):
        for iso in set(_PREFIX_TO_ISO.values()):
            assert default_voice_for_language(iso) is not None, iso


class TestDefaultVoiceForLanguage:
    def test_picks_first_catalog_entry_for_the_language(self):
        assert default_voice_for_language("es") == "ef_dora"
        assert default_voice_for_language("en") == "af_heart"

    def test_ignores_region_subtag_and_case(self):
        assert default_voice_for_language("es-MX") == "ef_dora"
        assert default_voice_for_language("PT") == "pf_dora"

    def test_unknown_language_returns_none(self):
        assert default_voice_for_language("ja") is None


class TestResolveVoiceForLanguage:
    def test_no_language_keeps_voice(self):
        assert resolve_voice_for_language("af_heart", None) == "af_heart"
        assert resolve_voice_for_language("af_heart", "") == "af_heart"

    def test_auto_keeps_voice(self):
        assert resolve_voice_for_language("af_heart", "auto") == "af_heart"

    def test_mismatched_voice_swaps_to_language_default(self):
        assert resolve_voice_for_language("af_heart", "es") == "ef_dora"

    def test_pinned_voice_already_speaking_the_language_wins(self):
        # A user-chosen Spanish voice must not be stomped by the es default.
        assert resolve_voice_for_language("em_alex", "es") == "em_alex"

    def test_unsupported_language_keeps_voice(self):
        # Bad/exotic detection degrades to today's behavior, never an error.
        assert resolve_voice_for_language("af_heart", "ja") == "af_heart"

    def test_unknown_voice_id_still_resolves_by_language(self):
        assert resolve_voice_for_language("custom_voice", "fr") == "ff_siwis"
