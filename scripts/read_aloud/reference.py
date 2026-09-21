"""Prepare a Qwen voice reference whose transcript is outside the scoring corpus."""

import argparse
import json

from benchmark import ROOT, load_engine, sha256

REFERENCE_TEXT = {
    "en": "The little bookshop beside the river opens early on Saturdays, and visitors often stay for tea.",
    "es": "La librería que está junto al río abre temprano los sábados, y mucha gente se queda a tomar café.",
}


def main():
    import soundfile as sf

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", choices=["kokoro", "pocket"])
    parser.add_argument("language", choices=["en", "es"])
    parser.add_argument("--threads", type=int, default=4)
    args = parser.parse_args()
    metadata = {}
    rate, generate = load_engine(args, metadata)
    output = ROOT / ".ai/local/read-aloud/references"
    output.mkdir(parents=True, exist_ok=True)
    audio = output / f"{args.language}.wav"
    count = 0
    with sf.SoundFile(audio, "w", samplerate=rate, channels=1, subtype="PCM_16") as target:
        for chunk in generate(REFERENCE_TEXT[args.language]):
            if hasattr(chunk, "detach"):
                chunk = chunk.detach().cpu().numpy()
            target.write(chunk)
            count += len(chunk)
    if count < rate * 3:
        audio.unlink()
        raise RuntimeError("Reference clip must contain at least three seconds of speech")
    (output / f"{args.language}.txt").write_text(REFERENCE_TEXT[args.language] + "\n")
    metadata.update(
        candidate=args.candidate,
        language=args.language,
        sample_rate=rate,
        audio_seconds=count / rate,
        voice_sha256=sha256(audio),
    )
    (output / f"{args.language}.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(audio)


if __name__ == "__main__":
    main()
