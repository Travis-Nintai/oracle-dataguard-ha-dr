# Switchover and failover runbook

Role transitions are the part of Data Guard that gets tested least and needed most. This runbook covers the two transitions, the reinstate that follows a failover, and the gap that is the most common reason a transition does not go cleanly. Read the whole runbook before the first transition, and run the first transition on a lab configuration, not on the one the business depends on.

## Before any transition

Run both checks and compare them. `sql/dataguard_status.sql` on the primary and on the standby should agree: same applied sequence, no gap, no destination error. `dgmgrl/show_configuration.dgmgrl` should report no warnings. If the two views disagree, believe the worse one and investigate before proceeding.

Check the switchover status on the primary (`V$DATABASE.SWITCHOVER_STATUS`). A value of `TO STANDBY` means a switchover can proceed. `SESSIONS ACTIVE` means connected sessions are blocking it; those sessions must disconnect or be handled first, not forced. `RESOLUTION` and other values mean the broker or the configuration needs attention before any transition is attempted.

Confirm where application connections will go. A role transition that the database handles perfectly and the application cannot find is still an outage. Services, connection strings, and any load balancer or cluster configuration that points at the primary must be planned alongside the database steps, and the cutover order must be written down before the transition starts.

## Planned switchover

Use a switchover for maintenance, patching, or testing. It loses no data by design, and it is reversible by switching back.

1. Run the pre-transition checks above on both databases.
2. Validate the standby through the broker (the template does this first).
3. Notify application owners and stop or drain application connections to the primary, so no session is left active to block the switch.
4. Run `dgmgrl/switchover.dgmgrl` with the standby's DB_UNIQUE_NAME filled in.
5. Confirm the new primary is open and the old primary is applying as the new standby. Run the status script on both sides again.
6. Move application connections to the new primary and confirm the application works before declaring the maintenance window over.
7. If the switchover was for maintenance, switch back the same way when the work is done. A configuration left in its swapped state by accident is a common source of confusion in the next incident.

If validation fails, stop. A failed validation is the broker telling you the standby is not ready to become primary, and switching anyway converts a planned maintenance window into an unplanned incident.

## Unplanned failover

Use a failover only when the primary is confirmed unavailable, or its writes are confirmed stopped. This is the precondition, and it is not negotiable: failing over while the old primary can still write creates two databases that both believe they are primary, and the divergence that follows is not repairable by re-running a command.

1. Confirm the primary is down or fenced. "Unreachable from here" is not the same as "down". Check from a second location if the first check is ambiguous.
2. Accept the data loss tradeoff explicitly. In maximum performance mode, or in maximum availability mode during a standby outage, transactions committed on the primary but not yet received by the standby are lost. Name that to the incident owner before running the command, not after.
3. Run `dgmgrl/failover.dgmgrl` with the standby's DB_UNIQUE_NAME filled in. The template performs a complete failover, applying all redo available on the standby before opening it.
4. Confirm the new primary is open, run the status script on it, and move application connections to it.
5. Preserve the old primary's state for diagnosis. Do not restart it into the configuration until the reinstate steps below have been followed.

`FAILOVER IMMEDIATE` exists for the case where the remaining redo cannot be applied and waiting costs more than the data. It is deliberately not in the template, so choosing it requires editing the file and therefore thinking about it.

## Reinstate after failover

The old primary does not rejoin the configuration on its own. After a failover it must be reinstated as the new standby, which means turning it into a standby of the new primary and letting it catch up.

1. Make sure the old primary is truly stopped as a primary and cannot accept writes. If it was fenced, keep it fenced until this step.
2. Flashback Database must have been enabled before the failover for automatic reinstate to work. With it, the broker can reinstate by flashing the old primary back to the failover point and converting it. Without it, the old primary must be rebuilt from a backup of the new primary, which is a longer job and should be planned as one.
3. Reinstate through the broker, then run the status script on both sides and confirm the applied sequence is advancing before declaring the configuration healthy.
4. Update the runbook notes with what actually happened: how long the failover took, how much data was lost if any, and what the reinstate required. The next incident inherits this record.

## Working a gap

A gap means archived logs are missing on the standby: the applied sequence is behind the archived sequence, or the broker reports a gap status. Work it in this order.

1. Read the destination error from the status script. A network error, a full disk on the standby, and a missing log directory are different problems with different fixes, and the error text usually names the right one.
2. Check disk space and permissions on the standby's archive destination. A standby that cannot write an incoming log stops applying, and the gap grows with every log the primary generates.
3. Check whether the missing logs still exist on the primary or in backups. If they do, they can be copied to the standby's archive destination and apply resumes. If they exist only in a backup, restore them to the standby.
4. If the missing logs are gone entirely, close the gap with an incremental backup taken from the standby's current SCN on the primary and applied to the standby (the RMAN roll-forward technique, covered in oracle-rman-backup-recovery). This is the repair of last resort, not the first step, because it costs a backup and a recovery window.
5. After the gap closes, confirm apply is advancing and the gap status clears. A gap that clears and immediately returns is a symptom, not a fix: look for the underlying transport or disk problem.

## Post-transition checks

After any transition, planned or not, confirm all of these before closing the incident or the maintenance window: the new primary is open and accepting writes, the new standby is applying and its applied sequence is advancing, the broker shows no errors, application connections are on the new primary and working, and the protection mode is the one the business was promised. A transition is not complete when the command finishes. It is complete when the configuration is healthy again.

Sample values in this repo are illustrative lab output, not captured results.
