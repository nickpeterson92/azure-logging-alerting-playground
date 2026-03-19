// ---------------------------------------------------------------------------
// Salesforce HTTP Client — makes real HTTP calls to the mock SF API server
// ---------------------------------------------------------------------------

const http = require("node:http");
const https = require("node:https");
const { URL } = require("node:url");

// ---------------------------------------------------------------------------
// SalesforceApiError
// ---------------------------------------------------------------------------
class SalesforceApiError extends Error {
	constructor({ statusCode, errorCode, message, fields, retryAfter }) {
		super(message);
		this.name = "SalesforceApiError";
		this.statusCode = statusCode;
		this.errorCode = errorCode;
		this.fields = fields || [];
		this.retryAfter = retryAfter || null;
	}
}

// ---------------------------------------------------------------------------
// classifyError — turns a SalesforceApiError into an actionable classification
// ---------------------------------------------------------------------------
const classifyError = (sfError) => {
	if (sfError.statusCode === 429) {
		return { level: "warning", retryable: true, category: "RATE_LIMIT" };
	}
	if (sfError.statusCode === 503) {
		return { level: "warning", retryable: true, category: "TRANSIENT_ERROR" };
	}
	if (sfError.statusCode === 400 && sfError.errorCode === "INVALID_FIELD") {
		return { level: "error", retryable: false, category: "FIELD_MISSING" };
	}
	if (
		sfError.statusCode === 400 &&
		sfError.errorCode === "FIELD_CUSTOM_VALIDATION_EXCEPTION"
	) {
		return {
			level: "warning",
			retryable: false,
			category: "VALIDATION_FAILURE",
		};
	}
	if (sfError.statusCode === 403) {
		return { level: "error", retryable: false, category: "PERMISSION_ERROR" };
	}
	return { level: "error", retryable: false, category: "UNKNOWN_SF_ERROR" };
};

// ---------------------------------------------------------------------------
// httpRequest — thin promise wrapper around Node's built-in http/https modules
// ---------------------------------------------------------------------------
const httpRequest = (url, options, body) =>
	new Promise((resolve, reject) => {
		const parsed = new URL(url);
		const transport = parsed.protocol === "https:" ? https : http;

		const req = transport.request(url, options, (res) => {
			const chunks = [];
			res.on("data", (chunk) => chunks.push(chunk));
			res.on("end", () => {
				const raw = Buffer.concat(chunks).toString("utf-8");
				let parsed = null;
				try {
					parsed = JSON.parse(raw);
				} catch {
					parsed = raw;
				}
				resolve({
					statusCode: res.statusCode,
					headers: res.headers,
					body: parsed,
				});
			});
		});

		req.on("error", (err) => reject(err));

		if (body) {
			req.write(body);
		}
		req.end();
	});

// ---------------------------------------------------------------------------
// upsertRecords — POST records to the mock Salesforce composite API
// ---------------------------------------------------------------------------
const upsertRecords = async (
	objectName,
	externalIdField,
	records,
	baseUrl = "http://localhost:3001",
) => {
	const endpoint = `${baseUrl}/services/data/v59.0/composite/sobjects/${objectName}/${externalIdField}`;

	const payload = JSON.stringify({ allOrNone: false, records });

	const res = await httpRequest(
		endpoint,
		{
			method: "POST",
			headers: {
				"Content-Type": "application/json",
				Accept: "application/json",
			},
		},
		payload,
	);

	if (res.statusCode === 200) {
		return { success: true, statusCode: 200, body: res.body };
	}

	// Parse the first error object from the Salesforce-style response body
	const errorBody = Array.isArray(res.body) ? res.body[0] : res.body;
	const errorCode = errorBody?.errorCode || errorBody?.error || "UNKNOWN_ERROR";
	const errorMessage =
		errorBody?.message || `Salesforce API returned ${res.statusCode}`;
	const fields = errorBody?.fields || [];

	const retryAfter = res.headers["retry-after"]
		? Number(res.headers["retry-after"])
		: null;

	throw new SalesforceApiError({
		statusCode: res.statusCode,
		errorCode,
		message: errorMessage,
		fields,
		retryAfter,
	});
};

module.exports = {
	SalesforceApiError,
	classifyError,
	upsertRecords,
};
