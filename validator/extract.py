"""Turns a training dataset into validate.py --batch rows: one row per fenced Luau block of each record's answer.

  python validator/extract.py data.jsonl [--out rows.jsonl] [--sample N] [--seed 0]

Reads the record shapes the datasets use: {"text"} (the blocks of the text), {"prompt", "completion"} (the completion's
assistant messages, or its text) and {"prompt", "chosen", "rejected"} (both answers, tagged). Only ```lua / ```luau blocks
count. Each row is {"id": "<file>:<line>:<field>:<block>", "code", "hint"}: hint is the request the code answers (the
last user message, or a text's words before its first block), which validate.py reads for the context when the code
alone doesn't say.
"""
import argparse
import json
import os
import random
import re
import sys

BLOCK = re.compile(r"```(?:luau|lua)[ \t]*\r?\n(.*?)```", re.S | re.I)


def message_text(messages) -> str:
	if isinstance(messages, str):
		return messages
	return "\n\n".join(message.get("content") or "" for message in messages or [] if message.get("role") == "assistant")


def last_user(messages) -> str:
	if isinstance(messages, str):
		return messages
	users = [message.get("content") or "" for message in messages or [] if message.get("role") == "user"]
	return users[-1] if users else ""


def answers(record: dict):
	"""(field, answer text, hint) for each answer a record holds."""
	if "text" in record:
		text = record["text"]
		first = text.find("```")
		yield "text", text, text[:first] if first >= 0 else ""
		return
	hint = last_user(record.get("prompt"))
	for field in ("completion", "chosen", "rejected"):
		if field in record:
			yield field, message_text(record[field]), hint


def rows(path: str):
	name = os.path.basename(path)
	with open(path, encoding="utf-8") as source:
		for number, line in enumerate(source, 1):
			if not line.strip():
				continue
			record = json.loads(line)
			for field, text, hint in answers(record):
				for index, block in enumerate(BLOCK.findall(text)):
					if block.strip():
						yield {"id": f"{name}:{number}:{field}:{index}", "code": block, "hint": hint[-2000:]}


if __name__ == "__main__":
	parser = argparse.ArgumentParser()
	parser.add_argument("file")
	parser.add_argument("--out", help="default: stdout")
	parser.add_argument("--sample", type=int, help="this many rows, drawn at random (reservoir)")
	parser.add_argument("--seed", type=int, default=0)
	args = parser.parse_args()
	found = rows(args.file)
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
