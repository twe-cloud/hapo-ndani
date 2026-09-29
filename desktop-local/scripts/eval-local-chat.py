#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
import time


PROMPTS = [
    "hiii",
    "heloo",
    "i wannna dance",
    "I want to work on me",
    "I'm overwhelmed and don't know what to do first",
    "help me plan my week",
    "draft an email telling a customer we need one more day",
    "what can you do with my files?",
    "how does memory work?",
    "help me ship this product",
    "help me launch this app",
    "iefjpic",
    "A mi say boom bye bye in a what?",
]

BANNED = [
    "device troubleshooting assistant",
    "dead battery",
    "dead power button",
    "thanks for your patience",
    "please let me know what you need help with",
    "important to understand what you want to work on",
    "unable to assist with these questions",
    "<think>",
    "</think>",
]

SYSTEM_PROMPT = (
    "You are Hapo Ndani, a warm private local assistant. "
    "Reply naturally in 1-3 short sentences. "
    "Do not be generic support. "
    "Do not mention dead batteries, power buttons, or device troubleshooting. "
    "If the user says ship, launch, or release a product or app, treat it as product delivery, not parcel delivery, unless they explicitly mention packages or addresses. "
    "Do not write hidden reasoning or <think> tags. "
    "Ask one useful next question when needed."
)


def run_llama(model_path: str, prompt: str, timeout: int) -> str:
    cmd = [
        "/opt/homebrew/bin/llama-cli",
        "-m",
        model_path,
        "--jinja",
        "--reasoning",
        "off",
        "--temp",
        "0.4",
        "--top-p",
        "0.9",
        "--min-p",
        "0.02",
        "-n",
        "180",
        "-st",
        "-sys",
        SYSTEM_PROMPT,
        "-p",
        prompt,
    ]
    return subprocess.run(cmd, text=True, capture_output=True, timeout=timeout).stdout


def run_ollama(model: str, prompt: str, timeout: int) -> str:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        "stream": False,
        "think": False,
        "options": {
            "temperature": 0.4,
            "top_p": 0.9,
            "num_predict": 180,
        },
    }
    response = subprocess.run(
        ["curl", "-sS", "http://127.0.0.1:11434/api/chat", "-d", json.dumps(payload)],
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    data = json.loads(response.stdout)
    return data.get("message", {}).get("content", "")


def normalize(text: str) -> str:
    cleaned = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", text)
    cleaned = cleaned.replace("\b", "")
    if "\n>" in cleaned and "\n[" in cleaned:
        after_prompt = cleaned.split("\n>", 1)[1]
        if "\n\n" in after_prompt:
            after_prompt = after_prompt.split("\n\n", 1)[1]
        assistant_text = after_prompt.split("\n[", 1)[0]
        assistant_text = re.sub(r"[|/\\-]+", "", assistant_text)
        return assistant_text.strip()

    lines = []
    for line in cleaned.splitlines():
        if line.startswith("llama_") or line.startswith("main:") or "load_" in line:
            continue
        lines.append(line)
    return "\n".join(lines).strip()


def grade(prompt: str, response: str) -> tuple[bool, list[str]]:
    failures = []
    lower = response.lower()
    if not response:
        failures.append("empty response")
    if len(response.split()) > 110:
        failures.append("too long")
    if any(marker in lower for marker in BANNED):
        failures.append("banned generic/support/thinking text")
    prompt_norm = " ".join(prompt.lower().split())
    response_norm = " ".join(lower.split())
    if prompt_norm and prompt_norm == response_norm:
        failures.append("echoed prompt")
    if prompt in {"hiii", "heloo"} and not any(word in lower for word in ["hapo", "welcome", "hello", "hi"]):
        failures.append("weak greeting")
    if prompt in {"help me ship this product", "help me launch this app"}:
        physical_shipping_terms = [
            "order",
            "address",
            "parcel",
            "package",
            "shipping label",
            "where is it going",
            "delivered",
            "delivery process",
            "send out",
            "physical prototype",
        ]
        if any(word in lower for word in physical_shipping_terms):
            failures.append("treated product launch as physical shipping")
        if re.search(r"\bitem\b", lower):
            failures.append("treated product launch as physical shipping")
        if not any(word in lower for word in ["launch", "release", "ship", "product", "app", "block", "customer", "roadmap", "next"]):
            failures.append("weak product-launch response")
    return not failures, failures


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate local chat model behavior for Hapo Ndani.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--gguf", help="Path to a GGUF model for llama-cli")
    group.add_argument("--ollama", help="Ollama model name")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()

    failures = 0
    for prompt in PROMPTS:
        started = time.time()
        if args.gguf:
            raw = run_llama(args.gguf, prompt, args.timeout)
        else:
            raw = run_ollama(args.ollama, prompt, args.timeout)
        response = normalize(raw)
        passed, reasons = grade(prompt, response)
        failures += 0 if passed else 1
        print(json.dumps({
            "prompt": prompt,
            "passed": passed,
            "failures": reasons,
            "seconds": round(time.time() - started, 2),
            "response": response,
        }, ensure_ascii=True))

    print(json.dumps({"total": len(PROMPTS), "failures": failures}, ensure_ascii=True))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
