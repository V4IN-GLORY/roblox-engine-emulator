#!/usr/bin/env node
// data/docs-supplement.json: Roblox Creator Docs data that Studio's ReflectionService dump (data/reflection.json)
// leaves out:
//   1. `classes`: non-Plugin/Studio classes missing from the dump (Player, NetworkClient, NetworkServer,
//      UserGameSettings, NetworkSettings, TaskScheduler, CoreGui, ...) in the dump's own schema, filtered to
//      members a game script may use (`security` None and not `NotScriptable`), plus superclasses needed for
//      their inheritance chains.
//   2. `optionalParameters`: sorted `[class, method, parameterIndex]` (1-based) method parameters marked optional
//      in the docs (`default` present and non-empty, or `type` ending in `?`) that neither the dump's entry nor
//      `classes`' marks so.
//   3. `writeCapabilities`: sorted `[class, property, capability]` for the game-readable properties that are not
//      `ReadOnly`, that the dump (where it lists them) permits no `Write`, and that Roblox refuses to write with
//      "The current thread cannot write '<Name>' (lacking capability <capability>)":
//        - `security.write` != None: `security.write` without its `Security` suffix (Plugin, RobloxEngine,
//          RobloxScript, NotAccessible, LocalUser).
//        - `security.write` == None, a dump property that permits `Read`: PluginOrOpenCloud.
//      Checked against every "M w ... lacking capability" line of validator/probe/expected (Studio 0.748): the rule
//      gives each one's capability but the engine's own wordings (Player.UserId, Debris.MaxItems, ...).
//
//   node tools/docs-supplement.mjs <creator-docs/content/en-us/reference/engine>
//   node tools/docs-supplement.mjs --check <creator-docs/content/en-us/reference/engine>
//
// Source: https://github.com/Roblox/creator-docs (content/en-us/reference/engine/classes/*.yaml), CC-BY-4.0. The docs
// write an empty-string default as no default (Player:Kick's message), so `classes` takes those from Roblox's API dump
// (validator/probe/Full-API-Dump.json).
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DUMP = path.join(ROOT, "data", "reflection.json");
const API_DUMP = path.join(ROOT, "validator", "probe", "Full-API-Dump.json");
const OUT = path.join(ROOT, "data", "docs-supplement.json");
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

function splitMemberName(qualified, fallbackClass) {
	for (const sep of [":", "."]) {
		const idx = qualified.indexOf(sep);
		if (idx >= 0) return [qualified.slice(0, idx), qualified.slice(idx + 1)];
	}
	return [fallbackClass, qualified];
}

// Parses a creator-docs class YAML file relying on its regular 2-space auto-generated layout:
// col 0 top-level keys (`name`, `inherits`, `tags`, `deprecation_message`, `properties`, `methods`, `events`, `callbacks`),
// col 2 list items (`  - ...`), col 4 member fields (`    key: ...`), col 6 nested list items or map entries
// (`      - ...` or `      key: ...`), col 8 parameter/return fields (`        key: ...`).
function parseClassYaml(text) {
	const doc = {
		name: "",
		inherits: [],
		tags: [],
		deprecationMessage: "",
		properties: [],
		methods: [],
		events: [],
		callbacks: [],
	};
	let topSection = "";
	let currentMember = null;
	let memberSub = "";
	let currentItem = null;

	const newMember = () => ({
		className: doc.name,
		name: "",
		type: "",
		tags: [],
		deprecationMessage: "",
		securityRead: "None",
		securityWrite: "None",
		threadSafety: "",
		category: "",
		canLoad: false,
		canSave: false,
		capabilities: [],
		parameters: [],
		returns: [],
	});

	const recordMemberScalar = (member, line) => {
		const colon = line.indexOf(":");
		if (colon < 0) return "";
		const key = line.slice(0, colon).trim();
		const rawVal = line.slice(colon + 1).trim();
		const val = unquote(rawVal);
		if (key === "name") {
			const [cls, shortName] = splitMemberName(val, doc.name);
			member.className = cls;
			member.name = shortName;
		} else if (key === "type") {
			member.type = val;
		} else if (key === "deprecation_message") {
			if (rawVal === "|" || rawVal === "|-" || rawVal === ">" || rawVal === ">-") {
				member.deprecationMessage = "";
			} else {
				member.deprecationMessage = val;
			}
		} else if (key === "thread_safety") {
			member.threadSafety = val;
		} else if (key === "category") {
			member.category = val;
		} else if (key === "security" && val) {
			member.securityRead = val;
			member.securityWrite = val;
		}
		return key;
	};

	const recordItemField = (item, line) => {
		const colon = line.indexOf(":");
		if (colon < 0) return;
		const key = line.slice(0, colon).trim();
		const val = unquote(line.slice(colon + 1));
		if (key === "name") item.name = val;
		else if (key === "type") item.type = val;
		else if (key === "default") item.default = val;
	};

	for (const rawLine of text.split(/\r?\n/)) {
		if (!rawLine.trim() || rawLine.trimStart().startsWith("#")) continue;

		// Col 0: top-level key
		if (!rawLine.startsWith(" ")) {
			currentMember = null;
			memberSub = "";
			currentItem = null;
			const colon = rawLine.indexOf(":");
			if (colon < 0) {
				topSection = "";
				continue;
			}
			const key = rawLine.slice(0, colon).trim();
			const rest = rawLine.slice(colon + 1).trim();
			if (key === "name") {
				doc.name = unquote(rest);
				topSection = "";
			} else if (key === "deprecation_message") {
				if (rest === "|" || rest === "|-" || rest === ">" || rest === ">-") {
					doc.deprecationMessage = "";
					topSection = "deprecation_message";
				} else {
					doc.deprecationMessage = unquote(rest);
					topSection = "";
				}
			} else if (key === "inherits" || key === "tags" || key === "properties" || key === "methods" || key === "events" || key === "callbacks") {
				topSection = rest === "[]" ? "" : key;
			} else {
				topSection = "";
			}
			continue;
		}

		if (topSection === "deprecation_message") {
			if (rawLine.startsWith("  ")) {
				const textLine = rawLine.slice(2).trim();
				if (textLine) doc.deprecationMessage = doc.deprecationMessage ? `${doc.deprecationMessage} ${textLine}` : textLine;
			}
			continue;
		}

		// Top-level list sections (`inherits`, `tags`)
		if (topSection === "inherits" || topSection === "tags") {
			if (rawLine.startsWith("  - ")) {
				const val = unquote(rawLine.slice(4));
				if (val) doc[topSection].push(val);
			}
			continue;
		}

		if (topSection !== "properties" && topSection !== "methods" && topSection !== "events" && topSection !== "callbacks") {
			continue;
		}

		// Col 2: member entry (`  - ...`)
		if (rawLine.startsWith("  - ")) {
			currentMember = newMember();
			memberSub = "";
			currentItem = null;
			doc[topSection].push(currentMember);
			recordMemberScalar(currentMember, rawLine.slice(4));
			continue;
		}
		if (!currentMember) continue;

		// Col 4: member field (`    key: ...`)
		if (rawLine.startsWith("    ") && !rawLine.startsWith("     ")) {
			currentItem = null;
			const trimmed = rawLine.slice(4);
			const key = recordMemberScalar(currentMember, trimmed);
			const colon = trimmed.indexOf(":");
			const rest = colon >= 0 ? trimmed.slice(colon + 1).trim() : "";
			if (rest === "" && (key === "tags" || key === "security" || key === "serialization" || key === "capabilities" || key === "parameters" || key === "returns")) {
				memberSub = key;
			} else if (key === "deprecation_message" && (rest === "|" || rest === "|-" || rest === ">" || rest === ">-")) {
				memberSub = "deprecation_message";
			} else {
				memberSub = "";
			}
			continue;
		}
		if (!memberSub) continue;

		if (memberSub === "deprecation_message") {
			if (rawLine.startsWith("      ")) {
				const textLine = rawLine.slice(6).trim();
				if (textLine) currentMember.deprecationMessage = currentMember.deprecationMessage ? `${currentMember.deprecationMessage} ${textLine}` : textLine;
			}
			continue;
		}

		// Col 6: nested list item (`      - ...`) or nested map key (`      key: ...`)
		if (rawLine.startsWith("      - ")) {
			const rest = rawLine.slice(8);
			if (memberSub === "tags") {
				const val = unquote(rest);
				if (val) currentMember.tags.push(val);
			} else if (memberSub === "capabilities") {
				const val = unquote(rest);
				if (val) currentMember.capabilities.push(val);
			} else if (memberSub === "parameters") {
				currentItem = { name: "", type: "", default: "" };
				currentMember.parameters.push(currentItem);
				recordItemField(currentItem, rest);
			} else if (memberSub === "returns") {
				currentItem = { type: "" };
				currentMember.returns.push(currentItem);
				recordItemField(currentItem, rest);
			}
			continue;
		}

		if (rawLine.startsWith("      ") && !rawLine.startsWith("       ")) {
			const line = rawLine.slice(6);
			const colon = line.indexOf(":");
			if (colon >= 0) {
				const key = line.slice(0, colon).trim();
				const val = unquote(line.slice(colon + 1));
				if (memberSub === "security") {
					if (key === "read") currentMember.securityRead = val || "None";
					else if (key === "write") currentMember.securityWrite = val || "None";
				} else if (memberSub === "serialization") {
					if (key === "can_load") currentMember.canLoad = val === "true";
					else if (key === "can_save") currentMember.canSave = val === "true";
				}
			}
			continue;
		}

		// Col 8: parameter / return field (`        key: ...`)
		if (currentItem && (memberSub === "parameters" || memberSub === "returns") && rawLine.startsWith("        ") && !rawLine.startsWith("         ")) {
			recordItemField(currentItem, rawLine.slice(8));
		}
	}

	return doc;
}

function isGameUsable(member) {
	return member.securityRead === "None" && !member.tags.includes("NotScriptable");
}

// The docs tag no class as Studio's, so the name tells. DraggerService (the settings of Studio's draggers) does not
// say so in its name: a game script's GetService answers nil for it (validator/probe/expected, "C DraggerService").
function isPluginOrStudioClass(name) {
	return name.includes("Plugin") || name.includes("Studio") || name === "DraggerService";
}

// Maps creator-docs type names to data/reflection.json's `{ script?, engine, enum?, instance? }` shape, as the
// members both sources list are written in each.
function mapType(rawType, role, sets) {
	if (!rawType || rawType === "()") return { engine: "Void" };
	const nullable = rawType.endsWith("?");
	const base = nullable ? rawType.slice(0, -1) : rawType;

	if (base === "boolean" || base === "bool") return { script: "boolean", engine: "bool" };
	if (base === "string") return { script: "string", engine: "string" };
	if (base === "int" || base === "int64" || base === "float" || base === "double") return { script: "number", engine: base };
	if (base === "buffer") return { script: "buffer", engine: "Buffer" };
	if (base === "ContentId") return { script: "string", engine: "ContentId" };
	if (base === "Content") return { script: "Content", engine: "Content" };
	if (base === "CFrame") return { script: "CFrame", engine: "CoordinateFrame" };
	if (base === "OptionalCoordinateFrame") return { script: "CFrame", engine: "OptionalCoordinateFrame" };
	if (base === "Rect") return { script: "Rect", engine: "Rect2D" };
	if (base === "Region3int16") return { script: "Region3int16", engine: "Region3Int16" };
	if (base === "Vector2int16") return { script: "Vector2int16", engine: "Vector2Int16" };
	if (base === "Vector3int16") return { script: "Vector3int16", engine: "Vector3Int16" };
	if (base === "Datatype.Font" || base === "Font") return { script: "Font", engine: "Font" };
	if (base === "Array") return { script: "table", engine: "ValueArray" };
	if (base === "Dictionary") return { script: "table", engine: "ValueTable" };
	if (base === "Map") return { script: "Map", engine: "ValueMap" };
	if (base === "Function") return { script: nullable ? "Function?" : "Function", engine: "WeakFunctionRef" };
	if (base === "Tuple") return { script: "...", engine: "Tuple" };
	if (base === "Variant") return { engine: "Variant" };
	if (base === "User") return { engine: "User" };
	if (base === "BinaryString") return { engine: "BinaryString" };
	if (base === "RBXScriptConnection") return { script: "Connection", engine: "Connection" };
	if (base === "RBXScriptSignal") return { script: "EventInstance", engine: "EventInstance" };
	if (base === "Instances") {
		return role === "return"
			? { instance: "Instance", script: "Instances", engine: "Instances" }
			: { script: "Instances", engine: "Instances" };
	}

	const listMatch = /^List<(.+)>$/.exec(base);
	if (listMatch) {
		const inner = listMatch[1];
		if (sets.classes.has(inner)) {
			return { instance: inner, script: "Instances", engine: "Instances" };
		}
		return { script: "table", engine: "ValueArray" };
	}

	const enumName = base.startsWith("Enum.") ? base.slice(5) : sets.enums.has(base) ? base : null;
	if (enumName) {
		return { enum: enumName, script: "EnumItem", engine: "Enum" };
	}

	if (sets.classes.has(base)) {
		if (role === "property") return { instance: base, script: "Instance", engine: "RefType" };
		const kind = sets.isInstance(base) ? "Instance" : "Object";
		return { instance: base, script: kind, engine: kind };
	}

	if (sets.datatypes.has(base)) {
		return { script: nullable ? `${base}?` : base, engine: base };
	}

	// Struct dictionaries documented in creator-docs (e.g. CameraState, ProfileConfiguration)
	return { script: "table", engine: "ValueTable" };
}

function encodeDefault(rawDefault, mappedType) {
	if (!rawDefault) return undefined;
	if (mappedType.engine === "bool") {
		if (rawDefault === "true") return true;
		if (rawDefault === "false") return false;
	}
	if (mappedType.script === "number") {
		const n = Number(rawDefault);
		if (Number.isFinite(n)) return n;
	}
	if (mappedType.enum) {
		const item = rawDefault.includes(".") ? rawDefault.split(".").pop() : rawDefault;
		return { "$t": "EnumItem", e: mappedType.enum, n: item };
	}
	if (mappedType.script === "string") {
		return rawDefault;
	}
	return undefined;
}

function buildDisplay(member, isProperty) {
	const display = {};
	if (isProperty) display.Category = member.category || "Data";
	if (member.tags.includes("Deprecated") || member.deprecationMessage) {
		display.DeprecationMessage = member.deprecationMessage || "";
	}
	return display;
}

// The permits of one action on a member: none when it needs a capability the dump grants no game script (InternalTest,
// PluginOrOpenCloud, Unknown), as the dump writes such members.
function permit(action, member, sets) {
	if (member.capabilities.some(capability => !sets.grantable.has(capability))) return {};
	return { [action]: member.capabilities.join(" | ") };
}

function buildClassEntry(doc, sets) {
	const isService = doc.tags.includes("Service");
	const notCreatable = doc.tags.includes("NotCreatable");
	const classPermits = {};
	if (isService) classPermits.GetService = "";
	else if (!notCreatable) classPermits.New = "";

	const classDisplay = { Category: "General" };
	if (doc.tags.includes("Deprecated") || doc.deprecationMessage) {
		classDisplay.DeprecationMessage = doc.deprecationMessage || "";
	}

	const properties = [];
	for (const prop of doc.properties) {
		if (!isGameUsable(prop)) continue;
		const permits = permit("Read", prop, sets);
		const readOnly = prop.tags.includes("ReadOnly") || prop.securityWrite !== "None";
		if (!readOnly) Object.assign(permits, permit("Write", prop, sets));
		properties.push({
			name: prop.name,
			type: mapType(prop.type, "property", sets),
			display: buildDisplay(prop, true),
			serialized: prop.canLoad && prop.canSave,
			permits,
		});
	}

	const methods = [];
	for (const method of doc.methods) {
		if (!isGameUsable(method)) continue;
		const permits = permit("Call", method, sets);
		if (method.threadSafety === "Safe") Object.assign(permits, permit("CallParallel", method, sets));

		const parameters = method.parameters.map((param, position) => {
			const type = mapType(param.type, "param", sets);
			const entry = { name: param.name, type };
			const emptyDefault = sets.emptyDefaults.has(`${doc.name}\0${method.name}\0${position}`);
			const def = emptyDefault ? "" : encodeDefault(param.default, type);
			if (def !== undefined) entry.default = def;
			return entry;
		});

		let returns;
		if (method.returns.length === 0) {
			returns = { engine: "Void" };
		} else if (method.returns.length === 1) {
			returns = mapType(method.returns[0].type, "return", sets);
		} else {
			returns = { script: "...", engine: "Tuple" };
		}

		methods.push({
			name: method.name,
			display: buildDisplay(method, false),
			returns,
			permits,
			parameters,
		});
	}

	const events = [];
	for (const event of doc.events) {
		if (!isGameUsable(event)) continue;
		const parameters = event.parameters.map(param => ({
			name: param.name,
			type: mapType(param.type, "event", sets),
		}));
		events.push({
			name: event.name,
			display: buildDisplay(event, false),
			permits: permit("Listen", event, sets),
			parameters,
		});
	}

	const callbacks = [];
	for (const cb of doc.callbacks) {
		if (!isGameUsable(cb)) continue;
		const parameters = cb.parameters.map(param => ({
			name: param.name,
			type: mapType(param.type, "param", sets),
		}));
		let returns;
		if (cb.returns.length === 0) returns = { engine: "Void" };
		else if (cb.returns.length === 1) returns = mapType(cb.returns[0].type, "return", sets);
		else returns = { script: "...", engine: "Tuple" };
		callbacks.push({
			name: cb.name,
			display: buildDisplay(cb, false),
			returns,
			permits: permit("Call", cb, sets),
			parameters,
		});
	}

	return {
		name: doc.name,
		superclass: doc.inherits[0] || "",
		serialized: !isService && !doc.tags.includes("NotReplicated"),
		permits: classPermits,
		display: classDisplay,
		properties,
		events,
		methods,
		callbacks,
	};
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

const compareTuple = (a, b) => {
	for (let i = 0; i < Math.min(a.length, b.length); i++) {
		if (a[i] < b[i]) return -1;
		if (a[i] > b[i]) return 1;
	}
	return a.length - b.length;
};

function formatOutput(header, classes, optionalParameters, writeCapabilities) {
	const lines = [
		"{",
		`\t"source": ${JSON.stringify(header.source)},`,
		`\t"license": ${JSON.stringify(header.license)},`,
	];
	if (header.studioVersion) lines.push(`\t"studioVersion": ${JSON.stringify(header.studioVersion)},`);
	if (header.commit) lines.push(`\t"commit": ${JSON.stringify(header.commit)},`);
	lines.push(`\t"dumpVersion": ${JSON.stringify(header.dumpVersion)},`);
	lines.push('\t"classes": [');
	for (let i = 0; i < classes.length; i++) {
		const comma = i + 1 < classes.length ? "," : "";
		lines.push(`\t\t${JSON.stringify(classes[i])}${comma}`);
	}
	lines.push("\t],");
	lines.push('\t"optionalParameters": [');
	for (let i = 0; i < optionalParameters.length; i++) {
		const comma = i + 1 < optionalParameters.length ? "," : "";
		lines.push(`\t\t${JSON.stringify(optionalParameters[i])}${comma}`);
	}
	lines.push("\t],");
	lines.push('\t"writeCapabilities": [');
	for (let i = 0; i < writeCapabilities.length; i++) {
		const comma = i + 1 < writeCapabilities.length ? "," : "";
		lines.push(`\t\t${JSON.stringify(writeCapabilities[i])}${comma}`);
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
		console.error("usage: node tools/docs-supplement.mjs [--check] <creator-docs/content/en-us/reference/engine>");
		process.exit(2);
	}
	const engineDir = positional[0];
	const classesDir = path.join(engineDir, "classes");
	if (!fs.existsSync(classesDir)) {
		console.error(`docs-supplement: missing classes directory under ${engineDir}`);
		process.exit(2);
	}

	const dump = JSON.parse(fs.readFileSync(DUMP, "utf8"));
	const dumpClassNames = new Set();
	const dumpPropertyPermits = new Map();
	const grantable = new Set();
	for (const cls of dump.classes || []) {
		if (!cls?.name) continue;
		dumpClassNames.add(cls.name);
		for (const member of [...(cls.properties || []), ...(cls.methods || []), ...(cls.events || [])]) {
			for (const text of Object.values(member.permits || {})) {
				for (const capability of String(text).split(" | ")) grantable.add(capability);
			}
		}
		for (const prop of cls.properties || []) {
			dumpPropertyPermits.set(`${cls.name}\0${prop.name}`, prop.permits || {});
		}
	}

	const readNames = subdir => {
		const dir = path.join(engineDir, subdir);
		if (!fs.existsSync(dir)) return new Set();
		return new Set(fs.readdirSync(dir).filter(f => f.endsWith(".yaml")).map(f => f.slice(0, -5)));
	};

	const docsByName = new Map();
	const files = fs.readdirSync(classesDir).filter(name => name.endsWith(".yaml")).sort();
	for (const file of files) {
		const doc = parseClassYaml(fs.readFileSync(path.join(classesDir, file), "utf8"));
		if (doc.name) docsByName.set(doc.name, doc);
	}

	const emptyDefaults = new Set();
	for (const cls of JSON.parse(fs.readFileSync(API_DUMP, "utf8")).Classes) {
		for (const member of cls.Members) {
			for (const [position, param] of (member.Parameters || []).entries()) {
				if (param.Default === "") emptyDefaults.add(`${cls.Name}\0${member.Name}\0${position}`);
			}
		}
	}
	const isInstance = name => {
		for (let current = name; current; current = docsByName.get(current)?.inherits[0]) {
			if (current === "Instance") return true;
		}
		return false;
	};
	const sets = {
		enums: new Set([...(dump.enums || []).map(e => e.name), ...readNames("enums")]),
		classes: new Set([...dumpClassNames, ...docsByName.keys()]),
		datatypes: readNames("datatypes"),
		grantable,
		isInstance,
		emptyDefaults,
	};

	// 1. Classes missing from data/reflection.json: non-Plugin/Studio classes with at least one
	//    game-usable member, plus any missing class needed in their superclass chain.
	const wantedClasses = new Set();
	for (const [name, doc] of docsByName) {
		if (dumpClassNames.has(name) || isPluginOrStudioClass(name)) continue;
		const hasUsable =
			doc.properties.some(isGameUsable) ||
			doc.methods.some(isGameUsable) ||
			doc.events.some(isGameUsable) ||
			doc.callbacks.some(isGameUsable);
		if (hasUsable) wantedClasses.add(name);
	}
	for (const name of [...wantedClasses]) {
		let cur = docsByName.get(name)?.inherits[0];
		while (cur && !dumpClassNames.has(cur) && !wantedClasses.has(cur) && docsByName.has(cur)) {
			wantedClasses.add(cur);
			cur = docsByName.get(cur)?.inherits[0];
		}
	}

	const supplementClasses = [...wantedClasses]
		.sort()
		.map(name => buildClassEntry(docsByName.get(name), sets));

	// 2. Optional parameters the entries the engine reads (the dump's, and `classes`') leave unmarked.
	const entryParameters = new Map();
	for (const cls of [...(dump.classes || []), ...supplementClasses]) {
		for (const method of cls.methods || []) {
			const key = `${cls.name}\0${method.name}`;
			if (!entryParameters.has(key)) entryParameters.set(key, method.parameters || []);
		}
	}
	const unmarked = new Map();
	for (const doc of docsByName.values()) {
		for (const method of doc.methods) {
			const key = `${method.className}\0${method.name}`;
			const parameters = entryParameters.get(key);
			if (!parameters) continue;
			for (const [position, documented] of method.parameters.entries()) {
				const entry = parameters[position];
				if (!entry || (!documented.default && !documented.type.endsWith("?"))) continue;
				if (entry.default !== undefined || entry.type?.script?.endsWith("?")) continue;
				unmarked.set(`${key}\0${position + 1}`, [method.className, method.name, position + 1]);
			}
		}
	}
	const optionalParameters = [...unmarked.values()].sort(compareTuple);

	// 3. Property write capabilities, one rule across the dump's classes and the supplement's.
	const restricted = new Map();
	for (const [name, doc] of docsByName) {
		if (!dumpClassNames.has(name) && !wantedClasses.has(name)) continue;
		for (const prop of doc.properties) {
			if (!isGameUsable(prop) || prop.tags.includes("ReadOnly")) continue;
			const key = `${prop.className}\0${prop.name}`;
			const dumped = dumpPropertyPermits.get(key);
			if (dumped && Object.hasOwn(dumped, "Write")) continue; // the dump wins
			let capability = null;
			if (prop.securityWrite !== "None") capability = prop.securityWrite.replace(/Security$/, "");
			else if (dumped && Object.hasOwn(dumped, "Read")) capability = "PluginOrOpenCloud";
			if (capability) restricted.set(key, [prop.className, prop.name, capability]);
		}
	}
	const writeCapabilities = [...restricted.values()].sort(compareTuple);

	const header = {
		source: SOURCE,
		license: LICENSE,
		studioVersion: readStudioVersion(engineDir),
		commit: readGitCommit(engineDir),
		dumpVersion: dump.version || "unknown",
	};
	const rendered = formatOutput(header, supplementClasses, optionalParameters, writeCapabilities);

	if (check) {
		// (a Windows checkout may hold it with CRLF)
		const existing = fs.existsSync(OUT) ? fs.readFileSync(OUT, "utf8").replaceAll("\r\n", "\n") : "";
		if (existing !== rendered) {
			console.error(
				`docs-supplement: ${path.relative(ROOT, OUT)} is out of date (${supplementClasses.length} classes, ${optionalParameters.length} optional params, ${writeCapabilities.length} write caps)`,
			);
			process.exit(1);
		}
		console.log(
			`docs-supplement: ${path.relative(ROOT, OUT)} is up to date (${supplementClasses.length} classes, ${optionalParameters.length} optional params, ${writeCapabilities.length} write caps)`,
		);
		return;
	}

	fs.writeFileSync(OUT, rendered);
	console.log(
		`docs-supplement: wrote ${path.relative(ROOT, OUT)} (${supplementClasses.length} classes, ${optionalParameters.length} optional params, ${writeCapabilities.length} write caps, dump ${header.dumpVersion})`,
	);
}

main();
