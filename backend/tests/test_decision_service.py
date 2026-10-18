"""System One's typed contract, bounded inputs and optional startup validation."""

import asyncio
import json
from unittest.mock import AsyncMock, patch

import httpx
import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.services.decision_service import (
    MAX_REQUEST_BYTES,
    DecisionError,
    DecisionService,
    validate_decision_config,
)

pytestmark = pytest.mark.asyncio


def _settings(**kwargs):
    return Settings(
        _env_file=None,
        ollama_base_url="http://ollama.test",
        topic_context_privacy_mode="cloud_allowed",
        **kwargs,
    )


def _response(value=0.7, **kwargs):
    return {
        "model": "clef:cloud",
        "answers": {"relevant": {"type": "noul", "noul": value}},
        "usage": {"input_tokens": 12, "output_tokens": 1},
        **kwargs,
    }


def _service(handler, **kwargs):
    return DecisionService(_settings(**kwargs), transport=httpx.MockTransport(handler))


async def test_typed_noul_request_and_response():
    def handler(request):
        assert request.url.path == "/v1/systemone"
        assert json.loads(request.content) == {
            "model": "clef:cloud",
            "state": {"message": "hello"},
            "questions": {"relevant": {"type": "noul", "instructions": "Is it relevant?"}},
        }
        assert "authorization" not in request.headers
        return httpx.Response(200, json=_response())

    result = await _service(handler).probabilities(
        state={"message": "hello"}, questions={"relevant": "Is it relevant?"}
    )
    assert result == {"relevant": 0.7}


async def test_cloud_proxy_canonical_name_matches_exact_cloud_alias():
    service = _service(lambda _: httpx.Response(200, json=_response(model="clef")))
    assert await service.probabilities(
        state="hello", questions={"relevant": "Is it relevant?"}
    ) == {"relevant": 0.7}


@pytest.mark.parametrize(
    "value", [True, False, "0.7", None, [], {}, -0.01, 1.01, float("nan"), float("inf"), 10**400]
)
async def test_rejects_invalid_probabilities(value):
    service = _service(lambda _: httpx.Response(200, content=json.dumps(_response(value))))
    with pytest.raises(DecisionError, match="finite numbers"):
        await service.probabilities(state="hello", questions={"relevant": "Is it relevant?"})


@pytest.mark.parametrize(
    "response, message",
    [
        (_response(model="another:cloud"), "model"),
        (_response(model=[]), "model"),
        (_response(usage=None), "token usage"),
        (_response(usage={"input_tokens": True, "output_tokens": 1}), "token usage"),
        (_response(answers={}), "question IDs"),
        (_response(answers={"extra": {"type": "noul", "noul": 1}}), "question IDs"),
        (_response(answers={"relevant": {"type": "choice", "noul": 1}}), "noul answers"),
        (_response(answers={"relevant": None}), "noul answers"),
        (_response(answers={"relevant": {"type": "noul"}}), "finite numbers"),
        ([], "JSON object"),
    ],
)
async def test_rejects_wrong_response_contract(response, message):
    service = _service(lambda _: httpx.Response(200, json=response))
    with pytest.raises(DecisionError, match=message):
        await service.probabilities(state="hello", questions={"relevant": "Is it relevant?"})


@pytest.mark.parametrize("body", ["not JSON", '{"model":"clef:cloud","model":"other"}'])
async def test_rejects_invalid_json_or_duplicate_fields(body):
    service = _service(lambda _: httpx.Response(200, content=body))
    with pytest.raises(DecisionError, match="invalid JSON"):
        await service.probabilities(state="hello", questions={"relevant": "Is it relevant?"})


@pytest.mark.parametrize("status", [401, 402, 404, 413, 500])
async def test_http_failures_are_explicit_and_do_not_expose_state(status):
    service = _service(lambda _: httpx.Response(status, json={"error": "private-state-or-auth"}))
    with pytest.raises(DecisionError, match=f"HTTP {status}") as error:
        await service.probabilities(state="private-state-or-auth", questions={"q": "Question?"})
    assert "private-state-or-auth" not in str(error.value)


async def test_transport_failure_is_explicit_and_redacted():
    def handler(request):
        raise httpx.ReadTimeout("private-state-or-auth", request=request)

    with pytest.raises(DecisionError, match="timed out") as error:
        await _service(handler).probabilities(state="private", questions={"q": "Question?"})
    assert "private-state-or-auth" not in str(error.value)


async def test_total_request_deadline_is_enforced():
    async def handler(_):
        await asyncio.Event().wait()
        pytest.fail("The request should have timed out")

    with pytest.raises(DecisionError, match="timed out"):
        await _service(handler, decision_timeout_seconds=0.01).probabilities(
            state="hello", questions={"q": "Question?"}
        )


@pytest.mark.parametrize(
    "state,questions",
    [
        ("", {"q": "Question?"}),
        ([], {"q": "Question?"}),
        ("hello", {}),
        ("hello", {str(i): "Question?" for i in range(33)}),
        ("hello", {"invalid id": "Question?"}),
        ("hello", {"q": ""}),
        ("hello", {"q": True}),
        ({"invalid": float("nan")}, {"q": "Question?"}),
        ("😀" * (MAX_REQUEST_BYTES // 4), {"q": "Question?"}),
        ("a" * MAX_REQUEST_BYTES, {"q": "Question?"}),
    ],
)
async def test_invalid_or_oversized_request_never_reaches_network(state, questions):
    def handler(_):
        pytest.fail("Invalid input reached the server")

    with pytest.raises(DecisionError):
        await _service(handler).probabilities(state=state, questions=questions)


async def test_disabled_startup_does_not_contact_ollama():
    with patch.object(DecisionService, "validate", new_callable=AsyncMock) as validate:
        await validate_decision_config(_settings())
    validate.assert_not_awaited()


@pytest.mark.parametrize("flag", ["room_decisions_enabled", "topic_decisions_enabled"])
async def test_enabled_startup_validates_dependency(flag):
    with patch.object(DecisionService, "validate", new_callable=AsyncMock) as validate:
        await validate_decision_config(_settings(**{flag: True}))
    validate.assert_awaited_once()


@pytest.mark.parametrize("version", ["0.40.4", "0.35.1", "bad", None, 42])
async def test_cloud_startup_rejects_unsupported_version(version):
    service = _service(lambda _: httpx.Response(200, json={"version": version}))
    with pytest.raises(DecisionError, match="version|requires Ollama"):
        await service.validate()


@pytest.mark.parametrize("capabilities", [[], ["completion", "tools"], None, "decision", [1]])
async def test_startup_rejects_model_without_decision_capability(capabilities):
    def handler(request):
        return httpx.Response(
            200,
            json={"version": "0.40.5"}
            if request.url.path == "/api/version"
            else {"capabilities": capabilities},
        )

    with pytest.raises(DecisionError, match="decision capability"):
        await _service(handler).validate()


async def test_startup_reports_missing_required_model():
    def handler(request):
        if request.url.path == "/api/version":
            return httpx.Response(200, json={"version": "0.40.5"})
        assert json.loads(request.content) == {"model": "clef:cloud"}
        return httpx.Response(404, json={"error": "model does not exist"})

    with pytest.raises(DecisionError, match="HTTP 404"):
        await _service(handler).validate()


@pytest.mark.parametrize("model,version", [("clef:cloud", "0.40.5"), ("clef", "0.35.1")])
async def test_startup_accepts_supported_decision_models(model, version):
    def handler(request):
        return httpx.Response(
            200,
            json={"version": version}
            if request.url.path == "/api/version"
            else {"capabilities": ["vision", "decision"]},
        )

    await _service(handler, decision_model=model).validate()


@pytest.mark.parametrize("value", [0, -1, float("inf"), float("nan")])
async def test_decision_timeout_must_be_positive_and_finite(value):
    with pytest.raises(ValidationError):
        _settings(decision_timeout_seconds=value)


@pytest.mark.parametrize("model", ["clef:27b-cloud", "clef:1017-cloud"])
async def test_cloud_alias_needs_cloud_proxy_version(model):
    with pytest.raises(DecisionError, match="requires Ollama"):
        await _service(
            lambda _: httpx.Response(200, json={"version": "0.35.1"}), decision_model=model
        ).validate()


async def test_custom_alias_remote_metadata_cannot_bypass_local_privacy():
    def handler(request):
        return httpx.Response(
            200,
            json={"version": "0.40.6"}
            if request.url.path == "/api/version"
            else {
                "capabilities": ["decision"],
                "remote_model": "clef",
                "remote_host": "https://ollama.com",
            },
        )

    settings = Settings(
        _env_file=None,
        ollama_base_url="http://localhost:11434",
        decision_model="private-alias",
        topic_decisions_enabled=True,
        topic_context_privacy_mode="local_only",
    )
    with pytest.raises(DecisionError, match="cloud_allowed"):
        await DecisionService(settings, transport=httpx.MockTransport(handler)).validate()


@pytest.mark.parametrize("local_weights", [True, False])
async def test_local_privacy_requires_positive_local_weights_not_just_an_alias(local_weights):
    metadata = {"capabilities": ["decision"]}
    if local_weights:
        metadata.update(details={"format": "gguf"}, model_info={"general.architecture": "qwen3"})

    def handler(request):
        return httpx.Response(
            200, json={"version": "0.40.6"} if request.url.path == "/api/version" else metadata
        )

    settings = Settings(
        _env_file=None,
        ollama_base_url="http://localhost:11434",
        decision_model="renamed-model",
        topic_decisions_enabled=True,
        topic_context_privacy_mode="local_only",
    )
    service = DecisionService(settings, transport=httpx.MockTransport(handler))
    if local_weights:
        await service.validate()
    else:
        with pytest.raises(DecisionError, match="local model metadata"):
            await service.validate()
