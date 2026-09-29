# Models and their licences

**No model weights are in this repository, and none are redistributed by it.**
The apps link to models you download yourself. Each model carries its own
licence, which applies to you directly — not through this repository's
Apache-2.0 grant.

Read this before you ship anything built on these apps. Some of these are **not
open-source licences**, and two of them place obligations on you.

## What the apps link to

| Model | Where it appears | Licence | What it requires of you |
| --- | --- | --- | --- |
| Qwen3 4B / 8B / 14B (GGUF) | macOS, iOS, Windows/Linux | **Apache-2.0** | Nothing beyond notice retention. Clean. |
| Gemma 3n / 4 E2B, E4B (LiteRT-LM) | macOS, iOS, Android | **Google Gemma Terms of Use** | **Not open source.** You must pass the Gemma terms downstream to your own users and comply with the Gemma Prohibited Use Policy. |
| Hermes 3 Llama 3.1 8B (GGUF) | Windows/Linux | **Llama 3.1 Community License** | **"Built with Llama"** attribution is required, the Llama Acceptable Use Policy applies, and there is a monthly-active-user threshold above which you need a separate licence from Meta. |

Links:

- Gemma Terms of Use — <https://ai.google.dev/gemma/terms>
- Gemma Prohibited Use Policy — <https://ai.google.dev/gemma/prohibited_use_policy>
- Llama 3.1 Community License — <https://github.com/meta-llama/llama-models/blob/main/models/llama3_1/LICENSE>
- Llama Acceptable Use Policy — <https://llama.meta.com/llama3_1/use-policy>
- Qwen3 — Apache-2.0, per each model's card on Hugging Face

If you fork these apps and ship them, **the obligations in the right-hand column
become yours.** The Apache-2.0 licence on this code grants you nothing with
respect to any model's weights.

## Download integrity

Every model URL in this repository is **pinned to an immutable Hugging Face
commit revision** (`/resolve/<sha>/`), not to a moving branch ref. The bytes
behind a pinned URL cannot change after the fact.

Verified reachable at the pinned revision at time of writing:

| Repo | Revision |
| --- | --- |
| `Qwen/Qwen3-4B-GGUF` | `bc640142c66e1fdd12af0bd68f40445458f3869b` |
| `Qwen/Qwen3-8B-GGUF` | `7c41481f57cb95916b40956ab2f0b139b296d974` |
| `Qwen/Qwen3-14B-GGUF` | `530227a7d994db8eca5ab5ced2fb692b614357fd` |
| `litert-community/gemma-4-E2B-it-litert-lm` | `b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1` |
| `litert-community/gemma-4-E4B-it-litert-lm` | `2eee7ac325f20eb8c9ac1d0e972f7c84663062da` |
| `NousResearch/Hermes-3-Llama-3.1-8B-GGUF` | `307a5dfb59aa38d88b6cfd32f44b8ad7c1da9fb8` |

### Still open: expected hashes

`expectedSHA256` is `nil` on every package. The apps implement hash
verification and it works — it is simply not fed any digests, so a download is
accepted on the strength of the pinned revision alone.

Pinning is the substantive protection; the hash is belt-and-braces over it.
Filling them in requires downloading and digesting each multi-gigabyte file
once. **Pull requests welcome.** The verification path already exists:

- Swift — the `expectedSHA256` checks in `StarterAppState.swift`, around the
  model smoke test and the download completion handler
- Electron — the `expectedSHA256` field on each entry in `main.js`
