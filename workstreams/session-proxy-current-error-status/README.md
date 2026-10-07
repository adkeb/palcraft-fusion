# Current rejection and earlier session history

An actual automatic MC reconnect recovered to `state=bound` and `code=null`, while the status producer still exposed the earlier `guest_not_ready` rejection as `session_error`. The old failure was initially mistaken for a current fault.

This status-only increment keeps that earlier rejection under `last_session_rejection`. `session_error` is published only for an actual current error with `PROXY_SESSION_REJECTED`. It does not clear or rewrite historical logs, weaken rejection, change binding, snapshots, freshness, or the native750ms guard.

The source passed AST inspection; no game or binding test was rerun for this reversible status-label change. It remains a source candidate and is not installed. The private original status/log observations are excluded.
