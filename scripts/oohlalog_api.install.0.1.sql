
------------------------------------------------------------------
--  USER OOHLALOG
------------------------------------------------------------------
CREATE USER OOHLALOG IDENTIFIED BY password DEFAULT TABLESPACE SYSTEM QUOTA 1M ON SYSTEM TEMPORARY TABLESPACE TEMP;
BEGIN DBMS_OUTPUT.PUT_LINE ('Created OOHLALOG user'); END;
------------------------------------------------------------------
--  PRIVS
------------------------------------------------------------------
GRANT CONNECT TO OOHLALOG;
GRANT RESOURCE TO OOHLALOG;
GRANT SELECT ON sys.v_$diag_alert_ext to OOHLALOG;
GRANT EXECUTE ON sys.DBMS_SYSTEM to OOHLALOG;
GRANT EXECUTE ON sys.UTL_INADDR to OOHLALOG;
GRANT EXECUTE ON sys.UTL_HTTP to OOHLALOG;
CREATE SYNONYM OOHLALOG.dbms_system FOR sys.dbms_system;
CREATE SYNONYM OOHLALOG.UTL_HTTP FOR sys.UTL_HTTP;
CREATE SYNONYM OOHLALOG.UTL_INADDR FOR sys.UTL_INADDR;

BEGIN
DBMS_NETWORK_ACL_ADMIN.CREATE_ACL (
acl          => 'OOHLALOG_ACL',
description  => 'OOHLALOG_ACL',
principal    => 'OOHLALOG',
is_grant     => TRUE,
privilege    => 'connect');

DBMS_NETWORK_ACL_ADMIN.ADD_PRIVILEGE (
acl          => 'OOHLALOG_ACL',                
principal    => 'OOHLALOG',
is_grant     => TRUE, 
privilege    => 'connect',
position     => null);


DBMS_NETWORK_ACL_ADMIN.ADD_PRIVILEGE (
acl          => 'OOHLALOG_ACL',                
principal    => 'OOHLALOG',
is_grant     => TRUE, 
privilege    => 'resolve',
position     => null);

DBMS_NETWORK_ACL_ADMIN.ASSIGN_ACL (
acl          => 'OOHLALOG_ACL',                
host         => '*');
COMMIT;

END;

BEGIN DBMS_OUTPUT.PUT_LINE ('Granted OOHLALOG privs'); END;

------------------------------------------------------------------
--  TABLE OOHLALOG_CONFIG
------------------------------------------------------------------

CREATE TABLE OOHLALOG.oohlalog_config
(
   name           VARCHAR2 (255 BYTE),
   VALUE          VARCHAR2 (400 BYTE),
   last_updated   TIMESTAMP (6) WITH TIME ZONE DEFAULT SYSTIMESTAMP
)
NOCACHE
LOGGING;

------------------------------------------------------------------
--  TRIGGER TRG_OLL_CONFIG_UPDATE
------------------------------------------------------------------

CREATE OR REPLACE TRIGGER OOHLALOG.trg_oll_config_update
   BEFORE INSERT OR UPDATE OF name, VALUE, last_updated
   ON OOHLALOG.oohlalog_config
   FOR EACH ROW
BEGIN
   :NEW.last_updated := SYSTIMESTAMP;
END;
/
BEGIN DBMS_OUTPUT.PUT_LINE ('Created OOHLALOG config table'); END;

------------------------------------------------------------------
--  PACKAGE OOHLALOG
------------------------------------------------------------------

CREATE OR REPLACE PACKAGE OOHLALOG.OOHLALOG_API
AS
   ENDPOINT CONSTANT VARCHAR2(40) := 'http://app.oohlalog.com';

   PROCEDURE INCREMENT_COUNTER (NM     IN VARCHAR2,
                                INCR   IN INTEGER := 1,
                                CD     IN VARCHAR2 := NULL);

   PROCEDURE TEST_ALERT_LOG (MSG IN VARCHAR2);

   PROCEDURE LOG_ALERTS;

   PROCEDURE LOG_ALERTS (P_START_TS   IN TIMESTAMP WITH TIME ZONE,
                         P_END_TS     IN TIMESTAMP WITH TIME ZONE);

   PROCEDURE LOG_MESSAGE (P_MESSAGE   IN VARCHAR2,
                          P_LVL       IN VARCHAR2,
                          P_CAT       IN VARCHAR2);

   FUNCTION GET_LAST_ALERT_TS
      RETURN TIMESTAMP WITH TIME ZONE;

   PROCEDURE SET_LAST_ALERT_TS (P_TS IN TIMESTAMP WITH TIME ZONE);

   FUNCTION GET_API_KEY
      RETURN VARCHAR2;

   FUNCTION GET_LAST_ALERT_EXEC
      RETURN TIMESTAMP WITH TIME ZONE;

   PROCEDURE SET_LAST_ALERT_EXEC (P_TS IN TIMESTAMP WITH TIME ZONE);
END;
/

BEGIN DBMS_OUTPUT.PUT_LINE ('Granted OOHLALOG_API pkg spec'); END;


------------------------------------------------------------------
--  PACKAGE BODY OOHLALOG
------------------------------------------------------------------

CREATE OR REPLACE PACKAGE BODY OOHLALOG.OOHLALOG_API
AS
   LOOKBACK_SECS CONSTANT INTEGER := 3;
   
   FUNCTION UNIX_TO_TIMSTAMP (P_UNIX IN NUMBER)
      RETURN DATE
   IS
      r   DATE;
   BEGIN
      DBMS_OUTPUT.PUT_LINE ('Executed OOHLALOG_API.UNIX_TO_TIMSTAMP');

      SELECT (  TIMESTAMP '1970-01-01 00:00:00 GMT'
              + NUMTODSINTERVAL (P_UNIX / 1000, 'SECOND'))
        INTO r
        FROM DUAL;

      RETURN r;
   END;

   FUNCTION TIMESTAMP_TO_UNIX (P_TS TIMESTAMP WITH TIME ZONE)
      RETURN NUMBER
   IS
   BEGIN
      DBMS_OUTPUT.PUT_LINE ('Executed OOHLALOG_API.TIMESTAMP_TO_UNIX');
      RETURN ROUND (
                  (CAST (P_TS AS DATE) - TO_DATE ('01.01.1970', 'dd.mm.yyyy'))
                * (24 * 60 * 60 * 1000));
   END;

   FUNCTION GET_CATEGORY (MSG_TYP IN NUMBER)
      RETURN VARCHAR2
   IS
   BEGIN
      RETURN 'Oracle Alert';
   END;

   FUNCTION GET_LEVEL (MSG_LEVEL IN NUMBER)
      RETURN VARCHAR2
   IS
   BEGIN
      RETURN 'WARN';
   END;

   PROCEDURE TEST_ALERT_LOG (MSG IN VARCHAR2)
   IS
   BEGIN
      DBMS_SYSTEM.ksdwrt (2, MSG);
   END;

   PROCEDURE INCREMENT_COUNTER (NM     IN VARCHAR2,
                                INCR   IN INTEGER := 1,
                                CD     IN VARCHAR2 := NULL)
   IS
      req      UTL_HTTP.REQ;
      resp     UTL_HTTP.RESP;
      VALUE    VARCHAR2 (1024);
      apiKey   VARCHAR2 (100);
      cod      VARCHAR2 (200) := CD;
   BEGIN
      IF cod IS NULL
      THEN
         cod := NM;
      END IF;

      apiKey := GET_API_KEY ();

      DBMS_OUTPUT.PUT_LINE (
            ENDPOINT
         || '/api/counter/increment.json?apiKey='
         || apiKey
         || '&code='
         || REPLACE (REPLACE (cod, ' ', '%20'), '&', '%26')
         || '&name='
         || REPLACE (REPLACE (NM, ' ', '%20'), '&', '%26')
         || '&incr='
         || TO_CHAR (INCR));

      req :=
         UTL_HTTP.BEGIN_REQUEST (
            url      =>    ENDPOINT
                        || '/api/counter/increment.json?apiKey='
                        || apiKey
                        || '&code='
                        || REPLACE (REPLACE (cod, ' ', '%20'), '&', '%26')
                        || '&name='
                        || REPLACE (REPLACE (NM, ' ', '%20'), '&', '%26')
                        || '&incr='
                        || TO_CHAR (INCR),
            method   => 'GET');
      resp := UTL_HTTP.GET_RESPONSE (req);
      UTL_HTTP.END_RESPONSE (resp);
   END;

   PROCEDURE LOG_ALERTS
   IS
      st   TIMESTAMP WITH TIME ZONE;
      ed   TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP - LOOKBACK_SECS / 86400;
   BEGIN
      --OOHLALOG.SET_LAST_ALERT_TS(SYSTIMESTAMP - 20/96);
      st := GET_LAST_ALERT_TS ();
      LOG_ALERTS (st, ed);
      SET_LAST_ALERT_TS (ed);
      SET_LAST_ALERT_EXEC (SYSTIMESTAMP);
      COMMIT;
   END;

   PROCEDURE LOG_ALERTS (P_START_TS   IN TIMESTAMP WITH TIME ZONE,
                         P_END_TS     IN TIMESTAMP WITH TIME ZONE)
   IS
      req      UTL_HTTP.REQ;
      resp     UTL_HTTP.RESP;
      VALUE    VARCHAR2 (1024);
      ip       VARCHAR2 (100);
      HOST     VARCHAR2 (200);
      json     CLOB := '';
      delim    VARCHAR2 (2) := '';
      apiKey   VARCHAR2 (100);
   BEGIN
      DBMS_OUTPUT.PUT_LINE ('Executed OOHLALOG_API.LOG_ALERTS');

      SELECT UTL_INADDR.get_host_address (
                SYS_CONTEXT ('userenv', 'server_host'))
        INTO ip
        FROM DUAL;

      HOST := SYS_CONTEXT ('USERENV', 'SERVER_HOST');
      DBMS_OUTPUT.PUT_LINE ('IP address = ' || ip || ' Host = ' || HOST);

      apiKey := GET_API_KEY ();
      json := '{"apiKey":"' || apiKey || '",' || CHR (10) || '"logs":[';

      FOR r_alert
         IN (SELECT record_id,
                    originating_timestamp,
                    MESSAGE_TEXT,
                    message_level,
                    MESSAGE_TYPE
               FROM sys.v_$diag_alert_ext
              WHERE     originating_timestamp > P_START_TS
                    AND originating_timestamp <= P_END_TS)
      LOOP
         -- ADD batching in configurable batch size
         --json := json || delim || '{"timestamp":'||TO_CHAR(TIMESTAMP_TO_UNIX(r_alert.originating_timestamp))||',"level":"'||GET_LEVEL(r_alert.message_level)||'", "message":"' || REPLACE(REPLACE(r_alert.message_text, chr(10), '\n'),'"', '\"') || '", "hostName":"'||host||'", "category":"'||GET_CATEGORY(r_alert.message_type)||'"}';
         json :=
               json
            || delim
            || '{"level":"'
            || GET_LEVEL (r_alert.message_level)
            || '", "message":"'
            || REPLACE (REPLACE (r_alert.MESSAGE_TEXT, CHR (10), '\n'),
                        '"',
                        '\"')
            || '", "hostName":"'
            || HOST
            || '", "category":"'
            || GET_CATEGORY (r_alert.MESSAGE_TYPE)
            || '"}';
         delim := CHR (10) || ',';
      END LOOP;

      json := json || ']}';
      DBMS_OUTPUT.PUT_LINE (json);

      req :=
         UTL_HTTP.BEGIN_REQUEST (
            url      =>    ENDPOINT
                        || '/api/logging/save.json?apiKey='
                        || apiKey,
            method   => 'POST');
      UTL_HTTP.SET_HEADER (r       => req,
                           name    => 'Content-Type',
                           VALUE   => 'application/json');
      UTL_HTTP.SET_HEADER (r       => req,
                           name    => 'Content-Length',
                           VALUE   => LENGTH (json));
      UTL_HTTP.WRITE_TEXT (r => req, data => json);
      resp := UTL_HTTP.GET_RESPONSE (req);
      --LOOP
      --UTL_HTTP.READ_LINE(resp, value, TRUE);
      --DBMS_OUTPUT.PUT_LINE(value);
      --END LOOP;
      UTL_HTTP.END_RESPONSE (resp);
   END LOG_ALERTS;


   PROCEDURE LOG_MESSAGE (P_MESSAGE   IN VARCHAR2,
                          P_LVL       IN VARCHAR2,
                          P_CAT       IN VARCHAR2)
   IS
      req      UTL_HTTP.REQ;
      resp     UTL_HTTP.RESP;
      VALUE    VARCHAR2 (1024);
      ip       VARCHAR2 (100);
      HOST     VARCHAR2 (200);
      json     CLOB := '';
      delim    VARCHAR2 (2) := '';
      apiKey   VARCHAR2 (100);
   BEGIN
      DBMS_OUTPUT.PUT_LINE ('Executed OOHLALOG_API.LOG_MESSAGE');

      SELECT UTL_INADDR.get_host_address (
                SYS_CONTEXT ('userenv', 'server_host'))
        INTO ip
        FROM DUAL;

      HOST := SYS_CONTEXT ('USERENV', 'SERVER_HOST');
      DBMS_OUTPUT.PUT_LINE ('IP address = ' || ip || ' Host = ' || HOST);

      apiKey := GET_API_KEY ();
      --json := '{"timestamp":'||TO_CHAR(TIMESTAMP_TO_UNIX(SYSTIMESTAMP))||',"level":"'||P_LVL||'", "message":"' || REPLACE(REPLACE(P_MESSAGE, chr(10), '\n'),'"', '\"') || '", "hostName":"'||host||'", "category":"'||P_CAT||'"}';
      json :=
            '{"level":"'
         || P_LVL
         || '", "message":"'
         || REPLACE (REPLACE (P_MESSAGE, CHR (10), '\n'), '"', '\"')
         || '", "hostName":"'
         || HOST
         || '", "category":"'
         || P_CAT
         || '"}';

      DBMS_OUTPUT.PUT_LINE (json);

      req :=
         UTL_HTTP.BEGIN_REQUEST (
            url      =>    ENDPOINT
                        || '/api/logging/save.json?apiKey='
                        || apiKey,
            method   => 'POST');
      UTL_HTTP.SET_HEADER (r       => req,
                           name    => 'Content-Type',
                           VALUE   => 'application/json');
      UTL_HTTP.SET_HEADER (r       => req,
                           name    => 'Content-Length',
                           VALUE   => LENGTH (json));
      UTL_HTTP.WRITE_TEXT (r => req, data => json);
      resp := UTL_HTTP.GET_RESPONSE (req);
      --LOOP
      --UTL_HTTP.READ_LINE(resp, value, TRUE);
      --DBMS_OUTPUT.PUT_LINE(value);
      --END LOOP;
      UTL_HTTP.END_RESPONSE (resp);
   END LOG_MESSAGE;

   FUNCTION GET_LAST_ALERT_TS
      RETURN TIMESTAMP WITH TIME ZONE
   IS
      v   VARCHAR2 (400);
      r   TIMESTAMP WITH TIME ZONE;
   BEGIN
      DBMS_OUTPUT.PUT_LINE ('Executed OOHLALOG_API.GET_LAST_ALERT_TS');

      SELECT VALUE
        INTO v
        FROM OOHLALOG.OOHLALOG_CONFIG
       WHERE NAME = 'lastAlertTs';

      r := CAST (UNIX_TO_TIMSTAMP (TO_NUMBER (v)) AS TIMESTAMP);
      RETURN r;
   EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
         RETURN SYSTIMESTAMP;
   END;

   PROCEDURE SET_LAST_ALERT_TS (P_TS IN TIMESTAMP WITH TIME ZONE)
   IS
      v   VARCHAR2 (400);
   BEGIN
      DBMS_OUTPUT.PUT_LINE ('Executed OOHLALOG.SET_LAST_ALERT_TS');
      v := TO_CHAR (TIMESTAMP_TO_UNIX (P_TS));

      UPDATE OOHLALOG.OOHLALOG_CONFIG
         SET VALUE = v
       WHERE NAME = 'lastAlertTs';

      INSERT INTO OOHLALOG_CONFIG (NAME, VALUE)
         SELECT 'lastAlertTs', v
           FROM DUAL
          WHERE 0 = (SELECT COUNT (*)
                       FROM OOHLALOG_CONFIG
                      WHERE NAME = 'lastAlertTs');

      NULL;
   END;

   FUNCTION GET_API_KEY
      RETURN VARCHAR2
   IS
      v   VARCHAR2 (400);
   BEGIN
      DBMS_OUTPUT.PUT_LINE ('Executed OOHLALOG_API.GET_API_KEY');

      SELECT VALUE
        INTO v
        FROM OOHLALOG.OOHLALOG_CONFIG
       WHERE NAME = 'apiKey';

      RETURN v;
   END;

   FUNCTION GET_LAST_ALERT_EXEC
      RETURN TIMESTAMP WITH TIME ZONE
   IS
      v   VARCHAR2 (400);
      r   TIMESTAMP WITH TIME ZONE;
   BEGIN
      DBMS_OUTPUT.PUT_LINE ('Executed OOHLALOG_API.GET_LAST_ALERT_EXEC');

      SELECT VALUE
        INTO v
        FROM OOHLALOG.OOHLALOG_CONFIG
       WHERE NAME = 'lastAlertExec';

      r := CAST (UNIX_TO_TIMSTAMP (TO_NUMBER (v)) AS TIMESTAMP);
      RETURN r;
   EXCEPTION
      WHEN NO_DATA_FOUND
      THEN
         RETURN SYSTIMESTAMP;
   END;

   PROCEDURE SET_LAST_ALERT_EXEC (P_TS IN TIMESTAMP WITH TIME ZONE)
   IS
      v   VARCHAR2 (400);
   BEGIN
      DBMS_OUTPUT.PUT_LINE ('Executed OOHLALOG_API.SET_LAST_ALERT_EXEC');
      v := TO_CHAR (TIMESTAMP_TO_UNIX (P_TS));

      UPDATE OOHLALOG.OOHLALOG_CONFIG
         SET VALUE = v
       WHERE NAME = 'lastAlertExec';

      INSERT INTO OOHLALOG.OOHLALOG_CONFIG (NAME, VALUE)
         SELECT 'lastAlertExec', v
           FROM DUAL
          WHERE 0 = (SELECT COUNT (*)
                       FROM OOHLALOG_CONFIG
                      WHERE NAME = 'lastAlertExec');
   END;
END;
/
BEGIN DBMS_OUTPUT.PUT_LINE ('Granted OOHLALOG_API pkg body'); END;


GRANT EXECUTE ON OOHLALOG.OOHLALOG_API TO public;

CREATE PUBLIC SYNONYM OOHLALOG_API FOR OOHLALOG.OOHLALOG_API;

BEGIN DBMS_OUTPUT.PUT_LINE ('Granted access to OOHLALOG_API'); END;

BEGIN DBMS_OUTPUT.PUT_LINE ('FINISHED'); END;


