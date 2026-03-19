const { execFile } = require("node:child_process");

const SOURCE = "SQLSync-NodeApp";
const LOG = "APPLICATION";

function writeEvent(type, message, eventId) {
	execFile(
		"eventcreate",
		[
			"/L", LOG,
			"/T", type,
			"/SO", SOURCE,
			"/D", message,
			"/ID", String(eventId),
		],
		(err) => {
			if (err) {
				console.error(`eventcreate failed (${type}, ID=${eventId}): ${err.message}`);
			}
		},
	);
}

function logInfo(message, eventId) {
	writeEvent("INFORMATION", message, eventId);
}

function logWarning(message, eventId) {
	writeEvent("WARNING", message, eventId);
}

function logError(message, eventId) {
	writeEvent("ERROR", message, eventId);
}

module.exports = {
	logInfo,
	logWarning,
	logError,
};
