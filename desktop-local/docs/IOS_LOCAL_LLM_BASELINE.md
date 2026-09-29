# Hapo Ndani iOS Local LLM Baseline

Date: 2026-05-08
Status: planning/update only; no package, build, store upload, or release action from this pass.

## Decision

The iOS app must not treat a 4B model as the human conversation baseline.

Minimum iPhone posture:

- Less than 6 GB memory: capture-only journal and memory.
- 6 GB memory: capture-first, no local chat setup prompt.
- 8 GB or higher memory: allow the 8B-class local model path as the smallest current in-app baseline candidate.

This deliberately excludes some iPhones from full local chat. Bad responses are a product failure, so unsupported devices should get an honest capture-first experience instead of a weak assistant.

## Model Read

- Current 4B Qwen3 GGUF is small enough for phone storage and has an official Q4_K_M file around 2.5 GB, but the model card requires careful non-thinking setup and sampling. Our live app testing already showed the generic 4B path can sound scripted, repetitive, or off-persona, so it stays a mobile candidate, not the baseline.
- Qwen3-4B-Instruct-2507 is the better 4B direction because Qwen marks it as non-thinking only, improved for alignment, open-ended writing, and instruction following. It is a candidate for later once we pin a trusted GGUF/mobile runtime artifact and test it inside the app.
- Gemma 3n E4B is a strong future mobile candidate because Google designed it for low-resource devices with selective parameter activation and LiteRT-LM benchmarks on mobile-class hardware. It is not the current shipped iOS baseline until the Swift/iOS LiteRT loader path is bundled and tested.
- Apple Foundation Models are worth a separate native iOS spike because Apple exposes an on-device language model for text generation and structured output, but availability depends on device factors. It should be treated as an optional Apple-Intelligence-device path, not the only baseline.

## Product Rule

If the app cannot attach a model that passes the conversation-quality suite, it should say the iPhone is ready for private journal and memory capture, not that chat is ready.

Required conversation-quality checks before an iOS TestFlight update:

- greeting and onboarding: no repeated replies, no troubleshooting persona, no generic "tell me what you need" loops;
- personal reflection: responds warmly and concretely to vague human prompts like "I feel stuck";
- product/business request: understands "ship", "launch", "test", "write", and "plan" in app/product context;
- memory/journal: explains local memory without pretending cloud sync or analytics exist;
- adversarial persona drift: refuses device-repair-only and other wrong-persona patterns;
- privacy boundary: no hosted inference, analytics, or file access claims unless the app surface actually enables them.

## Source Notes

- Qwen3-4B-GGUF: https://huggingface.co/Qwen/Qwen3-4B-GGUF
- Qwen3-4B-Instruct-2507: https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507
- Gemma 3n E4B LiteRT-LM: https://huggingface.co/google/gemma-3n-E4B-it-litert-lm
- Gemma 3n overview: https://ai.google.dev/gemma/docs/gemma-3n
- Apple Foundation Models: https://developer.apple.com/documentation/FoundationModels
