export interface StreamedUsageValue {
	cost?: number | { total?: number };
	input?: number;
	output?: number;
	cacheRead?: number;
	cacheWrite?: number;
	reasoning?: number;
}

export interface StreamedChildResult {
	resultIndex: number;
	sessionFile?: string;
	usage?: StreamedUsageValue;
}

export interface StreamedEntry {
	type?: string;
	id?: string;
	cwd?: string;
	timestamp?: string | number;
	thinkingLevel?: string;
	usage?: StreamedUsageValue;
	message: {
		role?: string;
		provider?: string;
		model?: string;
		timestamp?: string | number;
		toolName?: string;
		usage?: StreamedUsageValue;
		details: {
			runId?: string;
			totalChildUsage?: StreamedUsageValue;
			results: StreamedChildResult[];
		};
	};
}

type JsonPath = Array<string | number>;

interface ObjectFrame {
	type: "object";
	path: JsonPath;
	state: "keyOrEnd" | "colon" | "value" | "commaOrEnd";
	key: string;
	afterComma: boolean;
}

interface ArrayFrame {
	type: "array";
	path: JsonPath;
	state: "valueOrEnd" | "commaOrEnd";
	index: number;
	afterComma: boolean;
}

type Frame = ObjectFrame | ArrayFrame;

// Oversized records fail closed beyond these schema ceilings. They bound the
// selector even for adversarial JSON without constraining ignored content.
const MAX_SELECTED_VALUE_BYTES = 64 * 1024;
const MAX_JSON_DEPTH = 128;
const MAX_CHILD_RESULTS = 4096;
const usageFields = new Set([
	"cost",
	"cost.total",
	"input",
	"output",
	"cacheRead",
	"cacheWrite",
	"reasoning",
]);
const selectedPaths = new Set([
	"type",
	"id",
	"cwd",
	"timestamp",
	"thinkingLevel",
	"message.role",
	"message.provider",
	"message.model",
	"message.timestamp",
	"message.toolName",
	"message.details.runId",
	"message.details.results.*.sessionFile",
]);

for (const prefix of [
	"usage",
	"message.usage",
	"message.details.totalChildUsage",
	"message.details.results.*.usage",
]) {
	for (const field of usageFields) selectedPaths.add(`${prefix}.${field}`);
}

function normalizedPath(path: JsonPath): string {
	return path.map((part) => (typeof part === "number" ? "*" : part)).join(".");
}

function ensureUsage(target: {
	usage?: StreamedUsageValue;
}): StreamedUsageValue {
	if (!target.usage) target.usage = {};
	return target.usage;
}

function setUsageValue(
	usage: StreamedUsageValue,
	suffix: string,
	value: unknown,
): void {
	if (suffix === "cost") {
		if (typeof value === "number") usage.cost = value;
		return;
	}
	if (suffix === "cost.total") {
		if (typeof value === "number") {
			const cost =
				typeof usage.cost === "object" && usage.cost !== null ? usage.cost : {};
			cost.total = value;
			usage.cost = cost;
		}
		return;
	}
	if (usageFields.has(suffix) && typeof value === "number") {
		(usage as Record<string, unknown>)[suffix] = value;
	}
}

/**
 * Incremental JSON selector for oversized session records. It validates the
 * JSON structure while retaining only accounting fields, never content bodies.
 */
export class BoundedJsonlEntryParser {
	private readonly entry: StreamedEntry = {
		message: { details: { results: [] } },
	};
	private readonly frames: Frame[] = [];
	private readonly resultsByIndex = new Map<number, StreamedChildResult>();
	private invalid = false;
	private rootStarted = false;
	private rootDone = false;
	private mode: "none" | "string" | "primitive" = "none";
	private tokenIsKey = false;
	private tokenEscaped = false;
	private tokenUnicodeDigits = 0;
	private tokenCapture = false;
	private tokenOverflow = false;
	private tokenBytes: number[] = [];
	private tokenPath: JsonPath = [];
	private primitiveState:
		| "start"
		| "minus"
		| "zero"
		| "integer"
		| "dot"
		| "fraction"
		| "exponent"
		| "exponentSign"
		| "exponentDigits" = "start";
	private primitiveLiteral = "";
	private primitiveLiteralIndex = 0;

	feed(bytes: Buffer): void {
		if (this.invalid) return;
		for (let offset = 0; offset < bytes.length && !this.invalid; offset++) {
			const byte = bytes[offset];
			if (this.mode === "string") {
				this.consumeStringByte(byte);
				continue;
			}
			if (this.mode === "primitive") {
				if (!this.isDelimiter(byte)) {
					this.consumePrimitiveByte(byte);
					continue;
				}
				this.finishPrimitive();
				offset--;
				continue;
			}
			if (this.isWhitespace(byte)) continue;
			switch (byte) {
				case 0x22:
					this.startString();
					break;
				case 0x7b:
					this.startContainer("object");
					break;
				case 0x5b:
					this.startContainer("array");
					break;
				case 0x7d:
					this.endContainer("object");
					break;
				case 0x5d:
					this.endContainer("array");
					break;
				case 0x3a:
					this.consumeColon();
					break;
				case 0x2c:
					this.consumeComma();
					break;
				default:
					this.startPrimitive(byte);
			}
		}
	}

	finish(): StreamedEntry | null {
		if (this.mode === "primitive") this.finishPrimitive();
		if (
			this.mode !== "none" ||
			this.frames.length !== 0 ||
			!this.rootDone ||
			this.invalid
		)
			return null;
		return this.entry;
	}

	private top(): Frame | undefined {
		return this.frames[this.frames.length - 1];
	}

	private takeValuePath(): JsonPath | null {
		const frame = this.top();
		if (!frame) {
			if (this.rootStarted || this.rootDone) {
				this.invalid = true;
				return null;
			}
			this.rootStarted = true;
			this.rootDone = true;
			return [];
		}
		if (frame.type === "object") {
			if (frame.state !== "value") {
				this.invalid = true;
				return null;
			}
			frame.state = "commaOrEnd";
			frame.afterComma = false;
			return [...frame.path, frame.key];
		}
		if (frame.state !== "valueOrEnd") {
			this.invalid = true;
			return null;
		}
		const path = [...frame.path, frame.index];
		frame.index++;
		frame.state = "commaOrEnd";
		frame.afterComma = false;
		return path;
	}

	private startContainer(type: "object" | "array"): void {
		const path = this.takeValuePath();
		if (!path) return;
		if (this.frames.length >= MAX_JSON_DEPTH) {
			this.invalid = true;
			return;
		}
		this.frames.push(
			type === "object"
				? { type, path, state: "keyOrEnd", key: "", afterComma: false }
				: { type, path, state: "valueOrEnd", index: 0, afterComma: false },
		);
	}

	private endContainer(type: "object" | "array"): void {
		const frame = this.top();
		if (
			!frame ||
			frame.type !== type ||
			frame.afterComma ||
			(frame.type === "object" &&
				frame.state !== "keyOrEnd" &&
				frame.state !== "commaOrEnd") ||
			(frame.type === "array" &&
				frame.state !== "valueOrEnd" &&
				frame.state !== "commaOrEnd")
		) {
			this.invalid = true;
			return;
		}
		this.frames.pop();
	}

	private startString(): void {
		const frame = this.top();
		this.tokenIsKey = frame?.type === "object" && frame.state === "keyOrEnd";
		if (this.tokenIsKey) {
			this.tokenPath = [];
			this.tokenCapture = true;
		} else {
			const path = this.takeValuePath();
			if (!path) return;
			this.tokenPath = path;
			this.tokenCapture = selectedPaths.has(normalizedPath(path));
		}
		this.mode = "string";
		this.tokenEscaped = false;
		this.tokenUnicodeDigits = 0;
		this.tokenOverflow = false;
		this.tokenBytes = this.tokenCapture ? [0x22] : [];
	}

	private consumeStringByte(byte: number): void {
		if (this.tokenUnicodeDigits > 0) {
			if (!this.isHexDigit(byte)) {
				this.invalid = true;
				return;
			}
			this.captureByte(byte);
			this.tokenUnicodeDigits--;
			return;
		}
		if (this.tokenEscaped) {
			this.captureByte(byte);
			this.tokenEscaped = false;
			if (byte === 0x75) this.tokenUnicodeDigits = 4;
			else if (
				![0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74].includes(byte)
			) {
				this.invalid = true;
			}
			return;
		}
		if (byte === 0x5c) {
			this.captureByte(byte);
			this.tokenEscaped = true;
			return;
		}
		if (byte !== 0x22) {
			if (byte < 0x20) {
				this.invalid = true;
				return;
			}
			this.captureByte(byte);
			return;
		}
		this.captureByte(byte);
		this.mode = "none";
		const value = this.decodeToken();
		if (this.tokenIsKey) {
			const frame = this.top();
			if (
				frame?.type !== "object" ||
				frame.state !== "keyOrEnd" ||
				typeof value !== "string"
			) {
				this.invalid = true;
				return;
			}
			frame.key = value;
			frame.state = "colon";
		} else if (value !== undefined) {
			this.select(this.tokenPath, value);
		}
	}

	private startPrimitive(firstByte: number): void {
		const path = this.takeValuePath();
		if (!path) return;
		this.tokenPath = path;
		this.tokenCapture = selectedPaths.has(normalizedPath(path));
		this.tokenOverflow = false;
		this.tokenBytes = [];
		this.mode = "primitive";
		this.primitiveState = "start";
		this.primitiveLiteral = "";
		this.primitiveLiteralIndex = 0;
		this.consumePrimitiveByte(firstByte);
	}

	private finishPrimitive(): void {
		this.mode = "none";
		const validNumber =
			this.primitiveState === "zero" ||
			this.primitiveState === "integer" ||
			this.primitiveState === "fraction" ||
			this.primitiveState === "exponentDigits";
		const validLiteral =
			this.primitiveLiteral !== "" &&
			this.primitiveLiteralIndex === this.primitiveLiteral.length;
		if (!validNumber && !validLiteral) {
			this.invalid = true;
			return;
		}
		const value = this.decodeToken();
		if (value !== undefined) this.select(this.tokenPath, value);
	}

	private consumePrimitiveByte(byte: number): void {
		this.captureByte(byte);
		if (this.primitiveLiteral) {
			if (
				byte !== this.primitiveLiteral.charCodeAt(this.primitiveLiteralIndex)
			) {
				this.invalid = true;
				return;
			}
			this.primitiveLiteralIndex++;
			return;
		}
		if (this.primitiveState === "start") {
			if (byte === 0x74) this.startLiteral("true");
			else if (byte === 0x66) this.startLiteral("false");
			else if (byte === 0x6e) this.startLiteral("null");
			else if (byte === 0x2d) this.primitiveState = "minus";
			else if (byte === 0x30) this.primitiveState = "zero";
			else if (this.isNonzeroDigit(byte)) this.primitiveState = "integer";
			else this.invalid = true;
			return;
		}
		if (this.primitiveState === "minus") {
			if (byte === 0x30) this.primitiveState = "zero";
			else if (this.isNonzeroDigit(byte)) this.primitiveState = "integer";
			else this.invalid = true;
			return;
		}
		if (this.primitiveState === "zero" || this.primitiveState === "integer") {
			if (this.primitiveState === "integer" && this.isDigit(byte)) return;
			if (byte === 0x2e) this.primitiveState = "dot";
			else if (byte === 0x65 || byte === 0x45) this.primitiveState = "exponent";
			else this.invalid = true;
			return;
		}
		if (this.primitiveState === "dot") {
			if (this.isDigit(byte)) this.primitiveState = "fraction";
			else this.invalid = true;
			return;
		}
		if (this.primitiveState === "fraction") {
			if (this.isDigit(byte)) return;
			if (byte === 0x65 || byte === 0x45) this.primitiveState = "exponent";
			else this.invalid = true;
			return;
		}
		if (this.primitiveState === "exponent") {
			if (byte === 0x2b || byte === 0x2d) this.primitiveState = "exponentSign";
			else if (this.isDigit(byte)) this.primitiveState = "exponentDigits";
			else this.invalid = true;
			return;
		}
		if (this.primitiveState === "exponentSign") {
			if (this.isDigit(byte)) this.primitiveState = "exponentDigits";
			else this.invalid = true;
			return;
		}
		if (this.primitiveState === "exponentDigits" && !this.isDigit(byte)) {
			this.invalid = true;
		}
	}

	private startLiteral(literal: string): void {
		this.primitiveLiteral = literal;
		this.primitiveLiteralIndex = 1;
	}

	private decodeToken(): unknown {
		if (this.tokenOverflow) {
			this.invalid = true;
			return undefined;
		}
		if (!this.tokenCapture) return undefined;
		try {
			return JSON.parse(Buffer.from(this.tokenBytes).toString("utf8"));
		} catch {
			this.invalid = true;
			return undefined;
		}
	}

	private captureByte(byte: number): void {
		if (!this.tokenCapture || this.tokenOverflow) return;
		if (this.tokenBytes.length >= MAX_SELECTED_VALUE_BYTES) {
			this.tokenOverflow = true;
			return;
		}
		this.tokenBytes.push(byte);
	}

	private consumeColon(): void {
		const frame = this.top();
		if (frame?.type !== "object" || frame.state !== "colon") {
			this.invalid = true;
			return;
		}
		frame.state = "value";
	}

	private consumeComma(): void {
		const frame = this.top();
		if (frame?.state !== "commaOrEnd") {
			this.invalid = true;
			return;
		}
		frame.afterComma = true;
		if (frame.type === "object") frame.state = "keyOrEnd";
		else frame.state = "valueOrEnd";
	}

	private select(path: JsonPath, value: unknown): void {
		const normalized = normalizedPath(path);
		if (normalized === "type" && typeof value === "string")
			this.entry.type = value;
		else if (normalized === "id" && typeof value === "string")
			this.entry.id = value;
		else if (normalized === "cwd" && typeof value === "string")
			this.entry.cwd = value;
		else if (
			normalized === "timestamp" &&
			(typeof value === "string" || typeof value === "number")
		)
			this.entry.timestamp = value;
		else if (normalized === "thinkingLevel" && typeof value === "string")
			this.entry.thinkingLevel = value;
		else if (normalized === "message.role" && typeof value === "string")
			this.entry.message.role = value;
		else if (normalized === "message.provider" && typeof value === "string")
			this.entry.message.provider = value;
		else if (normalized === "message.model" && typeof value === "string")
			this.entry.message.model = value;
		else if (
			normalized === "message.timestamp" &&
			(typeof value === "string" || typeof value === "number")
		)
			this.entry.message.timestamp = value;
		else if (normalized === "message.toolName" && typeof value === "string")
			this.entry.message.toolName = value;
		else if (
			normalized === "message.details.runId" &&
			typeof value === "string"
		)
			this.entry.message.details.runId = value;
		else if (normalized.startsWith("usage.")) {
			setUsageValue(
				ensureUsage(this.entry),
				normalized.slice("usage.".length),
				value,
			);
		} else if (normalized.startsWith("message.usage.")) {
			setUsageValue(
				ensureUsage(this.entry.message),
				normalized.slice("message.usage.".length),
				value,
			);
		} else if (normalized.startsWith("message.details.totalChildUsage.")) {
			const details = this.entry.message.details;
			if (!details.totalChildUsage) details.totalChildUsage = {};
			const usage = details.totalChildUsage;
			setUsageValue(
				usage,
				normalized.slice("message.details.totalChildUsage.".length),
				value,
			);
		} else if (normalized.startsWith("message.details.results.*.")) {
			const resultIndex = path[3];
			if (typeof resultIndex !== "number") return;
			let result = this.resultsByIndex.get(resultIndex);
			if (!result) {
				if (this.resultsByIndex.size >= MAX_CHILD_RESULTS) {
					this.invalid = true;
					return;
				}
				result = { resultIndex };
				this.resultsByIndex.set(resultIndex, result);
				this.entry.message.details.results.push(result);
			}
			const suffix = normalized.slice("message.details.results.*.".length);
			if (suffix === "sessionFile" && typeof value === "string")
				result.sessionFile = value;
			else if (suffix.startsWith("usage."))
				setUsageValue(
					ensureUsage(result),
					suffix.slice("usage.".length),
					value,
				);
		}
	}

	private isWhitespace(byte: number): boolean {
		return byte === 0x20 || byte === 0x09 || byte === 0x0a || byte === 0x0d;
	}

	private isDigit(byte: number): boolean {
		return byte >= 0x30 && byte <= 0x39;
	}

	private isNonzeroDigit(byte: number): boolean {
		return byte >= 0x31 && byte <= 0x39;
	}

	private isHexDigit(byte: number): boolean {
		return (
			this.isDigit(byte) ||
			(byte >= 0x41 && byte <= 0x46) ||
			(byte >= 0x61 && byte <= 0x66)
		);
	}

	private isDelimiter(byte: number): boolean {
		return (
			this.isWhitespace(byte) || byte === 0x2c || byte === 0x5d || byte === 0x7d
		);
	}
}
