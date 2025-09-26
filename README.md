# PAN-Number-Validation-Dataset-SQL

-- -----------------------------------------------------------
--  PAN NUMBER VALIDATION PROJECT (PostgreSQL)
--  File: pan_validation.sql
-- -----------------------------------------------------------

-- 1) Create raw table to hold incoming PAN values
CREATE TABLE IF NOT EXISTS sgt_pan_numbers_dataset (
    pan_number text
);


-- 2) (Optional) Insert some test rows to try the logic quickly
--    You can COMMENT OUT these inserts when running on your real dataset.
INSERT INTO sgt_pan_numbers_dataset (pan_number) VALUES
('ABCDE1234F'),
('AABCD1234E'),
('VWXYZ1234A'),
('abcde1234f'),
('  ABCDE1234F  '),
('1234567890'),
(NULL),
(''),
('AZZZZ1111B'),
('MNOPQ1234Z'),
('XYZAB1234K'),
('AAAAA1111A'); -- add any more for testing


-- 3) Basic exploration queries

-- how many records loaded
SELECT COUNT(*) AS total_records FROM sgt_pan_numbers_dataset;

-- show NULL or empty pan_numbers
SELECT * FROM sgt_pan_numbers_dataset
 WHERE pan_number IS NULL
    OR trim(pan_number) = '';

-- duplicates (exact raw values)
SELECT pan_number, COUNT(*) AS cnt
FROM sgt_pan_numbers_dataset
GROUP BY pan_number
HAVING COUNT(*) > 1
ORDER BY cnt DESC;


-- 4) Check for leading/trailing spaces (rows where TRIM changes value)
SELECT *
FROM sgt_pan_numbers_dataset
WHERE pan_number IS NOT NULL
  AND pan_number <> trim(pan_number);


-- 5) Check for lowercase (rows where UPPER changes value)
SELECT *
FROM sgt_pan_numbers_dataset
WHERE pan_number IS NOT NULL
  AND pan_number <> upper(pan_number);


-- 6) Create a cleaned set (distinct, trimmed, uppercased, remove null/empty)
--    This can be a materialized table or a view. Here we create a cleaned table.
DROP TABLE IF EXISTS sgt_pan_numbers_cleaned;
CREATE TABLE sgt_pan_numbers_cleaned AS
SELECT DISTINCT upper(trim(pan_number)) AS pan_number
FROM sgt_pan_numbers_dataset
WHERE pan_number IS NOT NULL
  AND trim(pan_number) <> '';

-- add an index for fast lookups (optional)
CREATE UNIQUE INDEX IF NOT EXISTS idx_sgt_pan_cleaned_pan ON sgt_pan_numbers_cleaned (pan_number);


-- 7) Create PL/pgSQL functions for checks
--    a) function to detect any adjacent identical characters (e.g., "AABCD" -> true)
CREATE OR REPLACE FUNCTION fn_check_adjacent_characters(p_str text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    i int;
    s_len int;
BEGIN
    IF p_str IS NULL THEN
        RETURN false;
    END IF;

    s_len := char_length(p_str);
    IF s_len < 2 THEN
        RETURN false;
    END IF;

    FOR i IN 1..(s_len - 1) LOOP
        IF substr(p_str, i, 1) = substr(p_str, i + 1, 1) THEN
            RETURN true; -- found adjacent repetition
        END IF;
    END LOOP;

    RETURN false;
END;
$$;


--    b) function to detect if all adjacent characters are strictly sequential
--       (e.g., "ABCDE" -> true, "1234" -> true, "AXDGE" -> false)
CREATE OR REPLACE FUNCTION fn_check_sequential_characters(p_str text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    i int;
    s_len int;
BEGIN
    IF p_str IS NULL THEN
        RETURN false;
    END IF;

    s_len := char_length(p_str);
    IF s_len < 2 THEN
        RETURN false;
    END IF;

    FOR i IN 1..(s_len - 1) LOOP
        IF ascii(substr(p_str, i + 1, 1)) - ascii(substr(p_str, i, 1)) <> 1 THEN
            RETURN false; -- not a full sequence
        END IF;
    END LOOP;

    RETURN true; -- all adjacent increments by 1
END;
$$;


-- Quick function tests (run and inspect)
SELECT fn_check_adjacent_characters('AABCD') AS adj_AABCD;  -- expected true
SELECT fn_check_adjacent_characters('ABCDE') AS adj_ABCDE;  -- expected false
SELECT fn_check_sequential_characters('ABCDE') AS seq_ABCDE; -- expected true
SELECT fn_check_sequential_characters('1234') AS seq_1234;   -- expected true
SELECT fn_check_sequential_characters('AXDGE') AS seq_AXDGE; -- expected false


-- 8) Regex check: valid PAN pattern is 5 letters, 4 digits, 1 letter
--    Show rows that satisfy pattern
SELECT pan_number
FROM sgt_pan_numbers_cleaned
WHERE pan_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]$';


-- 9) Build a view that classifies each cleaned PAN as Valid / Invalid
--    Validation rules used (example):
--      - matches regex ^[A-Z]{5}[0-9]{4}[A-Z]$
--      - no adjacent identical characters anywhere
--      - first 5 characters not fully sequential (e.g., "ABCDE")
--      - middle 4 digits not fully sequential (e.g., "1234")  -- optional rule
DROP VIEW IF EXISTS vw_valid_invalid_pans;
CREATE OR REPLACE VIEW vw_valid_invalid_pans AS
WITH cte_cleaned AS (
    SELECT pan_number
    FROM sgt_pan_numbers_cleaned
),
cte_valid AS (
    SELECT pan_number
    FROM cte_cleaned
    WHERE pan_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'
      AND fn_check_adjacent_characters(pan_number) = false
      /* Check first 5 letters not sequential */
      AND fn_check_sequential_characters(substr(pan_number, 1, 5)) = false
      /* OPTIONAL: check middle 4 digits not sequential (uncomment if desired) */
      AND fn_check_sequential_characters(substr(pan_number, 6, 4)) = false
)
SELECT c.pan_number,
       CASE WHEN v.pan_number IS NOT NULL THEN 'Valid PAN' ELSE 'Invalid PAN' END AS status
FROM cte_cleaned c
LEFT JOIN cte_valid v USING (pan_number);


-- 10) Query view
SELECT * FROM vw_valid_invalid_pans ORDER BY pan_number LIMIT 50;


-- 11) Summary report (counts)
WITH summary AS (
    SELECT
      (SELECT COUNT(*) FROM sgt_pan_numbers_dataset) AS total_raw_records,
      (SELECT COUNT(*) FROM sgt_pan_numbers_cleaned) AS total_cleaned_records,
      (SELECT COUNT(*) FROM vw_valid_invalid_pans WHERE status = 'Valid PAN') AS total_valid_pans,
      (SELECT COUNT(*) FROM vw_valid_invalid_pans WHERE status = 'Invalid PAN') AS total_invalid_pans
)
SELECT
    total_raw_records,
    total_cleaned_records,
    total_valid_pans,
    total_invalid_pans,
    (total_cleaned_records - (total_valid_pans + total_invalid_pans)) AS total_unclassified_after_cleaning
FROM summary;


-- 12) Export results (server-side) to CSV (requires server filesystem access)
--    Example: COPY (SELECT * FROM vw_valid_invalid_pans) TO '/tmp/pan_validation_result.csv' CSV HEADER;
--    If you run from psql client, use \copy to export to client machine:
--    \copy (SELECT * FROM vw_valid_invalid_pans) TO 'pan_validation_result.csv' CSV HEADER;

-- 13) Helpful maintenance: drop test data (optional)
--    TRUNCATE sgt_pan_numbers_dataset;
