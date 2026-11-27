"""Turns a training dataset into validate.py --batch rows: one row per answer, its fenced Luau blocks run together.

  python validator/extract.py data.jsonl [--out rows.jsonl] [--sample N] [--seed 0] [--blocks]

Reads the record shapes the datasets use: {"text"} (its blocks), {"prompt", "completion"} (the completion's assistant
messages, or its text) and {"prompt", "chosen", "rejected"} (both answers, tagged). Only ```lua / ```luau blocks count.

An answer's code is often in pieces (a second block uses what the first defined) and builds on the conversation (a fix to
the code the user pasted, a change to the last answer's script). So a row is the answer's `blocks` (validate.py runs each
as a script, on its own side, and reads the others for what a block's undefined names are), and `earlier` is the
conversation's code before it (the prompt's blocks), which validate.py reads the same way and never runs. `--blocks` makes
a row of each block alone instead.

Each row is {"id": "<file>:<line>:<field>[:<block>]", "code", "blocks", "earlier", "hint"}: code is the blocks joined; hint
is the request the code answers (the last user message, or a text's words before its first block), which validate.py
reads for the side when the code alone doesn't say.
"""
import argparse
import json
import os
import random
import re
import sys

BLOCK = re.compile(r"```(?:luau|lua)[ \t]*\r?\n(.*?)```", re.S | re.I)


def message_text(messages, role: str | None = "assistant") -> str:
	if isinstance(messages, str):
		return messages
	return "\n\n".join(message.get("content") or "" for message in messages or [] if role is None or message.get("role") == role)


def last_user(messages) -> str:
	if isinstance(messages, str):
		return messages
	users = [message.get("content") or "" for message in messages or [] if message.get("role") == "user"]
	return users[-1] if users else ""


def blocks(text: str) -> list[str]:
	return [block for block in BLOCK.findall(text) if block.strip()]


def answers(record: dict):
	"""(field, answer text, earlier conversation text, hint) for each answer a record holds."""
	if "text" in record:
		text = record["text"]
		first = text.find("```")
		yield "text", text, "", text[:first] if first >= 0 else ""
		return
	prompt = record.get("prompt")
	earlier, hint = message_text(prompt, None), last_user(prompt)
	for field in ("completion", "chosen", "rejected"):
		if field in record:
			yield field, message_text(record[field]), earlier, hint


def rows(path: str, separate: bool):
	name = os.path.basename(path)
	with open(path, encoding="utf-8") as source:
		for number, line in enumerate(source, 1):
			if not line.strip():
				continue
			record = json.loads(line)
			for field, text, earlier, hint in answers(record):
				found = blocks(text)
				if not found:
					continue
				hint = hint[-2000:]
				context = "\n".join(blocks(earlier))[-20000:]
				if separate:
					for index, block in enumerate(found):
						yield {"id": f"{name}:{number}:{field}:{index}", "code": block, "earlier": context, "hint": hint}
					continue
				yield {"id": f"{name}:{number}:{field}", "code": "\n".join(found), "blocks": found, "earlier": context, "hint": hint}


if __name__ == "__main__":
	parser = argparse.ArgumentParser()
	parser.add_argument("file")
	parser.add_argument("--out", help="default: stdout")
	parser.add_argument("--sample", type=int, help="this many rows, drawn at random (reservoir)")
	parser.add_argument("--seed", type=int, default=0)
	parser.add_argument("--blocks", action="store_true", help="a row per block, without the conversation's earlier code")
	args = parser.parse_args()
	found = rows(args.file, args.blocks)
	if args.sample:
		picker = random.Random(args.seed)
		kept = []
		for seen, row in enumerate(found):
			if seen < args.sample:
				kept.append(row)
			else:
				slot = picker.randrange(seen + 1)
				if slot < args.sample:
					kept[slot] = row
		found = kept
	out = open(args.out, "w", encoding="utf-8") if args.out else sys.stdout
	try:
		for row in found:
			out.write(json.dumps(row) + "\n")
	finally:
		if out is not sys.stdout:
			out.close()
