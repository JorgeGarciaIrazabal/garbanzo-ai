"""Offline synthesis screening, never an Android tap-to-audible measurement.

Run through just read-aloud-eval or just read-aloud-eval-qwen. Each invocation
creates a fresh evidence directory. Audio is written incrementally to disk.
"""

import argparse
import hashlib
import importlib
import importlib.metadata
import json
import math
import os
import platform
import re
import resource
import sys
import threading
import time
import uuid
from pathlib import Path

ROOT = (
    Path(__file__).resolve().parents[2]
    if Path(__file__).resolve().parent.name == "read_aloud"
    else Path("/results")
)
CORPUS = Path(__file__).with_name("corpus.json")
POCKET_REFERENCE_VOICES = {
    "alba": "hf://kyutai/tts-voices/alba-mackenna/casual.wav",
    "lola": (
        "hf://kyutai/pocket-tts/common_voice_es_19762977-enhanced-v2.mp3"
        "@64ab7d24c479d736a83b8cc666c4a776fca30fda"
    ),
}
POCKET_CLONING_WEIGHTS = {
    "english_2026-04": (
        "hf://kyutai/pocket-tts/languages/english_2026-04/model.safetensors"
        "@39592ff23c9ef80098bb74895d104c26275fe2c9"
    ),
    "spanish_24l": (
        "hf://kyutai/pocket-tts/languages/spanish_24l/model.safetensors"
        "@39592ff23c9ef80098bb74895d104c26275fe2c9"
    ),
}


def gpu_vram_path():
    paths = sorted(Path("/sys/class/drm").glob("card*/device/mem_info_vram_used"))
    if len(paths) != 1:
        raise RuntimeError(f"Expected one AMD VRAM usage counter, found {len(paths)}")
    return paths[0]


def sha256(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def numeric_file(path):
    try:
        return int(Path(path).read_text())
    except (OSError, ValueError):
        return None


def percentile(values, fraction):
    if not values:
        raise ValueError("Cannot calculate a percentile without observations")
    return sorted(values)[math.ceil(len(values) * fraction) - 1]


def write_json(path, data):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(path)


def load_engine(args, metadata):
    torch = importlib.import_module("torch")
    torch.set_num_threads(args.threads)
    torch.manual_seed(20260920)
    metadata["torch"] = torch.__version__
    metadata["hip"] = torch.version.hip
    if args.candidate == "pocket":
        pocket = importlib.import_module("pocket_tts")
        utils = importlib.import_module("pocket_tts.utils.utils")
        language = "spanish_24l" if args.language != "en" else "english_2026-04"
        if args.pocket_voice_cloning:
            # Pocket catches every Hub error and silently loads its public
            # non-cloning bundle. Fetch explicitly so strict evaluation exposes
            # authentication, license and availability errors.
            utils.download_if_necessary(POCKET_CLONING_WEIGHTS[language])
        model = pocket.TTSModel.load_model(language=language)
        voice = "alba" if args.language == "en" else "lola"
        if args.pocket_voice_cloning:
            if not model.has_voice_cloning:
                raise RuntimeError(
                    "Authenticated Pocket weights were unavailable; refusing the public "
                    "non-cloning fallback"
                )
            voice_source = POCKET_REFERENCE_VOICES[voice]
            state = model.get_state_for_audio_prompt(voice_source)
        else:
            voice_source = utils.get_predefined_voice(language=language, name=voice)
            state = model.get_state_for_audio_prompt(voice)
        weights_source = (
            model.config.weights_path
            if model.has_voice_cloning
            else model.config.weights_path_without_voice_cloning
        )
        metadata.update(
            model=language,
            voice=voice,
            config=str(model.config),
            voice_cloning=model.has_voice_cloning,
            weights_source=weights_source,
            weights_sha256=sha256(utils.download_if_necessary(weights_source)),
            voice_source=voice_source,
            voice_sha256=sha256(utils.download_if_necessary(voice_source)),
        )
        return model.sample_rate, lambda text: model.generate_audio_stream(state, text)
    if args.candidate == "kokoro":
        sys.path.insert(0, str(ROOT / "backend"))
        service = importlib.import_module("app.services.tts_service")
        kokoro = importlib.import_module("kokoro")
        hub = importlib.import_module("huggingface_hub")
        revision = hub.model_info("hexgrad/Kokoro-82M").sha
        config = hub.hf_hub_download("hexgrad/Kokoro-82M", "config.json", revision=revision)
        weights = hub.hf_hub_download("hexgrad/Kokoro-82M", "kokoro-v1_0.pth", revision=revision)
        voice = "af_heart" if args.language == "en" else "ef_dora"
        voice_file = hub.hf_hub_download(
            "hexgrad/Kokoro-82M", f"voices/{voice}.pt", revision=revision
        )
        model = service.TTSService(kokoro.KModel(config=config, model=weights).eval().to("cpu"))
        pipeline = model._get_pipeline(voice[0])
        metadata.update(
            model="hexgrad/Kokoro-82M",
            revision=revision,
            voice=voice,
            weights_sha256=sha256(weights),
            config_sha256=sha256(config),
            voice_sha256=sha256(voice_file),
        )

        def generate(text):
            for result in pipeline(text, voice=voice_file, speed=1.0, model=model._model):
                if result.audio is not None:
                    yield result.audio

        return service.SAMPLE_RATE, generate

    if not torch.version.hip or not torch.cuda.is_available():
        raise RuntimeError("Qwen evaluation requires a working ROCm GPU; no CPU fallback")
    if args.math_attention:
        torch.backends.cuda.enable_flash_sdp(False)
        torch.backends.cuda.enable_mem_efficient_sdp(False)
        torch.backends.cuda.enable_math_sdp(True)
    torch.cuda.set_per_process_memory_fraction(
        16 * 1024**3 / torch.cuda.get_device_properties(0).total_memory
    )
    qwen = importlib.import_module("qwen_tts")
    hub = importlib.import_module("huggingface_hub")
    model_id = f"Qwen/Qwen3-TTS-12Hz-{args.candidate.removeprefix('qwen-')}-Base"
    revision = hub.model_info(model_id).sha
    model_path = hub.snapshot_download(model_id, revision=revision)
    model = qwen.Qwen3TTSModel.from_pretrained(
        model_path, device_map="cuda:0", dtype=torch.float16, attn_implementation="sdpa"
    )
    if args.trace_stages:
        talker_generate = model.model.generate
        decode = model.model.speech_tokenizer.decode

        def traced_generate(*args, **kwargs):
            print("Qwen talker begin", flush=True)
            value = talker_generate(*args, **kwargs)
            print("Qwen talker end", flush=True)
            return value

        def traced_decode(*args, **kwargs):
            print("Qwen decoder begin", flush=True)
            value = decode(*args, **kwargs)
            print("Qwen decoder end", flush=True)
            return value

        model.model.generate = traced_generate
        model.model.speech_tokenizer.decode = traced_decode
    reference = Path("/results/references") / f"{args.language}.wav"
    transcript = reference.with_suffix(".txt")
    if not reference.is_file() or not transcript.is_file():
        raise FileNotFoundError(
            f"Prepare a reference clip and transcript: {reference}, {transcript}"
        )
    reference_text = transcript.read_text().strip()
    if reference_text in json.loads(CORPUS.read_text())[args.language]:
        raise ValueError("Reference transcript must be outside the listening corpus")
    prompt = model.create_voice_clone_prompt(
        ref_audio=str(reference), ref_text=reference_text, x_vector_only_mode=False
    )
    metadata.update(
        model=model_id,
        revision=revision,
        voice_file=str(reference),
        voice_sha256=sha256(reference),
        conditioning="full_reference",
        reference_text=reference_text,
        device=torch.cuda.get_device_name(0),
        incremental_api=False,
    )

    def generate(text):
        wavs, rate = model.generate_voice_clone(
            text=text,
            language="English" if args.language == "en" else "Spanish",
            voice_clone_prompt=prompt,
            max_new_tokens=1024,
        )
        if rate != 24000:
            raise RuntimeError(f"Unexpected Qwen sample rate: {rate}")
        yield wavs[0]

    return 24000, generate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", choices=["kokoro", "pocket", "qwen-1.7B", "qwen-0.6B"])
    parser.add_argument("language", choices=["en", "es", "mixed"])
    parser.add_argument("--output", type=Path, default=ROOT / ".ai/local/read-aloud")
    parser.add_argument("--run-id")
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--stall-seconds", type=float, default=15)
    parser.add_argument("--math-attention", action="store_true")
    parser.add_argument("--trace-stages", action="store_true")
    parser.add_argument(
        "--pocket-voice-cloning",
        action="store_true",
        help="Require Pocket's authenticated cloning weights and raw reference voice",
    )
    args = parser.parse_args()
    if args.pocket_voice_cloning and args.candidate != "pocket":
        parser.error("--pocket-voice-cloning is only valid for the Pocket candidate")
    if args.limit < 1 or args.threads < 1 or args.stall_seconds <= 0:
        parser.error("limit, threads and stall-seconds must be positive")
    if args.run_id is not None and not re.fullmatch(r"[a-z0-9-]+", args.run_id):
        parser.error("run-id must contain only lowercase letters, digits and hyphens")
    output = (
        args.output / f"{args.candidate}-{args.language}-{args.run_id or uuid.uuid4().hex[:10]}"
    )
    output.mkdir(parents=True)
    metadata = {
        "candidate": args.candidate,
        "language": args.language,
        "host": platform.platform(),
        "threads": args.threads,
        "corpus_sha256": hashlib.sha256(CORPUS.read_bytes()).hexdigest(),
        "measurement": "server PCM availability; excludes encoding, network and player",
        "miopen_find_mode": os.environ.get("MIOPEN_FIND_MODE"),
        "runtime_image": os.environ.get("READ_ALOUD_IMAGE"),
        "math_attention": args.math_attention,
        "status": "loading",
        "samples": [],
    }
    report = output / "report.json"
    write_json(report, metadata)
    print(output, flush=True)
    # Cold model downloads are setup work, not a stalled warm synthesis unit.
    deadline = [time.monotonic() + 3600]
    finished = threading.Event()
    try:
        gpu_path = gpu_vram_path() if args.candidate.startswith("qwen") else None
        gpu_start = numeric_file(gpu_path) if gpu_path else None
        if gpu_path and gpu_start is None:
            raise RuntimeError(f"Cannot read AMD VRAM usage counter: {gpu_path}")
    except BaseException as exc:
        metadata.update(status="failed", error=f"{type(exc).__name__}: {exc}")
        write_json(report, metadata)
        raise
    gpu_peak = [gpu_start]

    def watchdog():
        while not finished.wait(0.25):
            if gpu_path:
                current_gpu = numeric_file(gpu_path)
                if current_gpu is None:
                    metadata.update(status="failed", error="AMD VRAM usage counter vanished")
                    write_json(report, metadata)
                    os._exit(125)
                gpu_peak[0] = max(gpu_peak[0], current_gpu)
            if time.monotonic() > deadline[0]:
                metadata.update(status="failed", error="No synthesis progress within deadline")
                write_json(report, metadata)
                os._exit(124)

    threading.Thread(target=watchdog, daemon=True).start()
    try:
        sf = importlib.import_module("soundfile")
        torch = importlib.import_module("torch")
        rate, generate = load_engine(args, metadata)
        metadata["packages"] = {
            d.metadata["Name"]: d.version for d in importlib.metadata.distributions()
        }
        metadata["sample_rate"] = rate
        passages = json.loads(CORPUS.read_text())[args.language][: args.limit]
        metadata["status"] = "warming"
        write_json(report, metadata)
        deadline[0] = time.monotonic() + 300
        warm_start = time.monotonic()
        # Warm at the same text shape as the measured passage. ROCm kernels can
        # compile on first use for a longer sentence after a tiny greeting.
        for _ in generate(passages[0]):
            deadline[0] = time.monotonic() + 300
        metadata["warmup_seconds"] = time.monotonic() - warm_start
        metadata["status"] = "running"
        for index, passage in enumerate(passages):
            start = time.monotonic()
            deadline[0] = start + args.stall_seconds
            arrivals, count = [], 0
            audio_path = output / f"{index + 1:02}.wav"
            with sf.SoundFile(
                audio_path, "w", samplerate=rate, channels=1, subtype="PCM_16"
            ) as audio:
                for chunk in generate(passage):
                    if hasattr(chunk, "detach"):
                        chunk = chunk.detach().cpu().numpy()
                    if len(chunk) == 0:
                        continue
                    now = time.monotonic()
                    arrivals.append(now - start)
                    deadline[0] = now + args.stall_seconds
                    audio.write(chunk)
                    count += len(chunk)
            elapsed = time.monotonic() - start
            if not count:
                raise RuntimeError("Generator completed without audio")
            result = {
                "id": index + 1,
                "text": passage,
                "file": audio_path.name,
                "first_pcm_seconds": arrivals[0],
                "generation_seconds": elapsed,
                "audio_seconds": count / rate,
                "speed": count / rate / elapsed,
                "chunk_arrivals_seconds": arrivals,
                "peak_rss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * 1024,
            }
            result["gpu_vram_baseline_bytes"] = gpu_start
            result["gpu_vram_peak_bytes"] = gpu_peak[0]
            result["cgroup_memory_peak_bytes"] = numeric_file("/sys/fs/cgroup/memory.peak")
            if args.candidate.startswith("qwen"):
                result["peak_gpu_reserved_bytes"] = torch.cuda.max_memory_reserved()
            metadata["samples"].append(result)
            write_json(report, metadata)
            print(
                json.dumps(
                    {k: v for k, v in result.items() if k not in ("text", "chunk_arrivals_seconds")}
                ),
                flush=True,
            )
        metadata.update(
            status="completed",
            first_pcm_p95_seconds=percentile(
                [s["first_pcm_seconds"] for s in metadata["samples"]], 0.95
            ),
            aggregate_speed=sum(s["audio_seconds"] for s in metadata["samples"])
            / sum(s["generation_seconds"] for s in metadata["samples"]),
        )
    except BaseException as exc:
        metadata.update(
            status="interrupted" if isinstance(exc, KeyboardInterrupt) else "failed",
            error=f"{type(exc).__name__}: {exc}",
        )
        raise
    finally:
        finished.set()
        write_json(report, metadata)


if __name__ == "__main__":
    main()
