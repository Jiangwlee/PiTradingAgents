#!/usr/bin/env python3
"""pi-stream.py - shared JSON event helpers for pi-trader.

Commands:
  render-single  Render Pi JSON lines as human-readable stream output.
  extract-final  Extract the final assistant text from a JSONL file.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path


def supports_color() -> bool:
    return sys.stdout.isatty()


def ansi(text: str, code: str) -> str:
    if not supports_color():
        return text
    return f"\033[{code}m{text}\033[0m"


def label_ansi(label: str) -> str:
    palette = ["1;34", "1;36", "1;32", "1;33", "1;35", "1;31"]
    index = sum(ord(ch) for ch in label) % len(palette)
    return ansi(f"[{label}]", palette[index])


def write_stdout(text: str) -> None:
    sys.stdout.write(text)
    sys.stdout.flush()


def truncate(value: str, limit: int = 120) -> str:
    compact = " ".join(value.strip().split())
    if len(compact) <= limit:
        return compact
    return f"{compact[: limit - 3]}..."


def summarize_content(result: dict) -> str:
    for item in result.get("content", []):
        if item.get("type") != "text":
            continue
        text = item.get("text", "").strip()
        if not text:
            continue
        lines = text.splitlines()
        first = truncate(lines[0], 100)
        if len(lines) > 1:
            return f"{first} (+{len(lines) - 1} lines)"
        return first
    return "no text output"


def extract_message_text(message: dict) -> str:
    parts = message.get("content", [])
    return "".join(part.get("text", "") for part in parts if part.get("type") == "text")


def summarize_args(args: dict) -> str:
    if not args:
        return "-"
    parts: list[str] = []
    for key, value in args.items():
        if isinstance(value, str):
            rendered = value
        else:
            rendered = json.dumps(value, ensure_ascii=False)
        parts.append(f"{key}={truncate(str(rendered), 80)}")
    return " ".join(parts)


def extract_usage(message: dict) -> dict[str, int]:
    usage = message.get("usage", {})
    return {
        "input": int(usage.get("input", 0) or 0),
        "output": int(usage.get("output", 0) or 0),
        "cacheRead": int(usage.get("cacheRead", 0) or 0),
        "cacheWrite": int(usage.get("cacheWrite", 0) or 0),
        "totalTokens": int(usage.get("totalTokens", 0) or 0),
    }


def split_visible_and_trailing(delta: str) -> tuple[str, str]:
    stripped = delta.rstrip("\n")
    trailing = delta[len(stripped) :]
    return stripped, trailing


def iter_json_lines(path: str | None):
    if path:
        with open(path, encoding="utf-8") as handle:
            yield from handle
    else:
        yield from sys.stdin


def extract_final_text(path: str) -> int:
    text = ""
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            try:
                event = json.loads(line.strip())
            except Exception:
                continue
            event_type = event.get("type", "")
            if event_type in ("message_update", "message_end"):
                message = event.get("message", {})
                parts = message.get("content", [])
                candidate = "".join(
                    part.get("text", "") for part in parts if part.get("type") == "text"
                )
                if candidate:
                    text = candidate
    sys.stdout.write(text)
    return 0


def render_single(args: argparse.Namespace) -> int:
    start_ts = time.time()
    in_text_stream = False
    line_open = False
    pending_trailing_newlines = ""
    assistant_stream_open = False
    tools_started = 0
    tool_errors = 0
    pending_tools: dict[str, dict] = {}
    seen_usage_keys: set[str] = set()
    usage_totals = {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "totalTokens": 0}

    if not args.no_header:
        header = (
            f"{ansi(f'[{time.strftime('%H:%M:%S')}]', '90')} "
            f"agent={ansi(args.label, '1;36')} "
            f"model={ansi(args.model, '90')} "
            f"tools={ansi(args.tools, '90')} "
            f"cwd={ansi(str(Path.cwd()), '90')} "
            f"session={ansi('off', '90')}\n\n"
        )
        write_stdout(header)
        line_open = False

    def ensure_line_closed() -> None:
        nonlocal in_text_stream, line_open, pending_trailing_newlines, assistant_stream_open
        if pending_trailing_newlines:
            write_stdout("\n")
            pending_trailing_newlines = ""
            line_open = False
        if line_open:
            write_stdout("\n")
            line_open = False
        in_text_stream = False
        assistant_stream_open = False

    def flush_trailing_newlines(compact: bool) -> None:
        nonlocal pending_trailing_newlines, line_open
        if not pending_trailing_newlines:
            return
        if compact:
            write_stdout("\n")
            line_open = False
        else:
            write_stdout(pending_trailing_newlines)
            line_open = pending_trailing_newlines[-1] != "\n"
        pending_trailing_newlines = ""

    def render_tool_line(status: str, tool_name: str, args_summary: str, summary: str) -> None:
        status_display = "✓" if status == "done" else "✗"
        status_color = "32" if status == "done" else "31"
        line = (
            f"  {ansi(status_display, status_color)} "
            f"{ansi(tool_name, '37')}  "
            f"{ansi(args_summary, '90')}"
        )
        if summary:
            line += f"  {ansi(summary, '90')}"
        write_stdout(f"{line}\n")

    for raw in iter_json_lines(args.file):
        line = raw.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            if in_text_stream:
                write_stdout("\n")
                in_text_stream = False
            write_stdout(f"{line}\n")
            continue

        event_type = event.get("type", "")
        if event_type == "message_update":
            evt = event.get("assistantMessageEvent", {})
            evt_type = evt.get("type", "")
            if evt_type == "text_delta":
                flush_trailing_newlines(compact=not assistant_stream_open)
                if not in_text_stream:
                    prefix = f"{label_ansi(args.label)} "
                    write_stdout(prefix)
                    in_text_stream = True
                    line_open = True
                assistant_stream_open = True
                visible, trailing = split_visible_and_trailing(evt.get("delta", ""))
                if visible:
                    write_stdout(visible)
                    line_open = True
                if trailing:
                    pending_trailing_newlines += trailing
            elif evt_type == "text_end" and in_text_stream:
                in_text_stream = False
                assistant_stream_open = False

        elif event_type == "tool_execution_start":
            flush_trailing_newlines(compact=True)
            ensure_line_closed()
            tools_started += 1
            tool_call_id = str(event.get("toolCallId", ""))
            pending_tools[tool_call_id] = {
                "name": event.get("toolName", "tool"),
                "args_summary": summarize_args(event.get("args", {})),
            }

        elif event_type == "tool_execution_end":
            flush_trailing_newlines(compact=True)
            ensure_line_closed()
            tool_call_id = str(event.get("toolCallId", ""))
            tool_info = pending_tools.pop(tool_call_id, {})
            tool_name = tool_info.get("name", event.get("toolName", "tool"))
            args_summary = tool_info.get("args_summary", summarize_args(event.get("args", {})))
            summary = summarize_content(event.get("result", {}))
            if event.get("isError", False):
                tool_errors += 1
                render_tool_line("error", tool_name, args_summary, summary)
            else:
                render_tool_line("done", tool_name, args_summary, summary)

        elif event_type == "message_end":
            message = event.get("message", {})
            if message.get("role") == "assistant":
                assistant_stream_open = False
                usage_key = str(message.get("responseId") or message.get("timestamp") or id(message))
                if usage_key not in seen_usage_keys:
                    seen_usage_keys.add(usage_key)
                    usage = extract_usage(message)
                    for key, value in usage.items():
                        usage_totals[key] += value

    ensure_line_closed()

    if not args.no_footer:
        duration = time.time() - start_ts
        footer = (
            "\n"
            f"{ansi('[done]', '32')} "
            f"{duration:.1f}s  "
            f"tools={tools_started}  "
            f"errors={tool_errors}  "
            f"tokens=in:{usage_totals['input']} "
            f"out:{usage_totals['output']} "
            f"total:{usage_totals['totalTokens']} "
            f"cache_r:{usage_totals['cacheRead']} "
            f"cache_w:{usage_totals['cacheWrite']}\n"
        )
        write_stdout(footer)
    return 0


def render_parallel_follow(args: argparse.Namespace) -> int:
    path = Path(args.file)
    pid = args.pid
    offset = 0
    emitted_messages: set[str] = set()
    seen_tool_end: set[str] = set()

    def process_event(event: dict) -> None:
        event_type = event.get("type", "")
        if event_type == "tool_execution_end":
            tool_call_id = str(event.get("toolCallId", ""))
            if tool_call_id in seen_tool_end:
                return
            seen_tool_end.add(tool_call_id)
            tool_name = event.get("toolName", "tool")
            args_summary = summarize_args(event.get("args", {}))
            summary = summarize_content(event.get("result", {}))
            status_display = "✓" if not event.get("isError", False) else "✗"
            status_color = "32" if not event.get("isError", False) else "31"
            line = (
                f"{label_ansi(args.label)} "
                f"{ansi(status_display, status_color)} "
                f"{ansi(tool_name, '37')}  "
                f"{ansi(args_summary, '90')}"
            )
            if summary:
                line += f"  {ansi(summary, '90')}"
            write_stdout(f"{line}\n")
            return

        if event_type != "message_end":
            return

        message = event.get("message", {})
        if message.get("role") != "assistant":
            return
        message_key = str(message.get("responseId") or message.get("timestamp") or "")
        if message_key and message_key in emitted_messages:
            return
        if message_key:
            emitted_messages.add(message_key)
        text = extract_message_text(message).strip()
        if not text:
            return
        write_stdout(f"{label_ansi(args.label)}\n{text}\n\n")

    def drain_once() -> None:
        nonlocal offset
        if not path.exists():
            return
        with path.open(encoding="utf-8") as handle:
            handle.seek(offset)
            while True:
                raw = handle.readline()
                if not raw:
                    break
                offset = handle.tell()
                line = raw.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                process_event(event)

    while True:
        drain_once()
        proc_alive = Path(f"/proc/{pid}").exists()
        if not proc_alive:
            drain_once()
            break
        time.sleep(0.2)

    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Shared Pi JSONL helpers for pi-trader")
    subparsers = parser.add_subparsers(dest="command", required=True)

    render = subparsers.add_parser("render-single", help="Render Pi JSON events as readable stream")
    render.add_argument("--label", required=True)
    render.add_argument("--model", required=True)
    render.add_argument("--tools", required=True)
    render.add_argument("--file", help="JSONL file to read instead of stdin")
    render.add_argument("--no-header", action="store_true")
    render.add_argument("--no-footer", action="store_true")

    follow = subparsers.add_parser("render-follow", help="Follow a growing JSONL file and emit complete events")
    follow.add_argument("--label", required=True)
    follow.add_argument("--file", required=True)
    follow.add_argument("--pid", required=True, type=int)

    extract = subparsers.add_parser("extract-final", help="Extract the final assistant text from JSONL")
    extract.add_argument("jsonl_path")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.command == "render-single":
        return render_single(args)
    if args.command == "render-follow":
        return render_parallel_follow(args)
    if args.command == "extract-final":
        return extract_final_text(args.jsonl_path)
    parser.error(f"unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
