# Hapo Ndani Android Local LLM Baseline

Date: 2026-05-08

## Decision

Android should use Gemma 3n E2B IT through LiteRT-LM as the broad-support local conversation baseline candidate on Android phones.

Gemma 3n E4B remains an optional high-quality mode for stronger phones. Generic fallback models are not accepted as the human conversation baseline unless they pass the same conversation suite and are labeled clearly.

## Device Rule

- Broad Android target, 8 GB RAM or higher: eligible for Gemma 3n E2B LiteRT-LM runtime testing.
- 6 GB RAM devices: test-only candidate until first-response speed, memory pressure, and repeated conversation stability pass.
- 4 GB RAM, Android Go, or weak budget devices: Home, Chat intake, Journal, local memory, and capture-first behavior only.
- No hosted inference, token-metered API, analytics SDK, or cloud sync is part of the default Android path.

## Release Gate

Production release is blocked until all of these pass:

- LiteRT-LM runtime is bundled or the UI clearly says runtime is not installed yet.
- Local model file detection verifies format, storage, and device fit.
- Chat/journal conversation suite passes without device-repair persona drift, repeated replies, or fake cloud claims.
- Emulator QA and real-device smoke both pass.
- Release signing, Data safety, privacy policy, screenshots, and Play production track state are verified.

## Android Runtime Wiring

Implemented in this app:

- Gradle dependency: `com.google.ai.edge.litertlm:litertlm-android:0.11.0`
- Runtime adapter: `LiteRtLmConversationRuntime`
- Backend: CPU for the first Android baseline gate
- Automatic provisioning: Google Play fast-follow asset packs `hapondani_model_pack_0..2`
- Asset pack production slots: `model-pack-part*/src/main/assets/model_chunks/gemma-3n-E2B-it-int4.litertlm.part*`
- Local test fallback: Home exposes `Choose model file` backed by Android's document picker
- Runtime model destination: `context.noBackupFilesDir/models/gemma-3n-E2B-it-int4.litertlm`
- Model directories checked on device:
  - `context.noBackupFilesDir/models`
  - `context.filesDir/models`
  - `context.getExternalFilesDir("models")`
- Accepted model file names:
  - `gemma-3n-E2B-it-int4.litertlm`
  - `gemma-3n-E2B-it.litertlm`
  - `gemma-3n-E2B-it-litertlm.litertlm`
  - `gemma-3n-E2B-it-litert-lm.litertlm`
  - `gemma-3n-E4B-it-int4.litertlm`
  - `gemma-3n-E4B-it.litertlm`
  - `gemma-3n-E4B-it-litertlm.litertlm`
  - `gemma-3n-E4B-it-litert-lm.litertlm`

The app is fail-closed: if no readable model file exists, chat reports that personal AI setup has not finished. On Play installs, the app attempts automatic model provisioning from the split Hapo Ndani model asset packs; on sideloaded/test builds, it shows the fallback model picker. If a file exists but LiteRT-LM cannot initialize it, chat reports the LiteRT-LM load failure and stays capture-first. Production still requires a real-device smoke pass.

Emulator note: the full Gemma 3n E2B LiteRT-LM file was pushed to an API 35 emulator image and detected by the app, but direct native initialization crashed the emulator process with SIGILL in `liblitertlm_jni.so` while XNNPack was preparing the weight cache. The app now blocks emulator native initialization before LiteRT-LM starts and shows a physical-device requirement. Emulator QA is therefore valid for UI, provisioning, model detection, and fail-closed behavior; it is not a real conversation-quality pass.

## Source Notes

- Gemma 3n overview: https://ai.google.dev/gemma/docs/gemma-3n
  - Google describes Gemma 3n as optimized for phones, laptops, and tablets, with text, vision, and audio inputs.
  - Google notes E2B/E4B are effective-parameter sizes and can reduce memory through PLE caching, MatFormer selective activation, and conditional parameter loading.
- LiteRT GenAI overview: https://ai.google.dev/edge/litert/genai/overview
  - Google lists LiteRT-LM as the LLM orchestration layer for session cloning, KV cache management, prompt caching/scoring, and stateful inference.
  - The LiteRT model zoo lists Gemma 3n E2B/E4B.
- Play Asset Delivery overview: https://developer.android.com/guide/playcore/asset-delivery
  - Google Play supports install-time, fast-follow, and on-demand asset packs.
  - Fast-follow packs download automatically after install; apps must still check readiness at launch.
- Gemma 3n E2B LiteRT-LM model card: https://huggingface.co/google/gemma-3n-E2B-it-litert-lm
  - Access requires accepting Google's Gemma usage license on Hugging Face before model files can be used.
- Gemma 3n E4B LiteRT-LM model card: https://huggingface.co/google/gemma-3n-E4B-it-litert-lm
  - E4B remains a stronger-phone optional mode, not the broad Android baseline.
  - Access requires accepting Google's Gemma usage license on Hugging Face before model files can be used.
