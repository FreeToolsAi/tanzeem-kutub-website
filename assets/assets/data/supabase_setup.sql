-- =====================================================================
--  Tanzeem Kutub Khana  -  Supabase Setup  (FRESH / RESET)
-- =====================================================================
--
--  WHAT THIS DOES:
--   - Deletes (DROPS) the old tables so the database starts clean.
--   - Re-creates every table with the CORRECT, UPDATED schema.
--   - Adds security (RLS) and realtime (admin-to-admin instant sync).
--
--  HOW TO USE:
--   1) Open Supabase Dashboard
--   2) Left menu -> "SQL Editor"
--   3) Click "New query"
--   4) Copy ALL the text below and paste it here
--   5) Click "Run"
--   6) Done! All tables are re-created correctly.
--
--  IMPORTANT: We are ONLY deleting TABLES (not the project).
--  DROP TABLE removes old data. That is expected because the app was updated.
--
--  NOTE: The order matters. Tables are created FIRST, then the is_admin()
--  function. This prevents the error:
--     ERROR: relation "public.admins" does not exist
-- =====================================================================


-- ---------------------------------------------------------------------
--  STEP 1 : DELETE (DROP) the old tables and old function
-- ---------------------------------------------------------------------
drop function if exists public.is_admin() cascade;
drop table if exists public.books   cascade;
drop table if exists public.papers  cascade;
drop table if exists public.notices cascade;
drop table if exists public.ads     cascade;
drop table if exists public.users   cascade;
drop table if exists public.admins  cascade;


-- ---------------------------------------------------------------------
--  STEP 2 : ADMINS  (admin accounts) -- created FIRST
-- ---------------------------------------------------------------------
create table public.admins (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  role       text default 'admin',
  created_at timestamptz default now()
);


-- ---------------------------------------------------------------------
--  STEP 3 : BOOKS  (PDF file + alternative PDF link + cover + sharah + tarjuma)
-- ---------------------------------------------------------------------
create table public.books (
  id           text primary key,
  name         text,
  author       text,
  class_id     text,
  subject      text,
  cover_path   text,          -- cover photo (uploaded file OR link)
  pdf_path     text,          -- main PDF path OR link
  pdf_link     text,          -- separate ALTERNATIVE PDF link
  is_paper     boolean default false,
  paper_type   text,
  year         text,
  total_pages  integer default 0,
  sharah       jsonb  default '[]'::jsonb,   -- sharah list
  translations jsonb  default '[]'::jsonb,   -- tarjuma list
  sort_order   integer default 0,
  updated_at   timestamptz default now()
);


-- ---------------------------------------------------------------------
--  STEP 4 : PAPERS  (PDF file + alternative PDF link + cover)
-- ---------------------------------------------------------------------
create table public.papers (
  id           text primary key,
  name         text,
  author       text,
  class_id     text,
  subject      text,
  cover_path   text,          -- cover photo
  pdf_path     text,          -- main PDF path OR link
  pdf_link     text,          -- separate ALTERNATIVE PDF link
  paper_type   text,
  year         text,
  total_pages  integer default 0,
  sort_order   integer default 0,
  updated_at   timestamptz default now()
);


-- ---------------------------------------------------------------------
--  STEP 5 : NOTICES  (notifications sent by the admin)
-- ---------------------------------------------------------------------
create table public.notices (
  id         text primary key,
  title      text,
  body       text,
  active     boolean default true,
  created_at bigint,          -- millisecondsSinceEpoch (from the app)
  updated_at timestamptz default now()
);


-- ---------------------------------------------------------------------
--  STEP 6 : ADS  (private ads by the admin - NOT Google ads)
--           Matches the app: link, video, thumbnail
-- ---------------------------------------------------------------------
create table public.ads (
  id         text primary key,
  title      text,
  link       text,            -- click link
  video      text,            -- video (link OR uploaded)
  thumbnail  text,            -- thumbnail image (link OR uploaded)
  active     boolean default true,
  created_at bigint,          -- millisecondsSinceEpoch
  updated_at timestamptz default now()
);


-- ---------------------------------------------------------------------
--  STEP 7 : USERS  (user info + IP - based on device id, NOT auth)
-- ---------------------------------------------------------------------
create table public.users (
  device_id  text primary key,   -- unique per device
  name       text,
  class_id   text,
  ip         text,               -- user IP address
  first_seen bigint,
  last_seen  bigint,
  visits     integer default 1,
  updated_at timestamptz default now()
);


-- ---------------------------------------------------------------------
--  STEP 8 : is_admin() function -- created AFTER the admins table exists
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.admins a where a.id = auth.uid()
  );
$$;


-- =====================================================================
--  STEP 9 : ROW LEVEL SECURITY (RLS)
-- =====================================================================
alter table public.admins  enable row level security;
alter table public.books   enable row level security;
alter table public.papers  enable row level security;
alter table public.notices enable row level security;
alter table public.ads     enable row level security;
alter table public.users   enable row level security;

-- ADMINS : everyone can read, only admin can write
create policy admins_read  on public.admins for select using (true);
create policy admins_write on public.admins for all
  using (public.is_admin()) with check (public.is_admin());

-- BOOKS : everyone can read, only admin can write
create policy books_read  on public.books for select using (true);
create policy books_write on public.books for all
  using (public.is_admin()) with check (public.is_admin());

-- PAPERS : everyone can read, only admin can write
create policy papers_read  on public.papers for select using (true);
create policy papers_write on public.papers for all
  using (public.is_admin()) with check (public.is_admin());

-- NOTICES : everyone can read, only admin can write
create policy notices_read  on public.notices for select using (true);
create policy notices_write on public.notices for all
  using (public.is_admin()) with check (public.is_admin());

-- ADS : everyone can read, only admin can write
create policy ads_read  on public.ads for select using (true);
create policy ads_write on public.ads for all
  using (public.is_admin()) with check (public.is_admin());

-- USERS : everyone can read AND everyone can write
-- (device-based tracking; a normal user saves their own info without login)
create policy users_read  on public.users for select using (true);
create policy users_write on public.users for all
  using (true) with check (true);


-- =====================================================================
--  STEP 10 : REALTIME  (so one admin's change instantly appears for others)
-- =====================================================================
alter publication supabase_realtime add table public.books;
alter publication supabase_realtime add table public.papers;
alter publication supabase_realtime add table public.notices;
alter publication supabase_realtime add table public.ads;
alter publication supabase_realtime add table public.users;


-- =====================================================================
--  STEP 11 : STORAGE BUCKET  (for uploaded book PDFs + cover photos)
-- =====================================================================
--  This is IMPORTANT. When the admin uploads a book/paper FILE (not a link),
--  the app uploads that file to a PUBLIC storage bucket called "library" and
--  saves the resulting public URL. This is what makes an uploaded book OPEN
--  and its COVER SHOW for EVERY user (not only on the admin's phone).
--
--  Create a PUBLIC bucket named "library":
insert into storage.buckets (id, name, public)
values ('library', 'library', true)
on conflict (id) do update set public = true;

--  Storage policies: everyone can READ files; only signed-in admins can WRITE.
drop policy if exists "library_public_read"  on storage.objects;
drop policy if exists "library_admin_write"  on storage.objects;
drop policy if exists "library_admin_update" on storage.objects;
drop policy if exists "library_admin_delete" on storage.objects;

create policy "library_public_read" on storage.objects
  for select using (bucket_id = 'library');

create policy "library_admin_write" on storage.objects
  for insert with check (bucket_id = 'library' and public.is_admin());

create policy "library_admin_update" on storage.objects
  for update using (bucket_id = 'library' and public.is_admin());

create policy "library_admin_delete" on storage.objects
  for delete using (bucket_id = 'library' and public.is_admin());


-- =====================================================================
--  FINISHED! Now, in the app:  Admin Panel > Cloud section
--    1) Sign Up to create your first admin account
--    2) Then add that account's id into the admins table (see below)
-- =====================================================================
--  HOW TO MAKE YOURSELF AN ADMIN (do this ONCE, in a SEPARATE new query):
--   1) Go to: Authentication > Users, copy your account's UID (User UID)
--   2) Paste it in the line below and Run it.
--
--   DO NOT run the line below now. Run STEP 1-10 first. Then Sign Up in the
--   app. Then come back, remove the two dashes, paste your UID, and Run:
--
--   insert into public.admins (id, email, role)
--   values ('PASTE-YOUR-UID-HERE', 'your@email.com', 'admin');
-- =====================================================================
