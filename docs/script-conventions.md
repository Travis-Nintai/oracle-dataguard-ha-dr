# Script conventions

Every script in this repo follows the same shape so it is predictable to run and safe to schedule:

- Header comment: purpose, usage, and exit codes for SQL scripts. Nothing else in the header.
- Thresholds as `DEFINE` variables at the top of SQL scripts, with defaults noted in the comment.
- No hard-coded hostnames, SIDs, service names, credentials, or paths. Examples use placeholders like `$ORACLE_SID`, `<SERVICE_NAME>`, `<PRIMARY_DB_UNIQUE_NAME>`, and `<STANDBY_DB_UNIQUE_NAME>`.
- SQL scripts are read-only. DGMGRL scripts are a different category: a switchover reverses the roles of the primary and standby, and a failover promotes the standby. Every DGMGRL file says so in its header, and nothing here runs a transition without validation steps first. Test transitions on a lab configuration.
- DGMGRL files are templates, not turnkey jobs. Read them, replace the placeholders, and check the commands against your configuration before running them.
- Exit code 0 on success; non-zero on failure or threshold breach, documented per script.
- Output is plain text, readable in a terminal and greppable in logs.

New scripts should add a usage example to the README.
