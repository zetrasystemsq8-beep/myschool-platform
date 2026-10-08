-- 04: results. Lifecycle lives on the RESULT SHEET = (term, class, subject).
-- A teacher fills a sheet, submits it, an admin approves and publishes it. Students/parents only
-- ever see items of PUBLISHED sheets.

create table public.result_sheets (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null,
  term_id      uuid not null,
  class_id     uuid not null,
  subject_id   uuid not null,
  status       public.result_status not null default 'draft',
  return_note  text,
  created_by   uuid default auth.uid() references public.profiles (id) on delete set null,
  submitted_by uuid references public.profiles (id) on delete set null,
  submitted_at timestamptz,
  approved_by  uuid references public.profiles (id) on delete set null,
  approved_at  timestamptz,
  published_by uuid references public.profiles (id) on delete set null,
  published_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (term_id, class_id, subject_id),
  unique (id, school_id),
  foreign key (term_id, school_id) references public.terms (id, school_id) on delete restrict,
  foreign key (class_id, school_id) references public.classes (id, school_id) on delete restrict,
  foreign key (subject_id, school_id) references public.subjects (id, school_id) on delete restrict
);
create index result_sheets_school_status_idx on public.result_sheets (school_id, status);

-- Optional link to a photographed script (future OCR). Defined before result_items references it.
create table public.script_scans (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null references public.schools (id) on delete cascade,
  sheet_id     uuid,
  student_id   uuid,
  uploaded_by  uuid not null references public.profiles (id) on delete restrict,
  storage_path text not null,                    -- path in private bucket 'script-scans': {school_id}/...
  status       public.scan_status not null default 'uploaded',
  engine       text,                              -- e.g. 'vision-model-x' (set by the future pipeline)
  extracted    jsonb,                             -- {"score": 17, "confidence": 0.82, "raw_text": "..."}
  reviewed_by  uuid references public.profiles (id) on delete set null,
  reviewed_at  timestamptz,
  created_at   timestamptz not null default now(),
  unique (id, school_id),
  foreign key (sheet_id, school_id) references public.result_sheets (id, school_id) on delete set null (sheet_id),
  foreign key (student_id, school_id) references public.students (id, school_id) on delete set null (student_id)
);

create table public.result_items (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null,
  sheet_id   uuid not null,
  student_id uuid not null,
  ca_score   numeric(5,2) check (ca_score >= 0),
  exam_score numeric(5,2) check (exam_score >= 0),
  total      numeric(5,2),                         -- computed by trigger
  grade      text,                                 -- computed by trigger from grading_scales
  remark     text,
  source     public.result_source not null default 'manual',
  scan_id    uuid,
  entered_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (sheet_id, student_id),
  foreign key (sheet_id, school_id) references public.result_sheets (id, school_id) on delete cascade,
  foreign key (student_id, school_id) references public.students (id, school_id) on delete restrict,
  foreign key (scan_id, school_id) references public.script_scans (id, school_id) on delete set null (scan_id)
);
create index result_items_student_idx on public.result_items (student_id);
