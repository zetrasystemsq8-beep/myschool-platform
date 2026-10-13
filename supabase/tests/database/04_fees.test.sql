-- pgTAP: fees. Run with: supabase db reset && supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create schema if not exists tests;
grant usage on schema tests to anon, authenticated;
create or replace function tests.act_as(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create or replace function tests.today() returns date language sql as
  $$ select (now() at time zone 'Africa/Lagos')::date $$;
grant execute on function tests.act_as(uuid), tests.today() to anon, authenticated;

insert into myschool.fee_categories (id, school_id, name) values
 ('aaaaaaaa-b000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Tuition'),
 ('bbbbbbbb-b000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'Tuition');

-- ===================================================== admin sets up a fee
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');   -- admin A
select is(myschool.create_fee_charge('aaaaaaaa-b000-0000-0000-000000000001', 'Term 1 tuition', 10000, tests.today() + 30,
  'aaaaaaaa-6000-0000-0000-000000000001', null, 'aaaaaaaa-7000-0000-0000-000000000001', null), 2, 'a class fee is assigned to each student in the class');
select throws_ok($$select myschool.create_fee_charge('aaaaaaaa-b000-0000-0000-000000000001', 'Bad', 500, null, 'aaaaaaaa-6000-0000-0000-000000000001', null, 'aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-5000-0000-0000-000000000001')$$,
  '22023', null, 'a fee is for a class OR a student, not both');
select throws_ok($$select myschool.create_fee_charge('aaaaaaaa-b000-0000-0000-000000000001', 'Bad', 500, null, 'aaaaaaaa-6000-0000-0000-000000000001', null, null, null)$$,
  '22023', null, 'a fee needs a class or a student');
select throws_ok($$select myschool.create_fee_charge('aaaaaaaa-b000-0000-0000-000000000001', 'Bad', 0, null, 'aaaaaaaa-6000-0000-0000-000000000001', null, 'aaaaaaaa-7000-0000-0000-000000000001', null)$$,
  '22023', null, 'the amount must be more than zero');
select is(myschool.sync_fee_charge((select id from myschool.fee_charges where title = 'Term 1 tuition')), 0, 'sync adds nothing when nobody is missing');
select is(myschool.create_fee_charge('aaaaaaaa-b000-0000-0000-000000000001', 'Uniform', 4500, null,
  'aaaaaaaa-6000-0000-0000-000000000001', null, null, 'aaaaaaaa-5000-0000-0000-000000000002'), 1, 'a fee can be set for one student');

-- ===================================================== recording payments
select lives_ok($$select myschool.record_fee_payment((select student_fee_id from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and title = 'Term 1 tuition'), 3000, tests.today(), 'cash', 'RCPT-1', 'first part')$$,
  'admin records a payment');
select is((select paid from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and title = 'Term 1 tuition'), 3000.00::numeric, 'paid amount is tracked');
select is((select balance from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and title = 'Term 1 tuition'), 7000.00::numeric, 'outstanding balance is correct');
select is((select status from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and title = 'Term 1 tuition'), 'part_paid', 'status is part paid');
select is((select paid_recorded_by_school from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and title = 'Term 1 tuition'), 3000.00::numeric, 'the payment is marked as recorded by the school');
select is((select paid_verified_online from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and title = 'Term 1 tuition'), 0.00::numeric, 'nothing is shown as verified online');
select throws_ok($$select myschool.record_fee_payment((select student_fee_id from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and title = 'Term 1 tuition'), 8000, tests.today(), 'cash', null, null)$$,
  '23514', null, 'a student cannot pay more than is owed');
select throws_ok($$select myschool.record_fee_payment((select student_fee_id from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and title = 'Term 1 tuition'), 100, tests.today() + 1, 'cash', null, null)$$,
  '22023', null, 'a payment cannot be dated in the future');
select throws_ok($$select myschool.record_fee_payment((select student_fee_id from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and title = 'Term 1 tuition'), -5, tests.today(), 'cash', null, null)$$,
  '22023', null, 'a payment must be positive');
select throws_ok($$select myschool.reverse_fee_payment((select id from myschool.fee_payments limit 1), '')$$, '22023', null, 'reversing needs a reason');
select lives_ok($$select myschool.reverse_fee_payment((select id from myschool.fee_payments limit 1), 'Wrong student')$$, 'admin reverses a payment');
select is((select paid from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and title = 'Term 1 tuition'), 0.00::numeric, 'a reversed payment no longer counts');
select throws_ok($$select myschool.reverse_fee_payment((select id from myschool.fee_payments limit 1), 'Again')$$, '55000', null, 'a payment can only be reversed once');
select lives_ok($$select myschool.record_fee_payment((select student_fee_id from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and title = 'Term 1 tuition'), 2000, tests.today(), 'bank_transfer', 'TRF-9', null)$$, 'payment re-recorded');
select throws_ok($$insert into myschool.fee_payments (school_id, student_id, student_fee_id, amount, paid_on, method) values ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-5000-0000-0000-000000000001',(select id from myschool.student_fees limit 1), 1, tests.today(), 'cash')$$,
  '42501', null, 'clients cannot insert payments directly');
select throws_ok($$insert into myschool.fee_charges (school_id, category_id, session_id, title, amount, class_id) values ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-b000-0000-0000-000000000001','aaaaaaaa-6000-0000-0000-000000000001','Sneaky',1,'aaaaaaaa-7000-0000-0000-000000000001')$$,
  '42501', null, 'clients cannot create fees directly');
select throws_ok($$update myschool.fee_payments set amount = 1$$, '42501', null, 'clients cannot edit payments');
reset role;

-- ===================================================== online vs school-recorded
select throws_ok($$insert into myschool.fee_payments (school_id, student_id, student_fee_id, amount, paid_on, method, source) values ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-5000-0000-0000-000000000002',(select student_fee_id from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000002' and title = 'Uniform'), 1000, tests.today(), 'other', 'gateway_verified')$$,
  '23514', null, 'an "online" payment without verification proof is impossible');
select lives_ok($$insert into myschool.fee_payments (school_id, student_id, student_fee_id, amount, paid_on, method, source, gateway_provider, gateway_reference, verified_at) values ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-5000-0000-0000-000000000002',(select student_fee_id from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000002' and title = 'Uniform'), 1000, tests.today(), 'other', 'gateway_verified', 'testpay', 'REF-1', now())$$,
  'a verified online payment (inserted by the server side) is accepted');
select is((select paid_verified_online from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000002' and title = 'Uniform'), 1000.00::numeric, 'online money is shown separately');
select is((select paid_recorded_by_school from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000002' and title = 'Uniform'), 0.00::numeric, 'and is not mixed with school-recorded money');
select throws_ok($$update myschool.fee_payments set amount = 5 where source = 'gateway_verified'$$, '23514', null, 'a payment row cannot be edited');
select throws_ok($$delete from myschool.fee_payments$$, '42501', null, 'payments can never be deleted');
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select throws_ok($$select myschool.reverse_fee_payment((select id from myschool.fee_payments where source = 'gateway_verified'), 'try')$$, '42501', null, 'the school cannot reverse a verified online payment');
reset role;
select ok(exists (select 1 from myschool.audit_logs where action = 'fee.payment_recorded'), 'recording a payment is audited');
select ok(exists (select 1 from myschool.audit_logs where action = 'fee.payment_reversed'), 'reversing a payment is audited');
select ok(exists (select 1 from myschool.audit_logs where action = 'fee.charge_created'), 'creating a fee is audited');

-- ===================================================== who can see fees
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');   -- teacher A
select is((select count(*)::int from myschool.student_fee_balances), 0, 'teachers cannot see fee balances');
select is((select count(*)::int from myschool.fee_payments), 0, 'teachers cannot see payments');
select is((select count(*)::int from myschool.fee_charges), 0, 'teachers cannot see fee amounts');
reset role;
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');   -- Ada's parent
select is((select count(*)::int from myschool.student_fee_balances), 1, 'parent sees only their child''s fees');
select is((select count(*)::int from myschool.student_fee_balances where student_id = 'aaaaaaaa-5000-0000-0000-000000000002'), 0, 'parent does not see another child''s fees');
select is((select count(*)::int from myschool.fee_charges), 1, 'parent sees the fee that applies to their child');
select ok((select count(*)::int from myschool.fee_payments) >= 1, 'parent sees the payment history');
select throws_ok($$select myschool.record_fee_payment((select student_fee_id from myschool.student_fee_balances limit 1), 100, tests.today(), 'cash', null, null)$$, '42501', null, 'parents cannot record payments');
select throws_ok($$select myschool.create_fee_charge('aaaaaaaa-b000-0000-0000-000000000001', 'X', 100, null, 'aaaaaaaa-6000-0000-0000-000000000001', null, 'aaaaaaaa-7000-0000-0000-000000000001', null)$$, '42501', null, 'parents cannot create fees');
reset role;
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000002');   -- Bayo
select is((select count(*)::int from myschool.student_fee_balances where student_id <> 'aaaaaaaa-5000-0000-0000-000000000002'), 0, 'a student sees only their own fees');
reset role;
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');   -- admin B
select is((select count(*)::int from myschool.student_fee_balances where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, 'another school''s admin sees no fees');
select throws_ok($$select myschool.create_fee_charge('aaaaaaaa-b000-0000-0000-000000000001', 'X', 100, null, 'aaaaaaaa-6000-0000-0000-000000000001', null, 'aaaaaaaa-7000-0000-0000-000000000001', null)$$, '42501', null, 'another school''s admin cannot create fees here');
select throws_ok($$select myschool.record_fee_payment((select student_fee_id from myschool.student_fee_balances where school_id = 'aaaaaaaa-0000-0000-0000-000000000001' limit 1), 100, tests.today(), 'cash', null, null)$$, '42501', null, 'another school''s admin cannot record payments here');
reset role;

select * from finish();
rollback;
