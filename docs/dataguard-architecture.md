# Data Guard architecture

A physical standby is a block-for-block copy of the primary, kept current by applying the primary's redo. That one sentence carries most of the design decisions in this repo: everything here exists to prove the copy is current, to choose how much loss is acceptable when it is not, and to make the day the roles reverse boring instead of dramatic.

## The pieces

The primary generates redo and ships it to the standby. The standby receives it through RFS processes, writes it to standby redo logs when real-time apply is in use, and applies it through the managed recovery process (MRP). The standby's applied sequence number is the honest measure of how current it is. Everything else, including lag figures, is derived from that.

A standby without standby redo logs can still apply archived logs, but it cannot do real-time apply, and it cannot run in maximum protection mode. If the design calls for either, standby redo log groups come first, sized and counted to match the primary's online redo logs plus one extra group per thread.

Force logging matters more than it looks. A standby only replays what was logged. Any operation that bypasses redo logging on the primary (a direct-path load run without force logging, for example) creates a block the standby never sees, and the first sign of it is usually a corrupt block found during a failover test. Force logging on the primary closes that class of problem at the cost of the redo volume, which is the right trade for a database whose standby is supposed to be a faithful copy.

## Redo transport

Transport has two axes, and they are independent. The first is synchronicity: SYNC sends redo to the standby and waits for acknowledgment before the primary transaction commits, ASYNC sends it and does not wait. The second is affirmation: AFFIRM waits for the redo to be written to disk on the standby, NOAFFIRM accepts receipt into memory. SYNC with AFFIRM is the strongest combination and the slowest; ASYNC with NOAFFIRM is the weakest and the fastest. Most real configurations sit in the middle, and the protection mode chooses the combination.

Transport is also where distance shows up. SYNC across a high-latency link costs primary commit latency directly, which is why a far sync instance exists: a lightweight standby placed near the primary that receives redo synchronously and forwards it asynchronously to a distant standby. It buys zero data loss without paying cross-continent latency on every commit, at the cost of another instance to run.

## Protection modes

The protection mode is the data loss contract, stated in advance so nobody has to negotiate it during an outage.

Maximum protection pairs SYNC transport with AFFIRM and guarantees zero data loss. The price is availability: if the last standby that can acknowledge becomes unavailable, the primary shuts down rather than continue writing transactions the standby has not confirmed. That is the correct behavior for the contract, and the wrong behavior for a database whose uptime matters more than its last transaction. Choose it deliberately.

Maximum availability also uses SYNC transport, so under normal operation it also loses nothing. The difference is what happens when the standby disappears: the primary keeps running, accepting that it may now diverge from the standby. When the standby returns, it resynchronizes, but any transaction committed during the outage may not be on the standby if a failover happens in that window. This is the usual choice when both zero loss and uptime matter, because it gives zero loss in the common case and uptime in the rare one.

Maximum performance uses ASYNC transport and makes no data loss promise. The standby trails the primary by however much redo is in flight, and a failover loses whatever had not arrived. It is the right choice when the standby exists for reporting, for surviving a site loss with a small and accepted gap, or when the link cannot support SYNC at all. It is the wrong choice when someone has promised zero loss without reading this paragraph.

Switching modes is a broker operation, but switching from maximum performance to maximum availability or protection is not free: the standby must be in sync first, and the primary takes on the SYNC latency immediately. Test the mode change under load before promising it.

## The broker

The Data Guard broker (DGMGRL) manages the configuration as a unit: one command shows the whole configuration, one command switches roles, one command fails over. Managing the same configuration by hand, with log archive destinations set directly and no broker, works until the day it does not, usually because a destination was changed on one side and not the other. The broker also owns fast-start failover, which is the next section.

The broker keeps its configuration in files on each database, and the databases must be able to reach each other over the network with the broker's listener configuration in place. A broker that cannot connect to a database reports it as an error, not as silence, which is one reason to run the show configuration template on a schedule rather than only when something looks wrong.

## Fast-start failover

Fast-start failover is the broker promoting the standby automatically when the primary is unreachable, without a human issuing the failover command. It needs three things: an observer process watching the configuration, a protection mode of maximum availability or maximum protection, and a threshold for how long the primary may be unresponsive before the observer acts. It also needs Flashback Database enabled on both sides if the old primary is to be reinstated automatically afterward.

Automatic failover trades one risk for another. It removes the human delay, which is often the longest part of an outage, but it can also act on a network partition rather than a real failure, promoting a standby while the old primary is still alive and serving writes. The threshold, the observer placement, and the network design are what keep that from happening, and they deserve the same attention as the failover command itself.

## Licensing notes

Data Guard is an Enterprise Edition feature. The broker is included with it. Active Data Guard is a separately licensed option, and it is what enables real-time query on an open physical standby, automatic block repair between primary and standby, and a few other standby-side capabilities. A standby opened read-only without Active Data Guard is not a supported configuration for production query offload, so check the license before pointing reporting at it. Flashback Database, used for reinstate after failover, needs Enterprise Edition. As with every licensed feature in this portfolio, verify the current licensing terms before building a design on them.

## What good looks like

A healthy configuration shows the same story from both sides: the broker reports no errors, the status script reports no gaps and no errors, apply lag is small and stable rather than small and growing, and the protection mode matches the contract the business was given. A standby whose lag is small but growing is not healthy; it is a standby falling behind slowly, and the cause is usually redo generation outpacing apply, or an archive destination error that has not yet produced a gap. The status script exists to catch the second case early, and the runbook exists for the first.

Sample values in this repo are illustrative lab output, not captured results.
