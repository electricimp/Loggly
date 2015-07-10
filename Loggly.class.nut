class Loggly {
    static version = [1,0,1];

    static LOG_URL = "https://logs-01.loggly.com/bulk/%s/tag/%s/"

    static LOG  = "LOG";
    static WARN = "WARNING";
    static ERR  = "ERROR";

    _token = null;          // The customer token
    _id = null;             // ID (default: agentID)
    _tags = null;           // The log Tag (default: electricimp)
    _timeout = null;        // Send frequency (default: 15s)
    _limit = null;          // Max logs we collect before sending (default: 100)
    _debug = null;          // whether or not to server.log (default: true)

    _url = null;            // The URL we send reqeusts to
    _logString = null;      // The current set of logs that are queued for send
    _numLogs = null;        // The current nubmer of log messages in the queue

    _onError = null;        // The onError handler for when there's a problem with the logs
    _timer = null;          // The watchdog's timer object

    constructor(token, options = {}) {
        _token = token;

        // Grab any settings
        _id = "id" in options ? options.id : split(http.agenturl(), "/").pop();
        _tags = "tags" in options ? options.tags : "electricimp"
        _timeout = "timeout" in options ? options.timeout : 15;
        _limit = "limit" in options ? options.limit : 100;
        _debug = "debug" in options ? options.debug : true;

        // Generate the URL
        _url = _generateUrl()

        // initialize logs
        _logString = "";
        _numLogs = 0;
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
        server.log("WARNING: Loggly.send() is deprecated and has been replaced with .flush()");
        flush();
    }

    function flush() {
        _timer = null;

        // Grab the logs, and clear
        local logs = _logString;
        local numLogs = _numLogs;

        _logString = "";
        _numLogs = 0;

        // Send the logs
        http.post(_url, {}, logs).sendasync(function(resp) {
            if (resp.statuscode < 200 || resp.statuscode >= 300) {
                // If an error occured, add the logs back in
                _logString += logs;
                _numLogs += numLogs;

                // restart the timer if it hasn't already been restarted
                if (_timer == null) _timer = imp.wakeup(_timeout, flush.bindenv(this));

                if (_onError != null) {
                    imp.wakeup(0, function() { _onError(resp); }.bindenv(this));
                } else {
                    server.error("Loggly send failed:");
                    server.error("   " + resp.statuscode + " - " + resp.body);
                }
            } else {
                // nothing
            }
        }.bindenv(this));
    }

    function len() {
        return _numLogs;
    }


    function onError(cb) {
        _onError = cb;
    }

    static function ISODateTime(ts = null) {
        if (ts == null) ts = time();
        local datetime = date(ts);
        return format("%04i-%02i-%02iT%02i:%02i:%02iZ",
            datetime.year, datetime.month+1, datetime.day,
            datetime.hour, datetime.min, datetime.sec);
    }

    //-------------------- PRIVATE METHODS --------------------//
    // Addes a log to the _logString
    function _push(level, msg, argv = []) {
        // Start the timer if we haven't already
        if (_timer == null) _timer = imp.wakeup(_timeout, flush.bindenv(this));

        local json = {
            "id": _id,
            "level": level,
            "timestamp": ISODateTime()
        };

        if (typeof(msg) == "string") {
            local args = [this, msg];
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
        _numLogs++;

        // If we hit our log limit, send
        if (_numLogs >= _limit) flush();
    }

    function _generateUrl() {
        return format(LOG_URL, _token, _tags);
    }
}
