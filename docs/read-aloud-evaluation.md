# Read-aloud model qualification

The user selected Pocket TTS int8 for the read-aloud prototype after listening
to a smaller set of blind examples; English passage 7 A was Pocket and was
preferred. The planned 80-clip numeric scoring exercise was explicitly waived
by the user. This records a product choice, not a measured claim of superior
mean quality in both languages. The remaining delivery gates are Android
tap-to-audible p95 at most five seconds, sustained generation at least 2×
playback, robust long-message and cancellation behaviour, and measured service
RAM at most 6 GiB. Pocket uses CPU, so the 16 GiB GPU allocation gate does not
apply to this selected configuration. A server PCM arrival time is **not** an
Android tap-to-audible result.

`scripts/read_aloud/corpus.json` contains the same 20 passages per language
for every candidate, plus four mixed-language passages. The reproducible
benchmarks are:

```sh
just read-aloud-eval kokoro en --limit 20
just read-aloud-eval kokoro es --limit 20
just read-aloud-hf-status
just read-aloud-eval pocket en --limit 20 --pocket-voice-cloning --pocket-quantize
just read-aloud-eval pocket es --limit 20 --pocket-voice-cloning --pocket-quantize
just read-aloud-eval-qwen-build
just read-aloud-eval-qwen-official-pull
just read-aloud-eval-qwen-official-build
just read-aloud-eval-qwen 0.6B en --limit 20
just read-aloud-eval-qwen 0.6B es --limit 20
just read-aloud-eval-qwen 1.7B en --limit 20
just read-aloud-eval-qwen 1.7B es --limit 20
QWEN_EVAL_IMAGE=garbanzo-read-aloud-eval:qwen-official just read-aloud-eval-qwen 1.7B en --limit 20
just read-aloud-eval-test
```

If the public model CDN is slow, `just read-aloud-asset <repo> <revision>
<filename>` downloads an asset in resumable parallel ranges to the local
Hugging Face cache and verifies its advertised SHA-256 before the benchmark
can use it. Use `just read-aloud-asset-qwen` for the Qwen container's cache.
The target revision must be a full commit hash; do not use `main`.

Each run writes WAV files and a `report.json` to a new directory under
`.ai/local/read-aloud/`. That directory stays private and untracked. Reports
capture exact corpus hash, package versions, pinned model and voice hashes,
reference transcript (Qwen), first PCM availability, synthesis speed, memory and
errors. A watchdog records a failed run if synthesis stops making progress for
15 seconds. A representative passage is synthesized before measurement so
first-use ROCm kernel compilation is excluded from the warm-server results.
Qwen runs in a separate ROCm image pinned by digest. Its default
voice reference for each language must be prepared as
`.ai/local/read-aloud/references/{en,es}.wav`; the report records the clip hash.
Prepare each reference with `just read-aloud-reference pocket en` and
`just read-aloud-reference pocket es` (or `kokoro` if Pocket fails). Each
reference speaks a dedicated line outside the scored corpus. The
benchmark uses Qwen's public high-level clone API, which returns an entire
unit. Its streaming behaviour has **not** been validated by an API name.

For this machine, the isolated ROCm image passed an FP16 GPU operation on the
Radeon 8060S under Ubuntu 25.10. Pocket English has publicly accessible model
weights and an Alba voice. The Pocket Spanish 24-layer checkpoint and Lola's
source recording are gated by Hugging Face. Authenticate locally with
`just read-aloud-hf-login`; never put a token in a command, report, or committed
file. The `--pocket-voice-cloning` benchmark option requires those authenticated
weights, conditions from Lola's raw recording, and refuses Pocket's automatic
public non-cloning fallback. It fetches the gated weights before model loading
so repository approval failures remain visible instead of being hidden by that
fallback. `--pocket-quantize` enables Pocket's supported dynamic int8 CPU mode;
the report records whether it was enabled. A candidate that cannot load its
intended Spanish voice is unqualified; the benchmark surfaces that access error.

Create an offline blind listening sheet from completed report paths with
`just read-aloud-listening <report.json> <report.json> ...`. It writes an HTML
sheet with randomly ordered clips and a private `mapping.json` alongside it.
The HTML exports ratings; calculate model means with
`just read-aloud-listening --score <mapping.json> <ratings.json>`. Keep the
mapping hidden until ratings are final.

Peak process RSS and PyTorch GPU reservation are diagnostic measurements.
The Qwen container also has a 6 GiB cgroup limit and records cgroup peak memory;
the benchmark requires an AMD sysfs VRAM counter and samples its use against
a pre-run baseline. Neither
metric certifies total service/device allocation if another GPU process changes
during the run, so record its load separately before applying the 16 GiB gate.

The original protocol requested human blind scores for naturalness,
pronunciation, Spain accent and consistency. The user chose Pocket without
completing that sheet, so no numeric quality mean should be reported. Measure
the actual Android tap-to-audible path over a controlled and public connection,
including encoding, HTTPS, player buffering and UI scheduling. Test 5,000-,
20,000- and 100,000-character messages, cancellation, backgrounding, network
loss, worker stalls and segment ordering before selecting it for delivery.

## Measurements on this machine

These are warm **server PCM** results for 20 passages per language, with four
CPU threads while the normal app services were running. They exclude encoding,
network and Android player startup. RSS is the highest measured process RSS.

| Candidate | Language | p95 first PCM | Audio generated per second | Peak RSS |
| --- | --- | ---: | ---: | ---: |
| Kokoro | English | 0.97 s | 7.44× | 2,048 MiB |
| Kokoro | Spanish | 0.92 s | 7.47× | 1,824 MiB |
| Pocket TTS, public FP32 | English | 0.10 s | 3.93× | 973 MiB |
| Pocket TTS 24-layer, public FP32 | Spanish | 0.38 s | 1.23× | 2,275 MiB |
| Pocket TTS int8, raw Alba reference | English | 0.039 s | 8.92× | 1,032 MiB |
| Pocket TTS 24-layer int8, raw Lola reference | Spanish | 0.094 s | 3.67× | 2,271 MiB |

The initial public FP32 Pocket Spanish configuration misses the required 2×
sustained rate. After authenticated access was approved, Pocket's
cloning-capable checkpoint and raw Lola source were evaluated. Dynamic int8
quantization raises Spanish to 3.67× and English to 8.92× across 20 passages,
with process RSS below 2.3 GiB and incremental PCM delivery. That configuration
passes the synthesis speed screen and advances to blind listening; whole-service
RAM has not yet been measured against the 6 GiB ceiling. The isolated
community ROCm/PyTorch image executed an FP16 tensor operation, but Qwen 0.6B
crashed during talker generation in three attempts, including MIOpen full-search
and math-only attention variants.
It also crashed with an HSA hardware exception in [AMD's validated PyTorch
image](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installryz/native_linux/install-pytorch.html).
The supervised runner records exit 139 as `worker_crashed`. Qwen 1.7B completed
its talker and decoder warm-up but then produced no PCM for 15 seconds on a
measured passage in both images. The representative-passage warm-up in the
validated image did not resolve the stall. The high-level Qwen API returns a
whole waveform; actual incremental output was not demonstrated.

Pocket int8 is selected for implementation by the user. The initial voice
catalog contains the tested Alba (English) and Lola (Spain Spanish) references;
a second curated voice per language still needs a pinned asset and evaluation.
The production worker's Pocket package revision is pinned. Its package config
pins English `english_2026-04` weights at
`19f95fe2df36e79fbd9f10008595cc4c977a0fcc` and Spain Spanish
`spanish_24l` weights at `39592ff23c9ef80098bb74895d104c26275fe2c9`.
The full 80-clip quality comparison was waived. The local Pixel 9 preview
played a real message and exercised Pause, Resume, foreground transitions,
paragraph navigation, speed, and Stop. The later compact message-local
controls were also exercised on that device. This proves the local Android
path works, but it is not a controlled p95 tap-to-audible measurement or a
test through the public HTTPS connection. The prior long-message test of the
old installed app coincided with a host reboot whose cause is unknown.

An uncached local session benchmark advanced the reported playback position
as audio was generated, so it measured uninterrupted long synthesis without
waiting for hours of real-time listening. It used the warm int8 worker and
one continuous 128 kbps MP3 encoder. These are **server first-byte** and
synthesis results, not Android acoustic measurements:

| Text | Language | First MP3 byte | Total synthesis | Audio duration | Rate | Segments |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 5,000 characters | English | 0.186 s | 31.2 s | 317.6 s | 10.18× | 21 |
| 5,000 characters | Spanish | 0.213 s | 44.0 s | 195.0 s | 4.43× | 21 |
| 20,000 characters | English | 0.119 s | 124.5 s | 1269.9 s | 10.20× | 82 |
| 100,000 characters | English | 0.236 s | 680.0 s | 6361.8 s | 9.36× | 407 |

The 100,000-character run completed within a 6 GiB worker cgroup, reported
407 segments, and emitted 101.8 MB of MP3. Its cgroup memory
reached the exact 6 GiB limit near completion, although the worker remained
ready and synthesized another English and Spanish sample afterward. A later
worker change reclaims short-lived CPU allocations after each unit; a shorter
follow-up run held memory near 1.7 GiB, but the 100,000-character case has not
been repeated with that change. Production deployment still needs the
controlled Android p95, public-connection run, and accepted resource margin.
