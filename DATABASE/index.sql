-- AUTHOR:Tibay Vian 
-- DATE: 2019-11-20
DECLARE
V_last_name EMPLOYEES.LAST_NAME%TYPE;
BEGIN
    BEGIN
        SELECT LAST_NAME
        INTO V_LAST_NAME 
        FROM EMPLOYEES
        WHERE EMPLOYEE_ID = 500;

        EXCEPTION
        WHEN TOO_MANY_ROWS THEN
           DBMS_OUTPUT.PUT_LINE('MESSAGE 1');
           END;

           DBMS_OUTPUT.PUT_LINE('MESSAGE 2');

           EXCEPTION
           WHEN OTHERS THEN 
              DBMS_OUTPUT.PUT_LINE('MESSAGE 3');
END;
/
CREATE OR REPLACE PACKAGE VRT_LENDING_PACKAGE AS
    -- Constants
    MAX_LOAN_AMOUNT CONSTANT NUMBER := 1000000;  -- Maximum allowed loan amount

    -- Cursor to fetch loan details
   CURSOR loan_cursor IS
    SELECT LOAN_ID, LOAN_AMOUNT FROM loan;



    -- Function to get loan balance
    FUNCTION get_loan_balance(p_loan_number NUMBER) RETURN NUMBER;

    -- Procedure to apply for a new loan
    PROCEDURE apply_loan(p_customer_id NUMBER, p_loan_amount NUMBER);

    -- Procedure to process a loan payment
    PROCEDURE process_payment(p_loan_number NUMBER, p_payment_amount NUMBER);

END VRT_LENDING_PACKAGE;
/
CREATE OR REPLACE PACKAGE BODY VRT_LENDING_PACKAGE AS

    -- Function to get the remaining loan balance
    FUNCTION get_loan_balance(p_loan_number NUMBER) RETURN NUMBER IS
        v_balance NUMBER := 0;
    BEGIN
        SELECT loan_amount - NVL(SUM(payment_amount), 0)
        INTO v_balance
        FROM loan
        LEFT JOIN payment ON loan.loan_id = payment.loan_number
        WHERE loan.loan_id = p_loan_number
        GROUP BY loan_amount;

        RETURN v_balance;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;  -- No loan found
    END get_loan_balance;

    -- Procedure to apply for a new loan
    PROCEDURE apply_loan(p_customer_id NUMBER, p_loan_amount NUMBER) IS
    BEGIN
        -- Check if loan amount exceeds the maximum
        IF p_loan_amount > MAX_LOAN_AMOUNT THEN
            RAISE_APPLICATION_ERROR(-20001, 'Loan amount exceeds the allowed limit.');
        END IF;

        -- Insert new loan record
        INSERT INTO loan (loan_id, loan_amount, application_id)
        VALUES (loan_seq.NEXTVAL, p_loan_amount, p_customer_id);

        COMMIT;
    END apply_loan;

    -- Procedure to process a loan payment
    PROCEDURE process_payment(p_loan_number NUMBER, p_payment_amount NUMBER) IS
        v_balance NUMBER;
    BEGIN
        -- Get the current loan balance
        v_balance := get_loan_balance(p_loan_number);

        -- Check if the payment amount is valid
        IF v_balance IS NULL THEN
            RAISE_APPLICATION_ERROR(-20002, 'Loan not found.');
        ELSIF p_payment_amount > v_balance THEN
            RAISE_APPLICATION_ERROR(-20003, 'Payment exceeds remaining loan balance.');
        END IF;

        -- Insert payment record
        INSERT INTO payment (payment_number, loan_number, payment_amount, payment_date)
        VALUES (payment_seq.NEXTVAL, p_loan_number, p_payment_amount, SYSDATE);

        COMMIT;
    END process_payment;

END VRT_LENDING_PACKAGE;
/

SELECT TABLE_NAME FROM USER_TABLES WHERE TABLE_NAME = 'LOAN';
SELECT OBJECT_NAME, OBJECT_TYPE FROM USER_OBJECTS WHERE OBJECT_NAME = 'LOAN';
SELECT OWNER, TABLE_NAME FROM ALL_TABLES WHERE TABLE_NAME = 'LOAN';

CREATE OR REPLACE TRIGGER prevent_weekend_dml_loan
BEFORE INSERT OR UPDATE OR DELETE ON LOAN
FOR EACH ROW
DECLARE
    v_day_of_week NUMBER;
BEGIN
    -- Get the current day of the week (1 = Sunday, 7 = Saturday)
    SELECT TO_CHAR(SYSDATE, 'D') INTO v_day_of_week FROM DUAL;

    -- Restrict changes on Saturday (7) and Sunday (1)
    IF v_day_of_week IN (1, 7) THEN
        RAISE_APPLICATION_ERROR(-20010, 'DML operations on the LOAN table are not allowed during weekends.');
    END IF;
END prevent_weekend_dml_loan;
/
SELECT TRIGGER_NAME, TABLE_NAME 
FROM USER_TRIGGERS
WHERE TRIGGER_NAME = 'PREVENT_WEEKEND_DML';
/
CREATE OR REPLACE TRIGGER trg_order_audit
AFTER INSERT OR UPDATE OR DELETE ON ORDERS
FOR EACH ROW
DECLARE
    v_action_type VARCHAR2(10);
BEGIN
    -- Assign action type based on the trigger event
    IF INSERTING THEN
        v_action_type := 'INSERT';
    ELSIF UPDATING THEN
        v_action_type := 'UPDATE';
    ELSIF DELETING THEN
        v_action_type := 'DELETE';
    END IF;

    -- Insert audit log
    INSERT INTO ORDER_AUDIT_LOG (ORDER_ID, ACTION_TYPE, CHANGED_BY, CHANGED_AT)
    VALUES (:OLD.ORDER_ID, v_action_type, USER, SYSTIMESTAMP);
END;
/
SELECT trigger_name, status 
FROM user_triggers 
WHERE trigger_name = 'ORDER_AUDIT_TRIGGER';
SHOW ERRORS TRIGGER ADMIN.ORDER_AUDIT_TRIGGER;
CREATE OR REPLACE TRIGGER ORDER_AUDIT_TRIGGER
AFTER INSERT OR DELETE OR UPDATE ON ORDERS
FOR EACH ROW
DECLARE
    v_user VARCHAR2(100);
    v_operation_type VARCHAR2(10);
BEGIN
    SELECT USER INTO v_user FROM DUAL;

    IF INSERTING THEN
        v_operation_type := 'INSERT';
    ELSIF UPDATING THEN
        v_operation_type := 'UPDATE';
    ELSIF DELETING THEN
        v_operation_type := 'DELETE';
    END IF;

    INSERT INTO ORDER_AUDIT (AUDIT_ID, ORDER_ID, OPERATION_TYPE, MODIFIED_BY, MODIFIED_AT)
    VALUES (
        ORDER_AUDIT_SEQ.NEXTVAL, 
        :NEW.ORDER_ID, 
        v_operation_type, 
        v_user, 
        SYSDATE
    );
END;
/SELECT TRIGGER_NAME, TABLE_NAME, STATUS
FROM USER_TRIGGERS
WHERE TRIGGER_NAME = 'ORDER_AUDIT_TRIGGER';


ALTER TRIGGER ORDER_AUDIT_TRIGGER COMPILE;

CREATE OR REPLACE TRIGGER PREVENT_OVER_BORROWING_TRG
BEFORE INSERT OR UPDATE ON LOANS
FOR EACH ROW
DECLARE
    TOTAL_LOAN_AMOUNT NUMBER;
    MAX_LOAN_LIMIT NUMBER := 50000; -- Example limit
BEGIN
    SELECT SUM(AMOUNT) INTO TOTAL_LOAN_AMOUNT 
    FROM LOANS 
    WHERE BORROWER_ID = :NEW.BORROWER_ID;

    IF TOTAL_LOAN_AMOUNT + :NEW.AMOUNT > MAX_LOAN_LIMIT THEN
        RAISE_APPLICATION_ERROR(-20001, 'Loan limit exceeded!');
    END IF;
END;
/

CREATE OR REPLACE TRIGGER UPDATE_LOAN_STATUS_TRG
AFTER UPDATE ON PAYMENTS
FOR EACH ROW
BEGIN
    UPDATE LOANS
    SET STATUS = 
        CASE 
            WHEN (SELECT SUM(AMOUNT_PAID) FROM PAYMENTS WHERE LOAN_ID = :NEW.LOAN_ID) >= 
                 (SELECT AMOUNT FROM LOANS WHERE LOAN_ID = :NEW.LOAN_ID) 
            THEN 'PAID'
            ELSE 'PENDING'
        END
    WHERE LOAN_ID = :NEW.LOAN_ID;
END;
/










