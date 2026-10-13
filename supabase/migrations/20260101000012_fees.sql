-- 12: school fees. The school RECORDS payments; money received online is a separate, clearly marked kind
-- that only a verified gateway integration (service role) could ever create. No gateway is implemented here.
create type myschool.payment_source as enum ('school_recorded', 'gateway_verified');
create type myschool.payment_method as enum ('cash', 'bank_transfer', 'pos', 'cheque', 'other');

create table myschool.fee_categories (
  id          uuid primary key default gen_random_uuid(),
  school_id   uuid not null references myschool.schools (id) on delete cascade,
  name        text not null check (char_length(name) between 2 and 80),
  description text check (description is null or char_length(description) <= 300),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (school_id, name),
  unique (id, school_id)
);

-- A fee the school sets: one amount, for a whole class OR for one student.
create table myschool.fee_charges (
  id          uuid primary key default gen_random_uuid(),
  school_id   uuid not null,
  category_id uuid not null,
  session_id  uuid not null,
  term_id     uuid,
  title       text not null check (char_length(title) between 2 and 120),
  amount      numeric(12,2) not null check (amount > 0),
  currency    text not null default 'NGN' check (char_length(currency) = 3),
  due_date    date,
  class_id    uuid,
  student_id  uuid,
  created_by  uuid default auth.uid() references myschool.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (id, school_id),
  check ((class_id is not null)::int + (student_id is not null)::int = 1),
  foreign key (category_id, school_id) references myschool.fee_categories (id, school_id) on delete restrict,
  foreign key (session_id, school_id) references myschool.academic_sessions (id, school_id) on delete restrict,
  foreign key (term_id, school_id) references myschool.terms (id, school_id) on delete restrict,
  foreign key (class_id, school_id) references myschool.classes (id, school_id) on delete restrict,
  foreign key (student_id, school_id) references myschool.students (id, school_id) on delete restrict
);

-- What one student owes for one fee (created when the fee is assigned).
create table myschool.student_fees (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null,
  charge_id  uuid not null,
  student_id uuid not null,
  amount     numeric(12,2) not null check (amount > 0),
  due_date   date,
  created_at timestamptz not null default now(),
  unique (charge_id, student_id),
  unique (id, school_id),
  unique (id, student_id),
  foreign key (charge_id, school_id) references myschool.fee_charges (id, school_id) on delete restrict,
  foreign key (student_id, school_id) references myschool.students (id, school_id) on delete restrict
);
create index student_fees_student_idx on myschool.student_fees (student_id);

create table myschool.fee_payments (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid not null,
  student_id       uuid not null,
  student_fee_id   uuid not null,
  amount           numeric(12,2) not null check (amount > 0),
  paid_on          date not null,
  method           myschool.payment_method not null,
  reference        text check (reference is null or char_length(reference) <= 80),
  note             text check (note is null or char_length(note) <= 300),
  source           myschool.payment_source not null default 'school_recorded',
  recorded_by      uuid default auth.uid() references myschool.profiles (id) on delete set null,
  gateway_provider text,
  gateway_reference text,
  verified_at      timestamptz,
  reversed_at      timestamptz,
  reversed_by      uuid references myschool.profiles (id) on delete set null,
  reversal_reason  text,
  created_at       timestamptz not null default now(),
  foreign key (student_fee_id, school_id) references myschool.student_fees (id, school_id) on delete restrict,
  foreign key (student_fee_id, student_id) references myschool.student_fees (id, student_id) on delete restrict,
  -- online payments need proof of verification; school-recorded ones must not pretend to have it
  constraint payment_gateway_proof check (
    (source = 'gateway_verified' and gateway_provider is not null and gateway_reference is not null and verified_at is not null)
    or (source = 'school_recorded' and gateway_provider is null and gateway_reference is null and verified_at is null)),
  constraint payment_reversal_pair check ((reversed_at is null) = (reversal_reason is null))
);
create unique index fee_payments_gateway_ref on myschool.fee_payments (gateway_provider, gateway_reference)
  where gateway_reference is not null;
create index fee_payments_fee_idx on myschool.fee_payments (student_fee_id);

-- ---------------------------------------------------------------- integrity triggers
create or replace function ms_private.fee_charge_before_write() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.term_id is not null and not exists (
       select 1 from myschool.terms t where t.id = new.term_id and t.session_id = new.session_id) then
    raise exception 'The term does not belong to that school year.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger fee_charge_before_write before insert on myschool.fee_charges
  for each row execute function ms_private.fee_charge_before_write();

-- A student can never pay more than they owe for a fee.
create or replace function ms_private.fee_payment_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_amount numeric; v_paid numeric;
begin
  select amount into v_amount from myschool.student_fees where id = new.student_fee_id for update;
  select coalesce(sum(amount), 0) into v_paid from myschool.fee_payments
   where student_fee_id = new.student_fee_id and reversed_at is null;
  if new.reversed_at is null and v_paid + new.amount > v_amount then
    raise exception 'That is more than is still owed (%).', v_amount - v_paid using errcode = '23514';
  end if;
  return new;
end $$;
create trigger fee_payment_before_insert before insert on myschool.fee_payments
  for each row execute function ms_private.fee_payment_before_insert();

-- Payments are a ledger: only a reversal may change a row, and rows are never deleted.
create or replace function ms_private.fee_payment_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Payments cannot be deleted; reverse them instead.' using errcode = '42501';
  end if;
  if (new.school_id, new.student_id, new.student_fee_id, new.amount, new.paid_on, new.method, new.reference,
      new.note, new.source, new.recorded_by, new.gateway_provider, new.gateway_reference, new.verified_at)
     is distinct from
     (old.school_id, old.student_id, old.student_fee_id, old.amount, old.paid_on, old.method, old.reference,
      old.note, old.source, old.recorded_by, old.gateway_provider, old.gateway_reference, old.verified_at) then
    raise exception 'A payment cannot be edited. Reverse it and record it again.' using errcode = '23514';
  end if;
  if old.reversed_at is not null and new.reversed_at is distinct from old.reversed_at then
    raise exception 'This payment was already reversed.' using errcode = '55000';
  end if;
  return new;
end $$;
create trigger fee_payment_guard before update or delete on myschool.fee_payments
  for each row execute function ms_private.fee_payment_guard();

create trigger audit_fee_categories after insert or update on myschool.fee_categories
  for each row execute function ms_private.audit_row('fee_category');
create trigger forbid_school_change before update on myschool.fee_categories
  for each row execute function ms_private.forbid_school_change();

-- ---------------------------------------------------------------- read access
create or replace function ms_private.sees_fee_charge(p_charge uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from myschool.student_fees sf
                 where sf.charge_id = p_charge and ms_private.is_self_or_parent_of(sf.student_id))
$$;

alter table myschool.fee_categories enable row level security;
alter table myschool.fee_charges    enable row level security;
alter table myschool.student_fees   enable row level security;
alter table myschool.fee_payments   enable row level security;

create policy fee_categories_select on myschool.fee_categories for select to authenticated
  using (ms_private.is_member(school_id));
create policy fee_categories_insert on myschool.fee_categories for insert to authenticated
  with check (ms_private.is_school_admin(school_id));
create policy fee_categories_update on myschool.fee_categories for update to authenticated
  using (ms_private.is_school_admin(school_id)) with check (ms_private.is_school_admin(school_id));

create policy fee_charges_select on myschool.fee_charges for select to authenticated
  using (ms_private.is_school_admin(school_id) or ms_private.sees_fee_charge(id));
create policy student_fees_select on myschool.student_fees for select to authenticated
  using (ms_private.is_school_admin(school_id) or ms_private.is_self_or_parent_of(student_id));
create policy fee_payments_select on myschool.fee_payments for select to authenticated
  using (ms_private.is_school_admin(school_id) or ms_private.is_self_or_parent_of(student_id));
-- Teachers get no fee access at all. Charges, student fees and payments are written only by the RPCs below.

-- ---------------------------------------------------------------- write RPCs (admin only, audited)
create or replace function myschool.create_fee_charge(
  p_category uuid, p_title text, p_amount numeric, p_due date, p_session uuid,
  p_term uuid, p_class uuid, p_student uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare v_school uuid; v_charge uuid; v_n integer;
begin
  select school_id into v_school from myschool.fee_categories where id = p_category;
  if v_school is null or not ms_private.is_school_admin(v_school) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if (p_class is null) = (p_student is null) then
    raise exception 'Choose either a class or one student.' using errcode = '22023';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'The amount must be more than zero.' using errcode = '22023';
  end if;
  insert into myschool.fee_charges (school_id, category_id, session_id, term_id, title, amount, due_date, class_id, student_id)
  values (v_school, p_category, p_session, p_term, trim(p_title), p_amount, p_due, p_class, p_student)
  returning id into v_charge;
  if p_class is not null then
    insert into myschool.student_fees (school_id, charge_id, student_id, amount, due_date)
    select v_school, v_charge, e.student_id, p_amount, p_due
      from myschool.enrollments e
     where e.school_id = v_school and e.class_id = p_class and e.session_id = p_session and e.status <> 'withdrawn';
  else
    insert into myschool.student_fees (school_id, charge_id, student_id, amount, due_date)
    values (v_school, v_charge, p_student, p_amount, p_due);
  end if;
  get diagnostics v_n = row_count;
  perform ms_private.write_audit(v_school, 'fee.charge_created', 'fee_charge', v_charge,
    jsonb_build_object('title', p_title, 'amount', p_amount, 'class_id', p_class, 'student_id', p_student, 'students', v_n));
  return v_n;
end $$;

-- Adds the fee for students who joined the class after the fee was created. Safe to run repeatedly.
create or replace function myschool.sync_fee_charge(p_charge uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare c myschool.fee_charges; v_n integer;
begin
  select * into c from myschool.fee_charges where id = p_charge;
  if c.id is null or not ms_private.is_school_admin(c.school_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if c.class_id is null then return 0; end if;
  insert into myschool.student_fees (school_id, charge_id, student_id, amount, due_date)
  select c.school_id, c.id, e.student_id, c.amount, c.due_date
    from myschool.enrollments e
   where e.school_id = c.school_id and e.class_id = c.class_id and e.session_id = c.session_id and e.status <> 'withdrawn'
  on conflict (charge_id, student_id) do nothing;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    perform ms_private.write_audit(c.school_id, 'fee.charge_synced', 'fee_charge', c.id, jsonb_build_object('added', v_n));
  end if;
  return v_n;
end $$;

-- Records money the SCHOOL received (cash, transfer, POS, cheque). Always marked "school_recorded".
create or replace function myschool.record_fee_payment(
  p_student_fee uuid, p_amount numeric, p_paid_on date, p_method myschool.payment_method,
  p_reference text, p_note text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare sf myschool.student_fees; v_id uuid;
begin
  select * into sf from myschool.student_fees where id = p_student_fee;
  if sf.id is null or not ms_private.is_school_admin(sf.school_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'The amount must be more than zero.' using errcode = '22023';
  end if;
  if p_paid_on is null or p_paid_on > ms_private.school_today(sf.school_id) then
    raise exception 'The payment date cannot be in the future.' using errcode = '22023';
  end if;
  insert into myschool.fee_payments (school_id, student_id, student_fee_id, amount, paid_on, method, reference, note)
  values (sf.school_id, sf.student_id, sf.id, p_amount, p_paid_on, p_method,
          nullif(trim(coalesce(p_reference, '')), ''), nullif(trim(coalesce(p_note, '')), ''))
  returning id into v_id;
  perform ms_private.write_audit(sf.school_id, 'fee.payment_recorded', 'fee_payment', v_id,
    jsonb_build_object('amount', p_amount, 'method', p_method, 'student_fee_id', sf.id, 'source', 'school_recorded'));
  return v_id;
end $$;

create or replace function myschool.reverse_fee_payment(p_payment uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare p myschool.fee_payments;
begin
  select * into p from myschool.fee_payments where id = p_payment;
  if p.id is null or not ms_private.is_school_admin(p.school_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p.source = 'gateway_verified' then
    raise exception 'Online payments cannot be reversed here.' using errcode = '42501';
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A reason is required.' using errcode = '22023';
  end if;
  if p.reversed_at is not null then
    raise exception 'This payment was already reversed.' using errcode = '55000';
  end if;
  update myschool.fee_payments set reversed_at = now(), reversed_by = auth.uid(), reversal_reason = trim(p_reason)
   where id = p_payment;
  perform ms_private.write_audit(p.school_id, 'fee.payment_reversed', 'fee_payment', p.id,
    jsonb_build_object('amount', p.amount, 'reason', p_reason));
end $$;

-- ---------------------------------------------------------------- balances
create view myschool.student_fee_balances with (security_invoker = true) as
select sf.id as student_fee_id, sf.school_id, sf.student_id,
       st.first_name, st.last_name, st.admission_number,
       ch.id as charge_id, ch.title, cat.name as category_name, ch.currency,
       ses.name as session_name, t.name as term_name,
       sf.amount, sf.due_date,
       coalesce(p.paid, 0)::numeric(12,2) as paid,
       coalesce(p.school_paid, 0)::numeric(12,2) as paid_recorded_by_school,
       coalesce(p.gateway_paid, 0)::numeric(12,2) as paid_verified_online,
       (sf.amount - coalesce(p.paid, 0))::numeric(12,2) as balance,
       case when sf.amount - coalesce(p.paid, 0) <= 0 then 'paid'
            when sf.due_date is not null and sf.due_date < current_date then 'overdue'
            when coalesce(p.paid, 0) > 0 then 'part_paid'
            else 'unpaid' end as status
  from myschool.student_fees sf
  join myschool.fee_charges ch on ch.id = sf.charge_id
  join myschool.fee_categories cat on cat.id = ch.category_id
  join myschool.academic_sessions ses on ses.id = ch.session_id
  left join myschool.terms t on t.id = ch.term_id
  join myschool.students st on st.id = sf.student_id
  left join lateral (
    select sum(fp.amount) filter (where fp.reversed_at is null) as paid,
           sum(fp.amount) filter (where fp.reversed_at is null and fp.source = 'school_recorded') as school_paid,
           sum(fp.amount) filter (where fp.reversed_at is null and fp.source = 'gateway_verified') as gateway_paid
      from myschool.fee_payments fp where fp.student_fee_id = sf.id) p on true;

-- ---------------------------------------------------------------- privileges
revoke all on function ms_private.fee_charge_before_write(), ms_private.fee_payment_before_insert(),
  ms_private.fee_payment_guard(), ms_private.sees_fee_charge(uuid) from public, anon, authenticated;
grant execute on function ms_private.sees_fee_charge(uuid) to authenticated;
revoke all on function
  myschool.create_fee_charge(uuid, text, numeric, date, uuid, uuid, uuid, uuid),
  myschool.sync_fee_charge(uuid),
  myschool.record_fee_payment(uuid, numeric, date, myschool.payment_method, text, text),
  myschool.reverse_fee_payment(uuid, text)
  from public, anon, authenticated;
grant execute on function
  myschool.create_fee_charge(uuid, text, numeric, date, uuid, uuid, uuid, uuid),
  myschool.sync_fee_charge(uuid),
  myschool.record_fee_payment(uuid, numeric, date, myschool.payment_method, text, text),
  myschool.reverse_fee_payment(uuid, text)
  to authenticated;
grant select on myschool.fee_categories, myschool.fee_charges, myschool.student_fees,
  myschool.fee_payments, myschool.student_fee_balances to authenticated;
grant insert, update on myschool.fee_categories to authenticated;

notify pgrst, 'reload schema';
