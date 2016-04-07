# Loggly 1.1.0

This library wraps the [Loggly](http://www.loggly.com) cloud-based logging service.

The Loggly class automatically adds metadata to your log messages, and handles efficently sending log messages with the [Loggly Bulk Endpoint](https://www.loggly.com/docs/http-bulk-endpoint/).

By default, the Loggly class will send log messages every 15 seconds, or when it has accumulated 100 log messages (whichever occurs first). The value of these parameters can be changed using the `timeout` and `limit` constructor options (see below).

## constructor(*customerToken, [options]*)
To create a new Loggly object you will need your customer token. You may also supply an optional table with any of the following keys to further configure the Loggly object:

| key     | default     | notes                                             |
| ------- | ----------- | ------------------------------------------------- |
| id      | {agentId}   | A unique ID for the device/agent                  |
| tags    | electricimp | A comma separated list of tags for all log events |
| timeout | 15          | Time between sends (in seconds)                   |
| limit   | 100         | Max # of logs that will be queued before sending  |
| debug   | true        | Enables / disables server.log'ing log messages    |

```squirrel
// bulk send logs every minute
loggly <- Loggly("<-- CUSTOMER_TOKEN -->", { "timeout": 60 });
```

### Tags

Tags are a method of adding organization to your log events to aid in segmentation & filtering.

Tags can be used to form [Source Groups](https://www.loggly.com/docs/source-groups/), which will help segment your data & narrow down search results. It’s also possible to search your log data for tags with a search query.

For more information about tags, visit Loggly's [Support Center](https://www.loggly.com/docs/tags/).

## Logging Methods

There are three methods (representing three log levels) that can be used to log messages - `log`, `warn`, and `err`. When any of the logging methods are called, the following set of metadata is added to the message:

```squirrel
{
    "id": string,       // the id set in the constructor
    "level": string,    // The log level (specified by what logging method was invoked)
    "timestamp": string // An ISO 8601 timestamp
}
```

All three of the logging methods can be invoked in the following ways:

### log/warn/error(*table*)

When a table is passed into one of the logging methods, each key/value pair will be added to the log message. If desired, the metadata can be overriden by including keys present in the metadata (i.e. `id`, `level`, `timestamp`).

In the following example, we send a message collected from the device, and override the timestamp metadata with a device-side timestamp:

```squirrel
// Log information sent from the device
device.on("data", function(data) {
    loggly.log({
        "timestamp": Loggly.ISODateTime(data.ts),
        "ssid": data.ssid,
        "rssi": data.rssi,
        "msg": data.msg
    });
});
```

### log/warn/error(*string, [...]*)

A string, or a [format string](https://electricimp.com/docs/squirrel/string/format/) with parameters can also be passed into the logging methods. When a string or format string is passed into the logging methods, it will be added to the log message with a key of `msg`.

```squirrel
// Log a string:
loggly.log("Hello World!");

// Log a format string:
loggly.log("%s %s", "Hello", "World!");
```

### log/warn/error(*object*)

Any other object passed into logging methods will be cast as a string with the `.tostring()` method and added to the log message with a key of `msg`.

```squirrel
loggly.log(123.456);
```

## len()

Returns the number of logs that are currently queued to send.

*See onError for example usage.*

## onError(*callback*)

The onError handler allows you to attach an error handler (the callback) to the Loggly class. The error handler will be invoked if the Loggly class ever encounters an error while sending the logs to Loggly (note: the Loggly class will automatically retry sending the logs until successful).

The onError callback takes a single parameter - an HTTP Response table containing the `statuscode`, `body`, and `headers` (see [http.sendasync](https://electricimp.com/docs/api/httprequest/sendasync/) for more information).

```squirrel
loggly <- Loggly("<-- CUSTOMER_TOKEN -->");

loggly.onError(function(resp) {
    server.error("Failed to send messages to Loggly - " + resp.body);
    server.error(loggly.len() " messages queued for next send.");
});
```

## flush(*[callback]*)

The *flush* method will immediatly send any queued message to the Loggly service. An optional *callback* parameter can be passed to the *flush* method that will be invoked upon completion of the request.

The callback method takes two parameters - *error* (a string describing the error), and *response* (an [HTTP Response table](https://electricimp.com/docs/api/httprequest/sendasync/)). If the request was successful, the *error* parameter will be `null`.

Typical usage of the Loggly class should not involve calling *flush* - however when [server.onshutdown()](https://electricimp.com/docs/api/server/onshutdown/) is implemented, it would be a good idea to flush logs before calling [server.restart()](https://electricimp.com/docs/api/server/restart/).

```squirrel
function flushAndRestart(attempt = 0) {
    // If we've tried and failed 5 times, give up and restart
    if (attempt >= 5) {
        server.restart();
    }

    // Otherwise, try flushing the messages
    loggly.flush(function(err, resp) {
        if (err != null) {
            // If it failed, try again in 10 seconds
            imp.wakeup(10, function() { flushAndRestart(attempt+1);; });
            return;
        }

        // If we sent the logs, restart
        server.restart();
    });
}

server.onshutdown(function(shutdownReasonCode) {
    // Log a shutdown message
    loggly.log({
        "msg": "Shutting Down",
        "reason": shutdownReasonCode
    });

    // Flush the loggly messages, and restart
    flushAndRestart();
});
```

## Loggly.ISODateTime(*[timestamp]*)

The Loggly class has a static method that can generate an ISO 8601 datetime object. The ISODateTime method has an optional parameter *timestamp* - a Unix timestamp (generated with [time()](https://electricimp.com/docs/squirrel/system/time/)).

If an ISO 8601 datetime object is included with the key "timestamp" it will override the system timestamp generated by the Loggly class. This is particulairly useful when logging data from the device:

```squirrel
// Device code

// Reads data, sends it to the agent, then goes to sleep for 1 hr
function SenseSendAndSleep() {
    // Sense the data
    local data = senseData();

    // Add a timestamp
    data.ts <- time();

    // Send the data
    agent.send("data", data);

    // Go to sleep
    imp.onidle(function() { server.sleepfor(3600); });
}
```

```squirrel
// Agent Code

device.on("data", function(data) {
    // grab and delete the timestamp
    local ts = delete data.ts;

    // Add an ISO Datetime object with the key "timestamp"
    data.timestamp <- Loggly.ISODateTime(ts);

    // Logs the data
    loggly.log(data);
});
```

# License

The Loggly library is licensed under the [MIT License](./LICENSE).
