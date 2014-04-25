BEGIN 
	EXECUTE IMMEDIATE 'DROP USER OOHLALOG CASCADE';
	DBMS_OUTPUT.PUT_LINE ('Dropped OOHLALOG user');
EXCEPTION 
	WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE ('Unable to delete OOHLALOG user'); 
END;
/

BEGIN 
	DBMS_NETWORK_ACL_ADMIN.DROP_ACL (acl => 'OOHLALOG_ACL'); 
	DBMS_OUTPUT.PUT_LINE ('Dropped OOHLALOG ACL');
EXCEPTION 
	WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE ('Unable to drop OOHLALOG ACL'); 
END;
/

BEGIN 
	EXECUTE IMMEDIATE 'DROP PUBLIC SYNONYM OOHLALOG_API'; 
	DBMS_OUTPUT.PUT_LINE ('Dropped OOHLALOG_API synonym');
EXCEPTION 
	WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE ('Unable to drop OOHLALOG_API synonym'); 
END;
/

BEGIN DBMS_OUTPUT.PUT_LINE ('FINISHED'); END;
