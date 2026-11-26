#!/usr/bin/env node
// data/optional-parameters.json: method parameters that Roblox's Creator Docs mark optional (`default` present and
// non-empty, or `type` ending in `?`) that Studio's ReflectionService dump (data/reflection.json) leaves unmarked.
// Read when reflection metadata is built (src/reflection/members.rs) so ParameterInfo.optional is the union of both.
//
//   node tools/optional-parameters.mjs <creator-docs/content/en-us/reference/engine>
//   node tools/optional-parameters.mjs --check <creator-docs/content/en-us/reference/engine>
//
// Source: https://github.com/Roblox/creator-docs (content/en-us/reference/engine/classes/*.yaml), CC-BY-4.0.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DUMP = path.join(ROOT, "data", "reflection.json");
const OUT = path.join(ROOT, "data", "optional-parameters.json");
const SOURCE = "https://github.com/Roblox/creator-docs (content/en-us/reference/engine/classes/*.yaml)";
const LICENSE = "CC-BY-4.0 (Roblox Corporation)";

function unquote(raw) {
	const text = raw.trim();
	if (!text || text === "null" || text === "~") return "";
	if (text.length >= 2 && text.startsWith("'") && text.endsWith("'")) return text.slice(1, -1).replaceAll("''", "'");
	if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
		try {
			return JSON.parse(text);
		} catch {
			return text.slice(1, -1);
		}
	}
	return text;
}

// Parses a class YAML file's `methods:` list into [{ className, methodName, parameters: [{ name, type, default }] }].
// Relies on creator-docs' regular 2-space YAML layout: `methods:` at col 0, `- name: Class:Method` at col 2,
// `parameters:` at col 4, `- name: ...` at col 6, and parameter fields (`type:`, `default:`) at col 8.
function parseClassYaml(text) {
	const methods = [];
	let fileClass = "";
	let inMethods = false;
	let currentMethod = null;
	let inParams = false;
	let currentParam = null;

	const recordField = (target, line) => {
		const colon = line.indexOf(":");
		if (colon < 0) return;
		const key = line.slice(0, colon).trim();
		const value = unquote(line.slice(colon + 1));
		if (key === "name") target.name = value;
		else if (key === "type") target.type = value;
		else if (key === "default") target.default = value;
	};

	for (const rawLine of text.split(/\r?\n/)) {
		if (!rawLine.trim() || rawLine.trimStart().startsWith("#")) continue;

		// Top-level key (col 0)
		if (!rawLine.startsWith(" ")) {
			inParams = false;
			currentParam = null;
			currentMethod = null;
			if (rawLine.startsWith("name:")) {
				fileClass = unquote(rawLine.slice(5));
				inMethods = false;
			} else {
				inMethods = rawLine === "methods:";
			}
			continue;
		}
		if (!inMethods) continue;

		// Method entry (col 2: `  - ...`)
		if (rawLine.startsWith("  - ")) {
			inParams = false;
			currentParam = null;
			const rest = rawLine.slice(4);
			const fullName = rest.startsWith("name:") ? unquote(rest.slice(5)) : "";
			const sep = fullName.indexOf(":");
			const className = sep >= 0 ? fullName.slice(0, sep) : fileClass;
			const methodName = sep >= 0 ? fullName.slice(sep + 1) : fullName;
			currentMethod = { className, methodName, parameters: [] };
			methods.push(currentMethod);
			continue;
		}
		if (!currentMethod) continue;

		// Method-level key (col 4: `    key: ...`)
		if (rawLine.startsWith("    ") && !rawLine.startsWith("     ")) {
			currentParam = null;
			if (rawLine.startsWith("    name:") && !currentMethod.methodName) {
				const fullName = unquote(rawLine.slice(9));
				const sep = fullName.indexOf(":");
				currentMethod.className = sep >= 0 ? fullName.slice(0, sep) : fileClass;
				currentMethod.methodName = sep >= 0 ? fullName.slice(sep + 1) : fullName;
			}
			inParams = rawLine === "    parameters:";
			continue;
		}
		if (!inParams) continue;

		// Parameter entry (col 6: `      - ...`)
		if (rawLine.startsWith("      - ")) {
			currentParam = { name: "", type: "", default: "" };
			currentMethod.parameters.push(currentParam);
			recordField(currentParam, rawLine.slice(8));
			continue;
		}

		// Parameter field (col 8: `        key: ...`; col 10+ is a block scalar body like `summary: |`)
		if (currentParam && rawLine.startsWith("        ") && !rawLine.startsWith("         ")) {
			recordField(currentParam, rawLine.slice(8));
		}
	}
	return methods;
}

function readGitCommit(dir) {
	try {
		return execFileSync("git", ["-C", dir, "rev-parse", "HEAD"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim() || null;
	} catch {
		return null;
	}
}

function readStudioVersion(engineDir) {
	const file = path.join(engineDir, "STUDIO_VERSION");
	if (!fs.existsSync(file)) return null;
	const first = fs.readFileSync(file, "utf8").split(/\r?\n/).find(line => line.trim());
	return first ? first.trim() : null;
}

const compareEntry = (a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : a[2] - b[2]);

function formatOutput(header, parameters) {
	const lines = [
		"{",
		`\t"source": ${JSON.stringify(header.source)},`,
		`\t"license": ${JSON.stringify(header.license)},`,
	];
	if (header.studioVersion) lines.push(`\t"studioVersion": ${JSON.stringify(header.studioVersion)},`);
	if (header.commit) lines.push(`\t"commit": ${JSON.stringify(header.commit)},`);
	lines.push(`\t"dumpVersion": ${JSON.stringify(header.dumpVersion)},`);
	lines.push('\t"parameters": [');
	for (let i = 0; i < parameters.length; i++) {
		const comma = i + 1 < parameters.length ? "," : "";
		lines.push(`\t\t${JSON.stringify(parameters[i])}${comma}`);
	}
	lines.push("\t]");
	lines.push("}");
	return lines.join("\n") + "\n";
}

function main() {
	const args = process.argv.slice(2);
	const check = args.includes("--check");
	const positional = args.filter(arg => !arg.startsWith("--"));
	if (positional.length !== 1) {
		console.error("usage: node tools/optional-parameters.mjs [--check] <creator-docs/content/en-us/reference/engine>");
		process.exit(2);
	}
	const engineDir = positional[0];
	const classesDir = path.join(engineDir, "classes");
	if (!fs.existsSync(classesDir)) {
		console.error(`optional-parameters: missing classes directory under ${engineDir}`);
		process.exit(2);
	}

	const dump = JSON.parse(fs.readFileSync(DUMP, "utf8"));
	const dumpMethods = new Map();
	const dumpOptional = new Set();
	for (const cls of dump.classes || []) {
		if (!cls?.name) continue;
		for (const method of cls.methods || []) {
			if (!method?.name) continue;
			const key = `${cls.name}\0${method.name}`;
			if (dumpMethods.has(key)) continue;
			const params = method.parameters || [];
			dumpMethods.set(key, params.length);
			for (let i = 0; i < params.length; i++) {
				const param = params[i];
				const script = param?.type?.script || "";
				if ((param.default !== undefined && param.default !== null) || script.endsWith("?")) {
					dumpOptional.add(`${key}\0${i + 1}`);
				}
			}
		}
	}

	const seen = new Set();
	const extra = [];
	let docsOptionalCount = 0;
	const files = fs.readdirSync(classesDir).filter(name => name.endsWith(".yaml")).sort();
	for (const file of files) {
		const methods = parseClassYaml(fs.readFileSync(path.join(classesDir, file), "utf8"));
		for (const method of methods) {
			const key = `${method.className}\0${method.methodName}`;
			const dumpParamCount = dumpMethods.get(key);
			if (dumpParamCount === undefined) continue;
			for (let i = 0; i < method.parameters.length; i++) {
				const index = i + 1;
				if (index > dumpParamCount) continue;
				const param = method.parameters[i];
				if (!param.default && !param.type.endsWith("?")) continue;
				const paramKey = `${key}\0${index}`;
				if (seen.has(paramKey)) continue;
				seen.add(paramKey);
				docsOptionalCount++;
				if (!dumpOptional.has(paramKey)) {
					extra.push([method.className, method.methodName, index]);
				}
			}
		}
	}
	extra.sort(compareEntry);

	const header = {
		source: SOURCE,
		license: LICENSE,
		studioVersion: readStudioVersion(engineDir),
		commit: readGitCommit(engineDir),
		dumpVersion: dump.version || "unknown",
	};
	const rendered = formatOutput(header, extra);

	if (check) {
		const existing = fs.existsSync(OUT) ? fs.readFileSync(OUT, "utf8") : "";
		if (existing !== rendered) {
			console.error(`optional-parameters: ${path.relative(ROOT, OUT)} is out of date (${extra.length} entries from ${files.length} class files)`);
			process.exit(1);
		}
		console.log(`optional-parameters: ${path.relative(ROOT, OUT)} is up to date (${extra.length} entries)`);
		return;
	}

	fs.writeFileSync(OUT, rendered);
	console.log(`optional-parameters: wrote ${extra.length} entries to ${path.relative(ROOT, OUT)} (${docsOptionalCount} optional in docs, ${dumpOptional.size} in dump ${header.dumpVersion})`);
}

main();
