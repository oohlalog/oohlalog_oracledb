DECLARE
	API_KEY VARCHAR2 (100) := '1adec358-09bd-49b5-834c-8343c3034a9e';
BEGIN

INSERT INTO OOHLALOG.oohlalog_config (NAME, VALUE)
VALUES ('apiKey', API_KEY);

-- TODO put in endpoint, lookback secs, etc

END;
/
