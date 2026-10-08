# Normal stop TCP port capability probe

The original HUD relay uses `ThreadingTCPServer` with `allow_reuse_address = True`, followed by the standard listening activation. The original runtime port check used a plain bind, so a completed TCP connection in TIME_WAIT could be reported busy even though the reusable relay listener could bind and listen.

On the tested Mac, SO_REUSEADDR also permits cross-address listener binding: a new loopback listener can coexist with an active wildcard listener, and vice versa. A loopback-only reuse probe is therefore insufficient. The final `_port_free` requires successful SO_REUSEADDR + bind + listen on both loopback and wildcard for TCP, closing each probe immediately. An active listener on either address remains busy. UDP retains its original loopback bind without reuse or listening.

The three supplied cases use real local ephemeral sockets: netstat-observed server TIME_WAIT, active loopback/wildcard TCP listeners, and bound/closed UDP sockets. They do not probe application ports, run any game/roles, or establish a live normal-off receipt. Run `python3 -B checks/check_tcp_probe.py` from this exported tree on the existing tested Mac platform. The test extracts only the actual `_port_free` functions and uses the real socket module; it does not import the runtime's Game/launcher modules.

Only the runtime `_port_free` function and adjacent spacing change. Save/journal/waits, generated configuration, ready fields, profile schema, and other guards remain unchanged. The rejected single-address candidate and its failed attempt are retained privately; the final real cases pass. This is a source candidate for a later approved normal update, not an installed repair or a witness for any prior shutdown.
