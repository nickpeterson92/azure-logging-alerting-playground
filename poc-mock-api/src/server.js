const express = require("express");

const app = express();
app.use(express.json());

// Parse --failure-rate from CLI args
const failureRateArg = process.argv.find((arg) =>
	arg.startsWith("--failure-rate="),
);
const FAILURE_RATE = failureRateArg
	? Number.parseFloat(failureRateArg.split("=")[1])
	: 0.3;

const PORT = process.env.PORT || 3001;

// Request counter for generating unique-ish IDs
let requestCounter = 0;

// Generate a fake Salesforce-style ID
const generateSalesforceId = () => {
	requestCounter += 1;
	const suffix = String(requestCounter).padStart(12, "0");
	return `001${suffix}`;
};

// Salesforce error responses with their HTTP status codes
const ERROR_RESPONSES = [
	{
		status: 400,
		body: {
			errorCode: "INVALID_FIELD",
			message: "No such column 'Custom_Segment__c' on entity 'Account'",
			fields: ["Custom_Segment__c"],
		},
		headers: { "x-sfdc-error-code": "INVALID_FIELD" },
	},
	{
		status: 403,
		body: {
			errorCode: "INSUFFICIENT_ACCESS_OR_READONLY",
			message: "insufficient access rights on cross-reference id",
			fields: ["OwnerId"],
		},
		headers: {},
	},
	{
		status: 400,
		body: {
			errorCode: "FIELD_CUSTOM_VALIDATION_EXCEPTION",
			message: "Value required for field: Email when Status is Active",
			fields: ["Email"],
		},
		headers: {},
	},
	{
		status: 429,
		body: {
			errorCode: "REQUEST_LIMIT_EXCEEDED",
			message: "TotalRequests Limit exceeded.",
		},
		headers: { "Retry-After": "60" },
	},
	{
		status: 503,
		body: {
			errorCode: "SERVER_UNAVAILABLE",
			message: "Server is temporarily unavailable. Please try again later.",
		},
		headers: { "Retry-After": "30" },
	},
];

// Logging middleware
app.use((req, res, next) => {
	const start = Date.now();
	const timestamp = new Date().toISOString();

	res.on("finish", () => {
		const duration = Date.now() - start;
		console.log(
			`[${timestamp}] ${req.method} ${req.path} -> ${res.statusCode} (${duration}ms)`,
		);
	});

	next();
});

// POST /services/data/v59.0/composite/sobjects/:object/:externalIdField
app.post(
	"/services/data/v59.0/composite/sobjects/:object/:externalIdField",
	(_req, res) => {
		const shouldFail = Math.random() < FAILURE_RATE;

		if (shouldFail) {
			const errorIndex = Math.floor(Math.random() * ERROR_RESPONSES.length);
			const error = ERROR_RESPONSES[errorIndex];

			for (const [header, value] of Object.entries(error.headers)) {
				res.set(header, value);
			}

			return res.status(error.status).json(error.body);
		}

		return res.status(200).json({
			id: generateSalesforceId(),
			success: true,
			created: false,
		});
	},
);

// GET /services/data/v59.0/limits
app.get("/services/data/v59.0/limits", (_req, res) => {
	const remaining = Math.floor(Math.random() * 13800) + 200;

	res.status(200).json({
		DailyApiRequests: {
			Max: 15000,
			Remaining: remaining,
		},
	});
});

// GET /health
app.get("/health", (_req, res) => {
	res.status(200).json({
		status: "ok",
		mode: "mock-salesforce-api",
		failureRate: FAILURE_RATE,
	});
});

app.listen(PORT, () => {
	console.log(`Mock Salesforce API server started`);
	console.log(`  Port:         ${PORT}`);
	console.log(`  Failure rate: ${(FAILURE_RATE * 100).toFixed(0)}%`);
	console.log(`  Endpoints:`);
	console.log(
		`    POST /services/data/v59.0/composite/sobjects/:object/:externalIdField`,
	);
	console.log(`    GET  /services/data/v59.0/limits`);
	console.log(`    GET  /health`);
});
