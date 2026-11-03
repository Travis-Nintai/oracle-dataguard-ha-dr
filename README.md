# Oracle Data Guard HA/DR

A standby database only earns its keep on the day the primary fails. This repo is about proving, on an ordinary Tuesday, that the standby is actually ready: redo is flowing, apply is keeping up, there is no gap, and the role transition you would run in an incident has been thought through in advance.

It covers the Data Guard work a senior Oracle DBA owns end to end. Monitoring a physical standby configuration, reading protection modes and lag honestly, operating through the Data Guard broker, and running planned switchovers and unplanned failovers from runbooks instead of improvising during an outage. The companion backup repo, oracle-rman-backup-recovery, covers the case where the standby is not available and recovery has to come from backups instead.

## Who it is for

Oracle DBAs who run, or are about to run, a physical standby. The material assumes you know your way around SQL*Plus and DGMGRL and want repeatable checks and runbooks instead of discovering a transport problem during a failover.

## Layout

```
oracle-dataguard-ha-dr/
├── sql/      -- SQL*Plus read-only checks (standby status and lag)
├── dgmgrl/   -- Data Guard broker command templates (show, switchover, failover)
└── docs/     -- architecture, protection modes, transition runbooks
```

## Assumptions

- Oracle 11g or later, Enterprise Edition. Data Guard itself is an Enterprise Edition feature, and the broker is the supported way to manage a configuration.
- The database runs in ARCHIVELOG mode with force logging enabled. Without archived logs, a standby cannot stay in sync, and the status check says so plainly.
- Database names, hosts, and paths in examples are fictional lab values. Point the scripts at your own environment.
- The examples assume a physical standby. Logical standbys have a different apply mechanism and are not covered here.

## Safety notes

- The SQL scripts are read-only. The DGMGRL templates are not: a switchover reverses the roles of the primary and standby, and a failover promotes the standby while the old primary is presumed lost. Read every DGMGRL file before running it, replace the placeholders, and never test a transition against a database you care about until the runbook has been walked through on a lab configuration.
- A failover is not a switchover. Failing over to a standby while the old primary can still write is how split-brain data loss happens. The runbook states the precondition plainly: fail over only when the primary is confirmed unavailable or its writes are confirmed stopped.
- Never commit credentials, hostnames, or environment-specific connection details alongside these scripts. See `docs/script-conventions.md`.

## Testing

The SQL and DGMGRL in this repo are syntax and logic reviewed against the documented data dictionary and broker command reference. They have not been executed against a live Oracle instance in this environment, and the headers say so. Sample output in the docs is labeled illustrative lab output, not captured results.

## What this demonstrates

High availability ownership, not just standby existence: transport and apply monitoring, protection mode tradeoffs, broker operations, and tested role transitions, the work that decides whether an outage ends in a failover or in an explanation.

## Background

Recreated from standard DBA practice for a personal lab portfolio, generic examples, not exports from any production environment. That keeps them safe to share and easy to adapt.
