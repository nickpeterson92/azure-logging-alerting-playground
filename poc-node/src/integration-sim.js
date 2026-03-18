// Event ID constants
const EVENT_ID = {
  SYNC_START: 1000,
  SYNC_SUCCESS: 1001,
  COLUMN_DROPPED: 2001,
  TABLE_RENAMED: 2002,
  SF_FIELD_MISSING: 2003,
  SF_PERMISSION_ERROR: 2004,
  VALIDATION_WARNING: 3001
};

/**
 * Generate a random integer between min and max (inclusive).
 */
function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/**
 * Simulate a delay to mimic real processing time.
 */
function delay(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

/**
 * Run a single sync cycle simulation.
 *
 * @param {number} cycleNumber - The cycle number (1-based).
 * @param {number} [failureRate=0.3] - Probability of a failure occurring (0.0 to 1.0).
 * @returns {Promise<Object>} Result object with events array and summary data.
 */
async function runSyncCycle(cycleNumber, failureRate) {
  if (typeof failureRate !== 'number') {
    failureRate = 0.3;
  }

  const events = [];
  const result = {
    cycle: cycleNumber,
    success: false,
    events: events,
    recordsFetched: 0,
    recordsCreated: 0,
    recordsUpdated: 0,
    recordsErrored: 0,
    failureType: null
  };

  // Step 1: Always start with the SQL query initiation
  events.push({
    level: 'info',
    eventId: EVENT_ID.SYNC_START,
    message: `Sync cycle ${cycleNumber}: Initiating SQL Server query on dbo.Contacts...`
  });

  // Small delay to simulate query execution
  await delay(randomInt(50, 200));

  // Determine if this cycle will fail
  const willFail = Math.random() < failureRate;

  if (willFail) {
    // Pick a random failure scenario
    const scenario = randomInt(1, 5);

    switch (scenario) {
      case 1: // SQL Schema Drift - Column Dropped
        result.failureType = 'SCHEMA_DRIFT_COLUMN_DROPPED';
        events.push({
          level: 'error',
          eventId: EVENT_ID.COLUMN_DROPPED,
          message:
            "SCHEMA_DRIFT: Column 'PhoneExtension' was dropped from dbo.Contacts " +
            '(detected via schema comparison). Last known schema version: v42, current: v43. ' +
            "ALTER TABLE migration 'contacts_cleanup_2024' removed column. " +
            "Integration field mapping 'PhoneExtension -> Contact.Phone_Extension__c' is now broken."
        });
        break;

      case 2: // SQL Schema Drift - Table Renamed
        result.failureType = 'SCHEMA_DRIFT_TABLE_RENAMED';
        events.push({
          level: 'error',
          eventId: EVENT_ID.TABLE_RENAMED,
          message:
            "SQL_ERROR: Invalid object name 'dbo.Contacts'. Table may have been renamed or moved. " +
            "Investigating sys.objects... Found potential match: 'dbo.Contact_Records' " +
            '(renamed in migration #1205 on 2024-01-14). Integration config references stale table name.'
        });
        break;

      case 3: { // Salesforce Field Missing/Removed
        result.failureType = 'SALESFORCE_FIELD_MISSING';
        const fetchedCount = randomInt(50, 1000);
        result.recordsFetched = fetchedCount;
        events.push({
          level: 'info',
          eventId: EVENT_ID.SYNC_START,
          message: `Sync cycle ${cycleNumber}: Fetched ${fetchedCount} Contact records (delta since last sync)`
        });
        events.push({
          level: 'info',
          eventId: EVENT_ID.SYNC_START,
          message: `Sync cycle ${cycleNumber}: Mapping SQL Contact fields to Salesforce Contact object...`
        });
        events.push({
          level: 'info',
          eventId: EVENT_ID.SYNC_START,
          message: `Sync cycle ${cycleNumber}: Upserting ${fetchedCount} records to Salesforce Contact via Bulk API 2.0...`
        });
        events.push({
          level: 'error',
          eventId: EVENT_ID.SF_FIELD_MISSING,
          message:
            'SALESFORCE_UPSERT_FAILED: Field Contact.Department_Code__c does not exist. ' +
            'API Error: INVALID_FIELD at row 0. The custom field may have been deleted from ' +
            `the Salesforce org. Last successful upsert using this field: 2024-01-15T08:00:00Z. ` +
            `Affected records in batch: ${fetchedCount}.`
        });
        result.recordsErrored = fetchedCount;
        break;
      }

      case 4: { // Salesforce Object Permission Error
        result.failureType = 'SALESFORCE_PERMISSION_ERROR';
        const fetchedCount = randomInt(50, 1000);
        result.recordsFetched = fetchedCount;
        events.push({
          level: 'info',
          eventId: EVENT_ID.SYNC_START,
          message: `Sync cycle ${cycleNumber}: Fetched ${fetchedCount} Contact records (delta since last sync)`
        });
        events.push({
          level: 'info',
          eventId: EVENT_ID.SYNC_START,
          message: `Sync cycle ${cycleNumber}: Mapping SQL Contact fields to Salesforce Contact object...`
        });
        events.push({
          level: 'info',
          eventId: EVENT_ID.SYNC_START,
          message: `Sync cycle ${cycleNumber}: Upserting ${fetchedCount} records to Salesforce Contact via Bulk API 2.0...`
        });
        events.push({
          level: 'error',
          eventId: EVENT_ID.SF_PERMISSION_ERROR,
          message:
            "SALESFORCE_CRUD_ERROR: Entity type 'Contact' is not supported for upsert operation " +
            "by integration user. Check profile 'API_Integration_Profile' CRUD permissions. " +
            'Error: INSUFFICIENT_ACCESS on Contact (missing: Create, Edit). ' +
            "OAuth scope: api,bulk. Connected app: 'SQLServerSync'."
        });
        result.recordsErrored = fetchedCount;
        break;
      }

      case 5: { // Salesforce Validation Rule Failure (Warning - partial success)
        result.failureType = 'SALESFORCE_VALIDATION_FAILURE';
        const fetchedCount = randomInt(200, 1000);
        result.recordsFetched = fetchedCount;
        const rejectedCount = randomInt(20, Math.min(100, Math.floor(fetchedCount * 0.3)));
        const successCount = fetchedCount - rejectedCount;
        const created = randomInt(0, Math.floor(successCount * 0.4));
        const updated = successCount - created;

        events.push({
          level: 'info',
          eventId: EVENT_ID.SYNC_START,
          message: `Sync cycle ${cycleNumber}: Fetched ${fetchedCount} Contact records (delta since last sync)`
        });
        events.push({
          level: 'info',
          eventId: EVENT_ID.SYNC_START,
          message: `Sync cycle ${cycleNumber}: Mapping SQL Contact fields to Salesforce Contact object...`
        });
        events.push({
          level: 'info',
          eventId: EVENT_ID.SYNC_START,
          message: `Sync cycle ${cycleNumber}: Upserting ${fetchedCount} records to Salesforce Contact via Bulk API 2.0...`
        });
        events.push({
          level: 'warning',
          eventId: EVENT_ID.VALIDATION_WARNING,
          message:
            `SALESFORCE_VALIDATION_FAILED: ${rejectedCount} of ${fetchedCount} ` +
            "records rejected by validation rule 'Contact.Email_Required_For_Active'. " +
            "Rule: AND(ISPICKVAL(Status__c, 'Active'), ISBLANK(Email)). " +
            "Source SQL records have NULL email but Status='Active'. " +
            `Partial success: ${successCount} records upserted.`
        });

        result.recordsCreated = created;
        result.recordsUpdated = updated;
        result.recordsErrored = rejectedCount;
        // Partial success counts as a failure for tracking
        result.success = false;
        return result;
      }

      default:
        break;
    }

    result.success = false;
    return result;
  }

  // Normal (successful) flow
  const recordCount = randomInt(50, 1000);
  result.recordsFetched = recordCount;

  events.push({
    level: 'info',
    eventId: EVENT_ID.SYNC_START,
    message: `Sync cycle ${cycleNumber}: Fetched ${recordCount} Contact records (delta since last sync)`
  });

  await delay(randomInt(30, 100));

  events.push({
    level: 'info',
    eventId: EVENT_ID.SYNC_START,
    message: `Sync cycle ${cycleNumber}: Mapping SQL Contact fields to Salesforce Contact object...`
  });

  await delay(randomInt(30, 100));

  events.push({
    level: 'info',
    eventId: EVENT_ID.SYNC_START,
    message: `Sync cycle ${cycleNumber}: Upserting ${recordCount} records to Salesforce Contact via Bulk API 2.0...`
  });

  await delay(randomInt(100, 400));

  const created = randomInt(0, Math.floor(recordCount * 0.3));
  const updated = recordCount - created;
  result.recordsCreated = created;
  result.recordsUpdated = updated;

  events.push({
    level: 'info',
    eventId: EVENT_ID.SYNC_SUCCESS,
    message: `Sync cycle ${cycleNumber}: Complete. ${created} created, ${updated} updated, 0 errors.`
  });

  result.success = true;
  return result;
}

module.exports = {
  runSyncCycle,
  EVENT_ID
};
