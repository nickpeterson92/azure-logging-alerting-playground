const eventLogger = require('./event-logger');
const appinsights = require('./appinsights');
const integrationSim = require('./integration-sim');

// ---------------------------------------------------------------------------
// Parse command-line arguments
// ---------------------------------------------------------------------------
function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    cycles: 20,
    delay: 5000,
    failureRate: 0.3
  };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--cycles':
        options.cycles = parseInt(args[++i], 10) || 20;
        break;
      case '--delay':
        options.delay = parseInt(args[++i], 10) || 5000;
        break;
      case '--failure-rate':
        options.failureRate = parseFloat(args[++i]);
        if (Number.isNaN(options.failureRate)) options.failureRate = 0.3;
        break;
      default:
        break;
    }
  }

  return options;
}

// ---------------------------------------------------------------------------
// Delay helper
// ---------------------------------------------------------------------------
function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  const opts = parseArgs();
  let shuttingDown = false;

  console.log('==========================================================');
  console.log('  SQLSync Node Simulator');
  console.log(`  Cycles: ${opts.cycles}  Delay: ${opts.delay}ms  Failure Rate: ${(opts.failureRate * 100).toFixed(0)}%`);
  console.log('==========================================================\n');

  // Initialize Application Insights (no-op if connection string not set)
  appinsights.initialize();

  // Metrics accumulators
  const metrics = {
    totalSyncs: 0,
    successes: 0,
    failures: 0,
    failuresByType: {},
    totalRecordsFetched: 0,
    totalRecordsCreated: 0,
    totalRecordsUpdated: 0,
    totalRecordsErrored: 0
  };

  // Graceful shutdown on SIGINT
  process.on('SIGINT', () => {
    if (shuttingDown) return;
    shuttingDown = true;
    console.log('\n[SIGINT] Graceful shutdown requested. Finishing current cycle...');
  });

  // Run sync cycles
  for (let cycle = 1; cycle <= opts.cycles; cycle++) {
    if (shuttingDown) {
      console.log(`[shutdown] Stopping before cycle ${cycle}.`);
      break;
    }

    console.log(`--- Cycle ${cycle}/${opts.cycles} ---`);

    let result;
    try {
      result = await integrationSim.runSyncCycle(cycle, opts.failureRate);
    } catch (err) {
      console.error(`Unexpected error in cycle ${cycle}:`, err.message);
      eventLogger.logError(`Unexpected simulator error: ${err.message}`, 9999);
      appinsights.trackSyncException(err, { cycle: String(cycle) });
      metrics.totalSyncs++;
      metrics.failures++;
      continue;
    }

    metrics.totalSyncs++;
    metrics.totalRecordsFetched += result.recordsFetched;
    metrics.totalRecordsCreated += result.recordsCreated;
    metrics.totalRecordsUpdated += result.recordsUpdated;
    metrics.totalRecordsErrored += result.recordsErrored;

    if (result.success) {
      metrics.successes++;
    } else {
      metrics.failures++;
      if (result.failureType) {
        metrics.failuresByType[result.failureType] =
          (metrics.failuresByType[result.failureType] || 0) + 1;
      }
    }

    // Emit every event to both Windows Event Log and Application Insights
    for (let i = 0; i < result.events.length; i++) {
      const evt = result.events[i];
      const props = {
        cycle: String(result.cycle),
        eventId: String(evt.eventId),
        failureType: result.failureType || 'none'
      };

      switch (evt.level) {
        case 'info':
          console.log(`  [INFO]  ${evt.message}`);
          eventLogger.logInfo(evt.message, evt.eventId);
          appinsights.trackSyncEvent('SyncInfo', { message: evt.message, ...props });
          break;

        case 'warning':
          console.log(`  [WARN]  ${evt.message}`);
          eventLogger.logWarning(evt.message, evt.eventId);
          appinsights.trackSyncEvent('SyncWarning', { message: evt.message, ...props });
          appinsights.trackSyncException(
            new Error(evt.message),
            { severity: 'warning', ...props }
          );
          break;

        case 'error':
          console.log(`  [ERROR] ${evt.message}`);
          eventLogger.logError(evt.message, evt.eventId);
          appinsights.trackSyncEvent('SyncError', { message: evt.message, ...props });
          appinsights.trackSyncException(
            new Error(evt.message),
            { severity: 'error', ...props }
          );
          break;

        default:
          break;
      }
    }

    // Track per-cycle metrics in Application Insights
    appinsights.trackSyncMetric('RecordsFetched', result.recordsFetched);
    appinsights.trackSyncMetric('RecordsCreated', result.recordsCreated);
    appinsights.trackSyncMetric('RecordsUpdated', result.recordsUpdated);
    appinsights.trackSyncMetric('RecordsErrored', result.recordsErrored);
    appinsights.trackSyncMetric('CycleSuccess', result.success ? 1 : 0);

    const statusLabel = result.success
      ? 'SUCCESS'
      : (result.failureType || 'FAILURE');
    console.log(`  => ${statusLabel}\n`);

    // Wait between cycles (unless this is the last one)
    if (cycle < opts.cycles && !shuttingDown) {
      await sleep(opts.delay);
    }
  }

  // ---------------------------------------------------------------------------
  // Summary
  // ---------------------------------------------------------------------------
  console.log('\n==========================================================');
  console.log('  Simulation Summary');
  console.log('==========================================================');
  console.log(`  Total Sync Cycles:    ${metrics.totalSyncs}`);
  console.log(`  Successes:            ${metrics.successes}`);
  console.log(`  Failures:             ${metrics.failures}`);
  console.log(`  Records Fetched:      ${metrics.totalRecordsFetched}`);
  console.log(`  Records Created:      ${metrics.totalRecordsCreated}`);
  console.log(`  Records Updated:      ${metrics.totalRecordsUpdated}`);
  console.log(`  Records Errored:      ${metrics.totalRecordsErrored}`);

  const failureTypes = Object.keys(metrics.failuresByType);
  if (failureTypes.length > 0) {
    console.log('  Failures by Type:');
    for (let t = 0; t < failureTypes.length; t++) {
      console.log(`    ${failureTypes[t]}: ${metrics.failuresByType[failureTypes[t]]}`);
    }
  }
  console.log('==========================================================\n');

  // Send final aggregate metrics to Application Insights
  appinsights.trackSyncMetric('TotalSyncCycles', metrics.totalSyncs);
  appinsights.trackSyncMetric('TotalSuccesses', metrics.successes);
  appinsights.trackSyncMetric('TotalFailures', metrics.failures);
  appinsights.trackSyncMetric('TotalRecordsFetched', metrics.totalRecordsFetched);
  appinsights.trackSyncMetric('TotalRecordsCreated', metrics.totalRecordsCreated);
  appinsights.trackSyncMetric('TotalRecordsUpdated', metrics.totalRecordsUpdated);
  appinsights.trackSyncMetric('TotalRecordsErrored', metrics.totalRecordsErrored);

  appinsights.trackSyncEvent('SimulationComplete', {
    totalCycles: String(metrics.totalSyncs),
    successes: String(metrics.successes),
    failures: String(metrics.failures)
  });

  // Flush telemetry before exiting
  await appinsights.flush();

  console.log('Simulation complete.');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
