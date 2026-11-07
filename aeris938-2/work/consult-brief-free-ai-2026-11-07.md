# Brief: cull the genuinely-free AI tools (worldwide) for AERIS Music

## Context

K asked AR to "search the world for AI that is actually free, then cull it".
Hard rule: **FREE only** — no paid tier, no trial that expires into a bill, no
credit card. The account makes Thai music content (ลูกทุ่ง / เพื่อชีวิต / คาราโอเกะ
/ เพลงเศร้า) and posts it to Facebook Page, TikTok, YouTube, plus a Shopee
affiliate link. One operator (K) taps; AR runs unattended on a small Linux box
and on GitHub Actions (free minutes).

## What we already run for free (verified)

- **Piper** (rhasspy/piper, offline ONNX, Thai voice `th_TH-tsync2`) — syllable
  TTS for the song engine. Offline + deterministic.
- **Pollinations** (`image.pollinations.ai`) — cover art, no key, no login.
- **edge-tts** (rany2/edge-tts) — just installed and verified: `th-TH-NiwatNeural`
  and `th-TH-PremwadeeNeural` synthesise Thai MP3, no key. (Unofficial wrapper
  over Microsoft Edge's online voices.)

## Candidates found so far (with evidence)

LLM inference (free API or free local): Groq (free tier, RPM/RPD caps), Cerebras
(free tier), Google AI Studio / Gemini (free tier, "generous limits"), Mistral
(free tier), OpenRouter `:free` models (daily cap), Cloudflare Workers AI
(10,000 Neurons/day free), Hugging Face Inference Providers (free monthly
credits; $0 tier is thin), plus local via Ollama / llama.cpp / vLLM (weights:
Qwen, Llama, Gemma, DeepSeek, Mistral, Phi — all free to download).

Image: Pollinations (in use), ComfyUI / SD WebUI / InvokeAI / diffusers (local,
free), Flux/SD open weights.

Voice/TTS: edge-tts (verified), Piper (in use), Kokoro (82M, Apache), F5-TTS,
fish-speech, Coqui (idiap fork).

Music: ACE-Step (open weights), Meta AudioCraft/MusicGen, Stable Audio Open.

ASR (for captions): Whisper, faster-whisper, whisper.cpp.

OCR (for reading screenshots): PaddleOCR, tesseract.

## What we want from you

1. Which of these are **actually free with no card and no expiring trial**, and
   which are "free" only until a bill appears? Name the traps.
2. For THIS use case — Thai music content, unattended automation, a small box —
   rank the top 5 tools to adopt next and say what each replaces or unlocks.
   Say which one first.
3. Where is free AI genuinely not good enough yet, so we should not waste time
   (e.g. Thai pronunciation, long-form video, licensed music)?
4. Anything obvious we have missed that is free and would help this workflow.
