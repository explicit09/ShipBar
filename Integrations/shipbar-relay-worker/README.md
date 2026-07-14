# ShipBar Relay Worker

This worker heartbeats a Mac, leases private cloud captures and execution requests, and passes them through ShipBar's signed `shipbarctl` bridge. It acknowledges a capture only after ShipBar returns the durable local task.

## Configure

Build with `npm install && npm run build`. Set `SHIPBAR_RELAY_URL`, `SHIPBAR_DEVICE_ID`, and optionally `SHIPBAR_DEVICE_NAME` and `SHIPBARCTL_PATH`.

Store the relay key in macOS Keychain so it never appears in a plist or source file:

```sh
security add-generic-password -U -s com.shipbar.relay -a default -w
```

For a one-cycle proof, run `npm run once`. For continuous sync, run `npm start` or adapt the example LaunchAgent under `launchd/` after replacing its path placeholders.

The worker never runs shell strings. It invokes the signed helper with an argument array, keeps queued work in the relay after offline/local failures, and reports prepared runs as `claimed` until ShipBar proves a later lifecycle state.
