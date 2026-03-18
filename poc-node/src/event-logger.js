const EventLogger = require('node-windows').EventLogger;

const logger = new EventLogger('SQLSync-NodeApp');

/**
 * Write an informational event to the Windows Event Log.
 * @param {string} message - The log message.
 * @param {number} eventId - The numeric event ID.
 */
function logInfo(message, eventId) {
  logger.info(message, eventId, () => {
    // callback intentionally empty; fire-and-forget
  });
}

/**
 * Write a warning event to the Windows Event Log.
 * @param {string} message - The log message.
 * @param {number} eventId - The numeric event ID.
 */
function logWarning(message, eventId) {
  logger.warn(message, eventId, () => {
    // callback intentionally empty; fire-and-forget
  });
}

/**
 * Write an error event to the Windows Event Log.
 * @param {string} message - The log message.
 * @param {number} eventId - The numeric event ID.
 */
function logError(message, eventId) {
  logger.error(message, eventId, () => {
    // callback intentionally empty; fire-and-forget
  });
}

module.exports = {
  logInfo,
  logWarning,
  logError
};
