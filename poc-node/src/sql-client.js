// ---------------------------------------------------------------------------
// Mock SQL Client — simulates querying SQL Server with realistic error codes
// ---------------------------------------------------------------------------

const FAILURE_CATALOG = [
	{
		number: 207,
		message: "Invalid column name 'PhoneExtension'.",
		state: 1,
		class: 16,
		serverName: "sqlprod-east-01",
		procedureName: "",
	},
	{
		number: 208,
		message: "Invalid object name 'dbo.Contacts'.",
		state: 1,
		class: 16,
		serverName: "sqlprod-east-01",
		procedureName: "",
	},
	{
		number: 245,
		message:
			"Conversion failed when converting the varchar value '$1,234.56' to data type decimal.",
		state: 1,
		class: 16,
		serverName: "sqlprod-east-01",
		procedureName: "",
	},
	{
		number: 1205,
		message:
			"Transaction (Process ID 52) was deadlocked on lock resources with another process and has been chosen as the deadlock victim.",
		state: 51,
		class: 13,
		serverName: "sqlprod-east-01",
		procedureName: "",
	},
	{
		number: -2,
		message:
			"Timeout expired. The timeout period elapsed prior to completion of the operation.",
		state: 0,
		class: 11,
		serverName: "sqlprod-east-01",
		procedureName: "",
	},
	{
		number: 229,
		message:
			"The SELECT permission was denied on the object 'Contacts', database 'SyncDB', schema 'dbo'.",
		state: 5,
		class: 14,
		serverName: "sqlprod-east-01",
		procedureName: "",
	},
];

// ---------------------------------------------------------------------------
// SqlError — mirrors the shape of real mssql/tedious error objects
// ---------------------------------------------------------------------------
class SqlError extends Error {
	constructor({
		number,
		message,
		state,
		class: severity,
		serverName,
		procedureName,
	}) {
		super(message);
		this.name = "SqlError";
		this.number = number;
		this.state = state;
		this.class = severity;
		this.serverName = serverName;
		this.procedureName = procedureName || "";
	}
}

// ---------------------------------------------------------------------------
// classifyError — turns a raw SqlError into an actionable classification
// ---------------------------------------------------------------------------
const classifyError = (sqlError) => {
	switch (sqlError.number) {
		case 1205:
			return { level: "warning", retryable: true, category: "DEADLOCK" };
		case -2:
			return { level: "warning", retryable: true, category: "TIMEOUT" };
		case 207:
			return {
				level: "error",
				retryable: false,
				category: "SCHEMA_DRIFT_COLUMN",
			};
		case 208:
			return {
				level: "error",
				retryable: false,
				category: "SCHEMA_DRIFT_TABLE",
			};
		case 245:
			return { level: "error", retryable: false, category: "TYPE_MISMATCH" };
		case 229:
			return {
				level: "error",
				retryable: false,
				category: "PERMISSION_DENIED",
			};
		default:
			return {
				level: "error",
				retryable: false,
				category: "UNKNOWN_SQL_ERROR",
			};
	}
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const randomInt = (min, max) =>
	Math.floor(Math.random() * (max - min + 1)) + min;

const SAMPLE_CONTACTS = [
	{
		ContactId: "C-12345",
		FirstName: "John",
		LastName: "Doe",
		Email: "john.doe@example.com",
		Status: "Active",
	},
	{
		ContactId: "C-12346",
		FirstName: "Jane",
		LastName: "Smith",
		Email: "jane.smith@example.com",
		Status: "Active",
	},
	{
		ContactId: "C-12347",
		FirstName: "Carlos",
		LastName: "Reyes",
		Email: "carlos.reyes@example.com",
		Status: "Inactive",
	},
	{
		ContactId: "C-12348",
		FirstName: "Priya",
		LastName: "Patel",
		Email: null,
		Status: "Active",
	},
	{
		ContactId: "C-12349",
		FirstName: "Wei",
		LastName: "Zhang",
		Email: "wei.zhang@example.com",
		Status: "Active",
	},
];

// ---------------------------------------------------------------------------
// queryContacts — the main export: resolves with rows or throws SqlError
// ---------------------------------------------------------------------------
const queryContacts = async (_sinceTimestamp, failureRate = 0.3) => {
	// Simulate a small query delay
	await new Promise((resolve) => {
		setTimeout(resolve, randomInt(20, 80));
	});

	const willFail = Math.random() < failureRate;

	if (willFail) {
		const template = FAILURE_CATALOG[randomInt(0, FAILURE_CATALOG.length - 1)];
		throw new SqlError(template);
	}

	const rowCount = randomInt(50, 1000);
	const queryDurationMs = randomInt(50, 3000);

	return {
		records: SAMPLE_CONTACTS,
		rowCount,
		schemaVersion: "v43",
		queryDurationMs,
	};
};

module.exports = {
	SqlError,
	classifyError,
	queryContacts,
};
