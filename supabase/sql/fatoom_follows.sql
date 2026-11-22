-- FATOOM social follows: followers and following counts.
-- Applied to Supabase project tipuhfeipxxbmwbygqng.
create table if not exists public.follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint follows_no_self check (follower_id <> following_id)
);
create index if not exists follows_following_idx on public.follows(following_id);
alter table public.follows enable row level security;
drop policy if exists "follows visible to authenticated" on public.follows;
create policy "follows visible to authenticated" on public.follows
  for select to authenticated using (true);
drop policy if exists "users follow as themselves" on public.follows;
create policy "users follow as themselves" on public.follows
  for insert to authenticated with check ((select auth.uid()) = follower_id);
drop policy if exists "users unfollow as themselves" on public.follows;
create policy "users unfollow as themselves" on public.follows
  for delete to authenticated using ((select auth.uid()) = follower_id);
grant select, insert, delete on public.follows to authenticated;
