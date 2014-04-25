BEGIN
  DBMS_SCHEDULER.CREATE_JOB (
   job_name           =>  'OOHLALOG_ALERT_LOG_JOB',
   job_type           =>  'STORED_PROCEDURE',
   job_action         =>  'OOHLALOG.OOHLALOG.LOG_ALERTS',
   start_date         =>  SYSTIMESTAMP,
   repeat_interval    =>  'FREQ=SECONDLY;INTERVAL=10', /* every 10s */
   end_date           =>  NULL,
   enabled            =>  TRUE,
   auto_drop          =>  FALSE,
   comments           =>  'Job to foward alert_log entries into OohLaLog cloud logging service');
  DBMS_OUTPUT.PUT_LINE ('Created OOHLALOG_ALERT_LOG_JOB');
EXCEPTION 
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE ('Unable to create OOHLALOG_ALERT_LOG_JOB'); 
END;
/