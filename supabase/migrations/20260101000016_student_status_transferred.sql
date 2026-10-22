-- 16: one more student status. (Kept in its own file: a new enum value cannot be USED in the same transaction that adds it.)
alter type myschool.student_status add value if not exists 'transferred';
