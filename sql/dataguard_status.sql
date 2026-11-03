-- ============================================================================
-- dataguard_status.sql
--
-- Purpose:
--   Answers one question before an incident does: is the standby keeping
--   up? Reports the database role and protection mode, transport and
--   apply lag, the state of each standby archive destination including
--   any gap, the standby redo logs, and the managed recovery processes.
--   Run it on the primary to see whether redo is reaching the standby,
--   and on the standby to see whether apply is keeping up.
--
-- Usage:
--   sqlplus / as sysdba @dataguard_status.sql
--
--   To change the thresholds, edit the DEFINE lines below. The
--   unapplied-log threshold default is 5 archived logs behind the
--   applied sequence. Tighten it if the recovery point objective
--   demands a smaller gap.
--
-- Exit code:
--   0 - no destination reports a gap or an error, unapplied logs are
--       within threshold, and (on a standby) a managed recovery
--       process is running
--   2 - any of those checks fails
--
-- Notes:
--   Read-only. Lag figures in section 2 come from V$DATAGUARD_STATS
--   as text (for example "0 seconds"); the numeric verdict uses the
--   archived-minus-applied sequence gap from V$ARCHIVE_DEST_STATUS,
--   which is comparable across configurations. On a database with no
--   standby destinations, sections 3 and 5 report no rows and the
--   verdict reflects that there is nothing to monitor, not that the
--   configuration is healthy: check section 1 for the role first.
--   V$ARCHIVE_DEST_STATUS has one row per destination; only
--   destinations with TARGET 'STANDBY' are shown. GAP_STATUS values
--   other than 'NO GAP' mean archived logs are missing on the
--   standby. See docs/switchover-failover-runbook.md for how to work
--   a gap.
--   Reviewed; not executed against a live Oracle instance.
-- ============================================================================

SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 160
SET TRIMSPOOL ON
SET TAB OFF

-- ----------------------------------------------------------------------------
-- Thresholds. Edit to match local recovery objectives.
-- ----------------------------------------------------------------------------
DEFINE max_unapplied_logs = 5

PROMPT
PROMPT === 1. Role and protection ===
COLUMN database_role    FORMAT A18 HEADING 'ROLE'
COLUMN protection_mode  FORMAT A20 HEADING 'PROTECTION MODE'
COLUMN protection_level FORMAT A20 HEADING 'PROTECTION LEVEL'
COLUMN open_mode        FORMAT A18 HEADING 'OPEN MODE'
COLUMN switchover_status FORMAT A22 HEADING 'SWITCHOVER STATUS'
COLUMN force_logging    FORMAT A10 HEADING 'FORCE LOG'
COLUMN flashback_on     FORMAT A10 HEADING 'FLASHBACK'

SELECT database_role,
       protection_mode,
       protection_level,
       open_mode,
       switchover_status,
       force_logging,
       flashback_on
  FROM v$database;

PROMPT
PROMPT === 2. Transport and apply lag ===
PROMPT (V$DATAGUARD_STATS reports lag as text; see section 3 for the
PROMPT  numeric sequence gap used by the verdict.)
COLUMN stat_name  FORMAT A22 HEADING 'METRIC'
COLUMN stat_value FORMAT A22 HEADING 'VALUE'
COLUMN stat_unit  FORMAT A12 HEADING 'UNIT'

SELECT name  AS stat_name,
       value AS stat_value,
       unit  AS stat_unit
  FROM v$dataguard_stats
 WHERE name IN ('transport lag', 'apply lag',
                'apply rate', 'redo generation rate')
 ORDER BY name;

PROMPT
PROMPT === 3. Standby archive destinations ===
COLUMN dest_name       FORMAT A24 HEADING 'DESTINATION'
COLUMN dest_status     FORMAT A10 HEADING 'STATUS'
COLUMN recovery_mode   FORMAT A18 HEADING 'RECOVERY MODE'
COLUMN gap_status      FORMAT A16 HEADING 'GAP STATUS'
COLUMN archived_seq    FORMAT 99999990 HEADING 'ARCHIVED SEQ'
COLUMN applied_seq     FORMAT 99999990 HEADING 'APPLIED SEQ'
COLUMN unapplied_logs  FORMAT 99990 HEADING 'UNAPPLIED'
COLUMN dest_error      FORMAT A40 HEADING 'ERROR'

SELECT dest_name,
       status           AS dest_status,
       recovery_mode,
       gap_status,
       archived_seq#    AS archived_seq,
       applied_seq#     AS applied_seq,
       CASE WHEN archived_seq# IS NOT NULL
             AND applied_seq# IS NOT NULL
            THEN archived_seq# - applied_seq#
            ELSE NULL
       END              AS unapplied_logs,
       error            AS dest_error
  FROM v$archive_dest_status
 WHERE target = 'STANDBY'
 ORDER BY dest_id;

PROMPT
PROMPT === 4. Standby redo logs ===
PROMPT (Empty on a primary with no standby redo log groups configured,
PROMPT  or on a standby that has none. Standby redo logs are required
PROMPT  for real-time apply.)
COLUMN log_group  FORMAT 9990 HEADING 'GROUP'
COLUMN log_thread FORMAT 9990 HEADING 'THREAD'
COLUMN log_seq    FORMAT 99999990 HEADING 'SEQUENCE'
COLUMN log_bytes  FORMAT 999,999,990 HEADING 'BYTES'
COLUMN log_used   FORMAT 999,999,990 HEADING 'USED'
COLUMN log_status FORMAT A12 HEADING 'STATUS'
COLUMN archived   FORMAT A10 HEADING 'ARCHIVED'

SELECT group#    AS log_group,
       thread#   AS log_thread,
       sequence# AS log_seq,
       bytes     AS log_bytes,
       used      AS log_used,
       status    AS log_status,
       archived
  FROM v$standby_log
 ORDER BY group#;

PROMPT
PROMPT === 5. Managed recovery processes ===
PROMPT (On a standby, expect an MRP process applying logs and RFS
PROMPT  processes receiving them. Empty on a primary that is not also
PROMPT  a standby, and on a standby with recovery stopped.)
COLUMN process_name   FORMAT A10 HEADING 'PROCESS'
COLUMN process_status FORMAT A16 HEADING 'STATUS'
COLUMN proc_thread    FORMAT 9990 HEADING 'THREAD'
COLUMN proc_seq       FORMAT 99999990 HEADING 'SEQUENCE'
COLUMN proc_block     FORMAT 999999990 HEADING 'BLOCK'
COLUMN client_process FORMAT A12 HEADING 'CLIENT'

SELECT process        AS process_name,
       status         AS process_status,
       thread#        AS proc_thread,
       sequence#      AS proc_seq,
       block#         AS proc_block,
       client_process
  FROM v$managed_standby
 ORDER BY process, thread#;

PROMPT
PROMPT === Verdict ===

COLUMN exit_code NOPRINT NEW_VALUE v_exit_code
SELECT CASE
         WHEN EXISTS (SELECT 1
                        FROM v$archive_dest_status
                       WHERE target = 'STANDBY'
                         AND gap_status IS NOT NULL
                         AND gap_status <> 'NO GAP') THEN 2
         WHEN EXISTS (SELECT 1
                        FROM v$archive_dest_status
                       WHERE target = 'STANDBY'
                         AND error IS NOT NULL) THEN 2
         WHEN EXISTS (SELECT 1
                        FROM v$archive_dest_status
                       WHERE target = 'STANDBY'
                         AND archived_seq# IS NOT NULL
                         AND applied_seq# IS NOT NULL
                         AND archived_seq# - applied_seq# > &max_unapplied_logs) THEN 2
         WHEN (SELECT database_role FROM v$database) LIKE '%STANDBY%'
              AND NOT EXISTS (SELECT 1
                                FROM v$managed_standby
                               WHERE process LIKE 'MRP%'
                                 AND status IN ('APPLYING_LOG', 'IDLE',
                                                'WAIT_FOR_LOG', 'WAIT_FOR_GAP')) THEN 2
         ELSE 0
       END AS exit_code
  FROM dual;

PROMPT
PROMPT Done. Exit code: &v_exit_code (0 = standby keeping up, 2 = a check failed)
PROMPT A clean report means redo is flowing and apply is keeping up.
PROMPT It does not prove a failover will succeed; test the transition.
EXIT &v_exit_code
