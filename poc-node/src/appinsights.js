let client = null;
let warningLogged = false;

/**
 * Initialize Application Insights from the APPLICATIONINSIGHTS_CONNECTION_STRING
 * environment variable. Returns true if initialization succeeded, false otherwise.
 */
function initialize() {
  const connectionString = process.env.APPLICATIONINSIGHTS_CONNECTION_STRING;

  if (!connectionString) {
    if (!warningLogged) {
      console.warn(
        '[appinsights] WARNING: APPLICATIONINSIGHTS_CONNECTION_STRING is not set. ' +
        'Telemetry will be disabled (no-op mode).'
      );
      warningLogged = true;
    }
    return false;
  }

  try {
    const appInsights = require('applicationinsights');
    appInsights
      .setup(connectionString)
      .setAutoCollectRequests(false)
      .setAutoCollectPerformance(false)
      .setAutoCollectDependencies(false)
      .setAutoCollectConsole(false)
      .setAutoCollectExceptions(true)
      .start();

    client = appInsights.defaultClient;
    console.log('[appinsights] Application Insights initialized successfully.');
    return true;
  } catch (err) {
    console.error('[appinsights] Failed to initialize Application Insights:', err.message);
    return false;
  }
}

/**
 * Track a custom event in Application Insights.
 * @param {string} name - Event name.
 * @param {Object} [properties] - Custom properties dictionary.
 */
function trackSyncEvent(name, properties) {
  if (!client) {
    return;
  }
  client.trackEvent({
    name: name,
    properties: properties || {}
  });
}

/**
 * Track an exception in Application Insights.
 * @param {Error} error - The error object.
 * @param {Object} [properties] - Custom properties dictionary.
 */
function trackSyncException(error, properties) {
  if (!client) {
    return;
  }
  client.trackException({
    exception: error,
    properties: properties || {}
  });
}

/**
 * Track a custom metric in Application Insights.
 * @param {string} name - Metric name.
 * @param {number} value - Metric value.
 */
function trackSyncMetric(name, value) {
  if (!client) {
    return;
  }
  client.trackMetric({
    name: name,
    value: value
  });
}

/**
 * Flush all pending telemetry. Returns a promise that resolves when flushing completes.
 */
function flush() {
  return new Promise((resolve) => {
    if (!client) {
      resolve();
      return;
    }
    client.flush({
      callback: () => {
        resolve();
      }
    });
  });
}

module.exports = {
  initialize,
  trackSyncEvent,
  trackSyncException,
  trackSyncMetric,
  flush
};
