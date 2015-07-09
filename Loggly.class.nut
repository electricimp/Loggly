// Copyright (c) 2015 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

class Loggly {
    static version = [1,0,0];

    static LOG_URL = "https://logs-01.loggly.com/bulk/%s/tag/%s/"

    static LOG  = "LOG";
    static WARN = "WARNING";
    static ERR  = "ERROR";

    _token = null;          // The customer token
    _id = null;             // ID (default: agentID)
    _tag = null;            // The log Tag (default: electricimp)
    _timeout = null;        // Send frequency (default: 15s)
    _debug = null;          // whether or not to server.log (default: true)

    _url = null;            // The URL we send reqeusts to
    _logString = null;      // The current set of logs that are queued for send

    _onError = null;        // The onError handler for when there's a problem with the logs

    constructor(token, options = {}) {
        _token = token;

        // Grab any settings
        _id = "id" in options ? options.id : split(http.agenturl(), "/").pop();
        _tag = "tag" in options ? options.tag : "electricimp"
        _timeout = "timeout" in options ? options.timeout : 15;
        _debug = "debug" in options ? options.debug : true;

        // Generate the URL
        _url = _generateUrl()

        // initialize _logString
        _logString = "";

        // Start the watchdog loop
        imp.wakeup(_timeout, _watchdog.bindenv(this));
    }

    function log(msg, ...) {
        _push(LOG, msg, vargv);
    }

    function warn(msg, ...) {
        _push(WARN, msg, vargv);
    }

    function error(msg, ...) {
        _push(ERR, msg, vargv);
    }

    function send() {
        // if there's nothing to log, we're done
        if (_logString.len() == 0) return;

        // Grab the logs, and clear
        local logs = _logString;
        _logString = "";

        // Send the logs
        http.post(_url, {}, logs).sendasync(function(resp) {
            if (resp.statuscode != 200) {
                // If an error occured, add the logs back in
                _logString += logs;

                if (_onError != null) {
                    local __this = this;
                    imp.wakeup(0, function() { __this._onError(resp); });
                } else {
                    server.error("Loggly send failed:");
                    server.error("   " + resp.statuscode + " - " + resp.body);
                }
            } else {
                // nothing
            }
        }.bindenv(this));
    }

    function onError(cb) {
        _onError = cb;
    }

    //-------------------- PRIVATE METHODS --------------------//
    // Addes a log to the _logString
    function _push(level, msg, argv = []) {
        local json = {
            "id": _id,
            "level": level,
            "timestamp": _generateISODateTime()
        };

        if (typeof(msg) == "string") {
            local args = [this, msg];
            if (argv.len() > 0 && typeof(argv[0]) == "array") {
                argv = argv[0];
            }
            args.extend(argv);
            // If it's a string, treat as format
            json.msg <- format.acall(args);
        } else if (typeof msg == "table") {
            // if it's a single message
            foreach(idx, val in msg) {
                json[idx] <- val;
            }
        } else {
            // If it's anything else, treat as string
            json.msg <- msg.tostring();
        }

        json = http.jsonencode(json);
        if (_debug) server.log(json);

        _logString += json + "\n";
    }

    function _generateISODateTime(ts = null) {
        if (ts == null) ts = time();
        local datetime = date(ts);
        return format("%04i-%02i-%02iT%02i:%02i:%02iZ",
            datetime.year, datetime.month+1, datetime.day,
            datetime.hour, datetime.min, datetime.sec);
    }

    function _watchdog() {
        imp.wakeup(_timeout, _watchdog.bindenv(this));
        send();
    }

    function _generateUrl() {
        return format(LOG_URL, _token, _tag);
    }

}
