
-- Allow submission ids to have non-digit characters. This implementation uses
-- job arrays, so the submission id will look like this: 1313799[1].paroo3
-- 
ALTER TABLE job MODIFY submission_id varchar(100);
