"""Strict, bounded client for Ollama's typed System One decision endpoint.

Noul scores are probabilities of the supplied yes/no criterion, not calibrated
confidence in the correctness of a downstream action. No chat-provider fallback
is allowed when the configured decision service fails.
"""

import asyncio
import json
import math
import re
from typing import Any

import httpx

from app.core.config import Settings, get_settings

MAX_REQUEST_BYTES = 32 * 1024
MAX_QUESTIONS = 32
DECISION_CAPABILITIES = frozenset({"decision", "systemone"})


def is_cloud_decision_model(model: str) -> bool:
    """Recognize both :cloud and official size/dated -cloud tag variants."""
    return "cloud" in model.casefold().partition(":")[2].split("-")


class DecisionError(RuntimeError):
    """The configured decision service could not produce a valid typed answer."""


def _json_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON field")
        result[key] = value
    return result


class DecisionService:
    def __init__(
        self,
        settings: Settings | None = None,
        *,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        settings = settings or get_settings()
        self.base_url = settings.ollama_base_url.rstrip("/")
        self.model = settings.decision_model
        self.timeout = settings.decision_timeout_seconds
        self._transport = transport
        self._topic_local_only = (
            settings.topic_decisions_enabled and settings.topic_context_privacy_mode == "local_only"
        )
        if not self.model.strip():
            raise DecisionError("DECISION_MODEL must be configured")

    async def _request(self, method: str, path: str, *, body: bytes | None = None) -> dict:
        # Apply a total deadline as well as HTTPX's individual socket deadlines.
        # Never include request state, response bodies, URLs or auth in errors.
        try:
            async with asyncio.timeout(self.timeout):
                async with httpx.AsyncClient(
                    timeout=self.timeout, transport=self._transport
                ) as client:
                    response = await client.request(
                        method,
                        self.base_url + path,
                        content=body,
                        headers={"Content-Type": "application/json"},
                    )
                    response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise DecisionError(
                f"Decision service {path} returned HTTP {exc.response.status_code}"
            ) from None
        except (httpx.HTTPError, TimeoutError):
            raise DecisionError(f"Decision service {path} request failed or timed out") from None
        try:
            data = json.loads(response.content, object_pairs_hook=_json_object)
        except (ValueError, UnicodeDecodeError):
            raise DecisionError(f"Decision service {path} returned invalid JSON") from None
        if not isinstance(data, dict):
            raise DecisionError(f"Decision service {path} must return a JSON object")
        return data

    async def probabilities(
        self, *, state: dict | str, questions: dict[str, str]
    ) -> dict[str, float]:
        if not isinstance(state, dict | str) or (isinstance(state, str) and not state.strip()):
            raise DecisionError("Decision state must be an object or nonempty string")
        if not isinstance(questions, dict) or not 1 <= len(questions) <= MAX_QUESTIONS:
            raise DecisionError(f"Decision requests require 1–{MAX_QUESTIONS} questions")
        for key, instructions in questions.items():
            if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,100}", key):
                raise DecisionError(
                    "Decision question IDs must be 1–100 ASCII identifier characters"
                )
            if not isinstance(instructions, str) or not instructions.strip():
                raise DecisionError("Decision questions require nonempty instructions")
        payload = {
            "model": self.model,
            "state": state,
            "questions": {
                key: {"type": "noul", "instructions": instructions}
                for key, instructions in questions.items()
            },
        }
        try:
            body = json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8")
        except (TypeError, ValueError, UnicodeError):
            raise DecisionError("Decision request must contain valid JSON data") from None
        if len(body) > MAX_REQUEST_BYTES:
            raise DecisionError(f"Decision request exceeds {MAX_REQUEST_BYTES} UTF-8 bytes")
        data = await self._request("POST", "/v1/systemone", body=body)
        # Ollama 0.40.6's cloud proxy returns the canonical hosted name:
        # request clef:cloud -> response clef. Accept that exact suffix
        # normalization, never an arbitrary family/prefix match.
        response_models = {self.model}
        if is_cloud_decision_model(self.model):
            response_models.add(self.model.removesuffix(":cloud").removesuffix("-cloud"))
        response_model = data.get("model")
        if not isinstance(response_model, str) or response_model not in response_models:
            raise DecisionError("Decision response model does not match the requested model")
        usage = data.get("usage")
        if not isinstance(usage, dict) or any(
            type(usage.get(key)) is not int or usage[key] < 0
            for key in ("input_tokens", "output_tokens")
        ):
            raise DecisionError("Decision response requires nonnegative integer token usage")
        answers = data.get("answers")
        if not isinstance(answers, dict) or answers.keys() != questions.keys():
            raise DecisionError("Decision response question IDs do not match the request")
        probabilities: dict[str, float] = {}
        for key, answer in answers.items():
            if not isinstance(answer, dict) or answer.get("type") != "noul":
                raise DecisionError("Decision response requires noul answers")
            value = answer.get("noul")
            if type(value) not in (int, float) or not 0 <= value <= 1 or not math.isfinite(value):
                raise DecisionError("Decision probabilities must be finite numbers from 0 to 1")
            probabilities[key] = float(value)
        return probabilities

    async def validate(self) -> None:
        version_data = await self._request("GET", "/api/version")
        version = version_data.get("version")
        match = (
            re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:[-+].*)?", version)
            if isinstance(version, str)
            else None
        )
        if match is None:
            raise DecisionError("Decision service returned an invalid Ollama version")
        minimum = (0, 40, 5) if is_cloud_decision_model(self.model) else (0, 35, 1)
        if tuple(int(part) for part in match.groups()) < minimum:
            raise DecisionError(
                "Decision service requires Ollama >= " + ".".join(map(str, minimum))
            )
        metadata = await self._request(
            "POST", "/api/show", body=json.dumps({"model": self.model}).encode()
        )
        remote = is_cloud_decision_model(self.model) or bool(
            metadata.get("remote_model") or metadata.get("remote_host")
        )
        if remote and tuple(int(part) for part in match.groups()) < (0, 40, 5):
            raise DecisionError("Cloud decisions require Ollama >= 0.40.5")
        if remote and self._topic_local_only:
            raise DecisionError(
                "Cloud topic decisions require cloud_allowed privacy or TOPIC_DECISIONS_ENABLED=false"
            )
        if self._topic_local_only:
            # A renamed cloud manifest need not retain a :cloud tag, and
            # cloud /api/show responses may omit remote_model/remote_host.
            # Require positive local-weight evidence instead of guessing.
            details = metadata.get("details")
            if (
                not isinstance(details, dict)
                or details.get("format") not in {"gguf", "safetensors", "mlx"}
                or not isinstance(metadata.get("model_info"), dict)
                or not metadata["model_info"]
            ):
                raise DecisionError(
                    "Local-only topic decisions require verified local model metadata"
                )
        capabilities = metadata.get("capabilities")
        if (
            not isinstance(capabilities, list)
            or any(not isinstance(value, str) for value in capabilities)
            or not DECISION_CAPABILITIES.intersection(capabilities)
        ):
            raise DecisionError("DECISION_MODEL must advertise the decision capability")


def get_decision_service() -> DecisionService:
    return DecisionService(get_settings())


async def validate_decision_config(settings: Settings) -> None:
    """Disabled optional decision features require no server or installed model."""
    if settings.room_decisions_enabled or settings.topic_decisions_enabled:
        await DecisionService(settings).validate()
