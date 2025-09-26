--- PAN NUMBER VALIDATION PROJECT USING SQL ---

create table sgt_pan_numbers_dataset
(
pan_number   text

);
select * from sgt_pan_numbers_dataset;

-- Identify and handle missing data:

select * from sgt_pan_numbers_dataset where pan_number is null

-- Check for duplicates: 

SELECT pan_number, count(1)
from sgt_pan_numbers_dataset
group by pan_number
having count(1) > 1;

-- Handle leading/trailing spaces: 

select 	* from 	sgt_pan_numbers_dataset where pan_number <> TRIM(pan_number)

-- Correct letter case:

select * from sgt_pan_numbers_dataset where pan_number <> upper(pan_number)




-- Cleaned Pan Numbers :

select distinct upper(trim(pan_number)) as pan_number
from sgt_pan_numbers_dataset 
where pan_number is not null
and trim(pan_number) <> '';

-- function to check if adjacent characters are the same -- ASHCE1512F <= ASHCE
create or replace function fn_check_adjacent_characters(p_str text)
returns boolean 
language plpgsql
as $$ begin
	FOR i in 1 ..  length (p_str) - 1
		loop 
			if substring (p_str, i , 1) = substring (p_str, i+1 , 1)
			then
			return true; -- the characters are adjacent
		  end if;
		end loop;
		return false; -- non of the characters are adjacent to each other were the same
end;
$$

select fn_check_adjacent_characters ('ZWOOO')

-- 	Function to check if sequencial characters are used ABORT -- ABCDE, AXDGE

create or replace function fn_check_sequencial_characters(p_str text)
returns boolean 
language plpgsql
as $$ begin
	FOR i in 1 ..  length (p_str) - 1
		loop 
			if ascii(substring(p_str, i+1, 1)) - ascii(substring(p_str, i, 1)) <> 1
			then 
			return false; -- the string is forming not SEQUENCE
			end if;
		end loop;
		return true; -- the string is forming the SEQUENCE
end;
$$

select ascii('X')
select fn_check_sequencial_characters('AXDGE')

-- Regular expresstion to validate the partern or structure of PAN Numbers -- AAAAA1234B
select * from sgt_pan_numbers_dataset
 	where pan_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'

-- Valid and Invalid categoriztion ABORT
create or replace  view vw_valid_invalid_pans
as
with	cte_cleaned_pan as 
	(select distinct upper(trim(pan_number)) as pan_number
from sgt_pan_numbers_dataset 
where pan_number is not null
and trim(pan_number) <> ''),
	cte_valid_pans as 
	(select * 
	from cte_cleaned_pan
	where fn_check_adjacent_characters(pan_number) = false
	and fn_check_sequencial_characters(substring(pan_number,1,5)) = false
	and fn_check_sequencial_characters(substring(pan_number,6,4)) = false
	and pan_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]$')
select cln.pan_number
	, 	case when vld.pan_number is not null 
			then 'Valid PAN' 
			else 'Invalid PAN'
	end as status 
	from cte_cleaned_pan cln
	left join cte_valid_pans vld on vld.pan_number = cln.pan_number;

-- Summary report
sgt_pan_numbers_dataset
vw_valid_invalid_pans
with cte AS
	(SELECT
		(select count(*) from sgt_pan_numbers_dataset) as total_processed_records
		,	count(*) FILTER 	(where status = 'Valid PAN') as  total_valid_pans
		,		count(*) FILTER 	(where status = 'Invalid PAN') as  total_invalid_pans
	 	from vw_valid_invalid_pans)
select total_processed_records, total_valid_pans, total_invalid_pans
, (total_processed_records - (total_valid_pans + total_invalid_pans)) as total_missing_pans
from cte;
