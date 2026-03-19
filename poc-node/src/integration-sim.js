// ---------------------------------------------------------------------------
// Integration Simulator — uses real HTTP calls + mock SQL client
// Retries transient failures up to MAX_RETRIES, then escalates to error.
// ---------------------------------------------------------------------------

const sqlClient = require("./sql-client");
const sfClient = require("./sf-client");

const MAX_RETRIES = 3;
const RETRY_BASE_MS = 500;

// Event ID constants (eventcreate limits IDs to 1-1000)
const EVENT_ID = {
	SYNC_START: 100,
	SYNC_SUCCESS: 101,
	SQL_ERROR: 201,
	SF_ERROR: 202,
	RETRYABLE_WARNING: 301,
};

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Attempt a SQL query with retries for transient errors (deadlock, timeout).
 * Each retryable failure emits a warning event. If retries are exhausted,
 * the final attempt emits an error.
 */
async function queryWithRetry(
	_cycleNumber,
	sinceTimestamp,
	failureRate,
	events,
) {
	for (let attempt = 1; attempt <= MAX_RETRIES + 1; attempt++) {
		try {
			return await sqlClient.queryContacts(sinceTimestamp, failureRate);
		} catch (err) {
			if (!(err instanceof sqlClient.SqlError)) {
				throw err;
			}

			const classification = sqlClient.classifyError(err);
			const detail =
				`SQL Error #${err.number} on ${err.serverName}: ${err.message} ` +
				`[state=${err.state}, class=${err.class}] -> ${classification.category}`;

			if (!classification.retryable || attempt > MAX_RETRIES) {
				const level = attempt > MAX_RETRIES ? "error" : classification.level;
				const suffix =
					attempt > MAX_RETRIES
						? ` (exhausted ${MAX_RETRIES} retries — escalating to error)`
						: " (not retryable)";
				events.push({
					level,
					eventId: EVENT_ID.SQL_ERROR,
					message: detail + suffix,
				});
				throw {
					classified: true,
					classification,
					isRetryExhausted: attempt > MAX_RETRIES,
				};
			}

			events.push({
				level: "warning",
				eventId: EVENT_ID.RETRYABLE_WARNING,
				message: `${detail} (attempt ${attempt}/${MAX_RETRIES}, retrying...)`,
			});

			await sleep(RETRY_BASE_MS * attempt);
		}
	}
}

/**
 * Attempt a Salesforce upsert with retries for transient errors (429, 503).
 * Each retryable failure emits a warning event. If retries are exhausted,
 * the final attempt emits an error.
 */
async function upsertWithRetry(_cycleNumber, records, sfBaseUrl, events) {
	for (let attempt = 1; attempt <= MAX_RETRIES + 1; attempt++) {
		try {
			return await sfClient.upsertRecords(
				"Contact",
				"External_Id__c",
				records,
				sfBaseUrl,
			);
		} catch (err) {
			if (!(err instanceof sfClient.SalesforceApiError)) {
				throw err;
			}

			const classification = sfClient.classifyError(err);
			const detail =
				`Salesforce API ${err.statusCode}: [${err.errorCode}] ${err.message}` +
				(err.fields.length ? ` (fields: ${err.fields.join(", ")})` : "") +
				(err.retryAfter ? ` (retry-after: ${err.retryAfter}s)` : "") +
				` -> ${classification.category}`;

			if (!classification.retryable || attempt > MAX_RETRIES) {
				const level = attempt > MAX_RETRIES ? "error" : classification.level;
				const suffix =
					attempt > MAX_RETRIES
						? ` (exhausted ${MAX_RETRIES} retries — escalating to error)`
						: " (not retryable)";
				events.push({
					level,
					eventId: EVENT_ID.SF_ERROR,
					message: detail + suffix,
				});
				throw {
					classified: true,
					classification,
					isRetryExhausted: attempt > MAX_RETRIES,
				};
			}

			events.push({
				level: "warning",
				eventId: EVENT_ID.RETRYABLE_WARNING,
				message: `${detail} (attempt ${attempt}/${MAX_RETRIES}, retrying...)`,
			});

			const waitMs = err.retryAfter
				? Math.min(err.retryAfter * 1000, 5000)
				: RETRY_BASE_MS * attempt;
			await sleep(waitMs);
		}
	}
}

/**
 * Run a single sync cycle: query SQL -> upsert to Salesforce.
 * Retryable errors are retried up to MAX_RETRIES times.
 * If retries are exhausted, the warning escalates to an error.
 */
async function runSyncCycle(cycleNumber, options = {}) {
	const { sqlFailureRate = 0.15, sfBaseUrl = "http://localhost:3001" } =
		options;

	const events = [];
	const result = {
		cycle: cycleNumber,
		success: false,
		events,
		recordsFetched: 0,
		recordsCreated: 0,
		recordsUpdated: 0,
		recordsErrored: 0,
		failureType: null,
	};

	// -----------------------------------------------------------------------
	// Step 1: Query SQL Server (with retry for deadlocks/timeouts)
	// -----------------------------------------------------------------------
	events.push({
		level: "info",
		eventId: EVENT_ID.SYNC_START,
		message: `Sync cycle ${cycleNumber}: Querying SQL Server dbo.Contacts for changes...`,
	});

	let queryResult;
	try {
		queryResult = await queryWithRetry(
			cycleNumber,
			new Date().toISOString(),
			sqlFailureRate,
			events,
		);
	} catch (err) {
		if (err.classified) {
			result.failureType = err.isRetryExhausted
				? `${err.classification.category}_RETRY_EXHAUSTED`
				: err.classification.category;
			return result;
		}
		events.push({
			level: "error",
			eventId: EVENT_ID.SQL_ERROR,
			message: `Unexpected SQL layer error: ${err.message}`,
		});
		result.failureType = "UNKNOWN_SQL_ERROR";
		return result;
	}

	result.recordsFetched = queryResult.rowCount;
	events.push({
		level: "info",
		eventId: EVENT_ID.SYNC_START,
		message:
			`Sync cycle ${cycleNumber}: Fetched ${queryResult.rowCount} Contact records ` +
			`(${queryResult.queryDurationMs}ms, schema ${queryResult.schemaVersion})`,
	});

	// -----------------------------------------------------------------------
	// Step 2: Upsert to Salesforce (with retry for 429/503)
	// -----------------------------------------------------------------------
	events.push({
		level: "info",
		eventId: EVENT_ID.SYNC_START,
		message: `Sync cycle ${cycleNumber}: Upserting ${queryResult.rowCount} records to Salesforce Contact via Bulk API 2.0...`,
	});

	try {
		const sfResult = await upsertWithRetry(
			cycleNumber,
			queryResult.records,
			sfBaseUrl,
			events,
		);

		const created = Math.floor(
			Math.random() * Math.floor(queryResult.rowCount * 0.3),
		);
		const updated = queryResult.rowCount - created;
		result.recordsCreated = created;
		result.recordsUpdated = updated;
		result.success = true;

		events.push({
			level: "info",
			eventId: EVENT_ID.SYNC_SUCCESS,
			message:
				`Sync cycle ${cycleNumber}: Complete. ${created} created, ${updated} updated, 0 errors. ` +
				`(SF response: ${sfResult.statusCode})`,
		});

		return result;
	} catch (err) {
		if (err.classified) {
			result.failureType = err.isRetryExhausted
				? `${err.classification.category}_RETRY_EXHAUSTED`
				: err.classification.category;
			result.recordsErrored = queryResult.rowCount;
			return result;
		}
		events.push({
			level: "error",
			eventId: EVENT_ID.SF_ERROR,
			message: `Salesforce connection error: ${err.message} — is the mock API running?`,
		});
		result.failureType = "SF_CONNECTION_ERROR";
		return result;
	}
}

module.exports = {
	runSyncCycle,
	EVENT_ID,
};
