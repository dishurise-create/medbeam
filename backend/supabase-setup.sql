-- MedBeam community reports database
-- Run this once in your Supabase project: Dashboard → SQL Editor → New query → paste → Run.
--
-- Privacy: a report stores ONLY the medication ID, the pharmacy's location,
-- whether it was in stock, and the time. No names, accounts, or device IDs.

create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  rxcui       text not null check (rxcui ~ '^[0-9]{1,10}$'),
  latitude    double precision not null check (latitude between -90 and 90),
  longitude   double precision not null check (longitude between -180 and 180),
  in_stock    boolean not null,
  created_at  timestamptz not null default now()
);

-- Fast lookups by medication + area + time
create index if not exists reports_lookup_idx
  on public.reports (rxcui, created_at desc, latitude, longitude);

-- Row Level Security: the app's public key can ONLY read recent reports and add new ones.
-- It cannot edit or delete anything.
alter table public.reports enable row level security;

drop policy if exists "read recent reports" on public.reports;
create policy "read recent reports" on public.reports
  for select to anon, authenticated
  using (created_at > now() - interval '45 days');

drop policy if exists "add reports" on public.reports;
create policy "add reports" on public.reports
  for insert to anon, authenticated
  with check (created_at between now() - interval '1 minute' and now() + interval '1 minute');

-- Basic spam protection: at most 30 reports per minute for the whole database,
-- and at most 3 reports per minute for the same pharmacy + medication.
create or replace function public.limit_report_rate() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.reports where created_at > now() - interval '1 minute') >= 30 then
    raise exception 'Too many reports right now, please try again in a minute';
  end if;
  if (select count(*) from public.reports
        where rxcui = new.rxcui
          and abs(latitude - new.latitude) < 0.0007
          and abs(longitude - new.longitude) < 0.0007
          and created_at > now() - interval '1 minute') >= 3 then
    raise exception 'Too many reports for this pharmacy, please try again later';
  end if;
  new.created_at := now();   -- the server sets the time, not the phone
  return new;
end $$;

drop trigger if exists reports_rate_limit on public.reports;
create trigger reports_rate_limit before insert on public.reports
  for each row execute function public.limit_report_rate();

-- The app's public key gets exactly these permissions and nothing else
revoke all on public.reports from anon, authenticated;
grant select (id, rxcui, latitude, longitude, in_stock, created_at) on public.reports to anon, authenticated;
grant insert (rxcui, latitude, longitude, in_stock) on public.reports to anon, authenticated;
