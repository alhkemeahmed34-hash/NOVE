-- NOVA CHAT media, WebRTC call signaling, stories and social feed.
-- Applied to Supabase project tipuhfeipxxbmwbygqng on 2026-11-23.
-- Keep this SQL in sync with the live project. All exposed public tables use RLS and explicit grants.

create table if not exists public.call_signals (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check (kind in ('offer','answer','ice','hangup','decline','busy')),
 payload jsonb,
 created_at timestamptz not null default now()
);
create index if not exists call_signals_recipient_created_idx on public.call_signals(recipient_id, created_at desc);
alter table public.call_signals enable row level security;
drop policy if exists "call signals participants read" on public.call_signals;
create policy "call signals participants read" on public.call_signals for select to authenticated using (auth.uid()=sender_id or auth.uid()=recipient_id);
drop policy if exists "call signals valid participants insert" on public.call_signals;
create policy "call signals valid participants insert" on public.call_signals for insert to authenticated with check (
 auth.uid()=sender_id and sender_id<>recipient_id
 and exists(select 1 from public.conversation_members cm where cm.conversation_id=call_signals.conversation_id and cm.user_id=sender_id)
 and exists(select 1 from public.conversation_members cm where cm.conversation_id=call_signals.conversation_id and cm.user_id=recipient_id)
);
grant select,insert,update,delete on public.call_signals to authenticated;

create table if not exists public.posts (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 caption text not null default '' check(char_length(caption)<=2200), media_path text, created_at timestamptz not null default now()
);
create index if not exists posts_created_idx on public.posts(created_at desc);
alter table public.posts enable row level security;
drop policy if exists "posts visible to authenticated" on public.posts;
create policy "posts visible to authenticated" on public.posts for select to authenticated using(true);
drop policy if exists "users create own posts" on public.posts;
create policy "users create own posts" on public.posts for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "users edit own posts" on public.posts;
create policy "users edit own posts" on public.posts for update to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);
drop policy if exists "users delete own posts" on public.posts;
create policy "users delete own posts" on public.posts for delete to authenticated using(auth.uid()=user_id);
grant select,insert,update,delete on public.posts to authenticated;

create table if not exists public.post_likes (
 post_id uuid not null references public.posts(id) on delete cascade, user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(post_id,user_id)
);
alter table public.post_likes enable row level security;
drop policy if exists "likes visible to authenticated" on public.post_likes;
create policy "likes visible to authenticated" on public.post_likes for select to authenticated using(true);
drop policy if exists "users like as themselves" on public.post_likes;
create policy "users like as themselves" on public.post_likes for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "users unlike as themselves" on public.post_likes;
create policy "users unlike as themselves" on public.post_likes for delete to authenticated using(auth.uid()=user_id);
grant select,insert,update,delete on public.post_likes to authenticated;

create table if not exists public.post_comments (
 id uuid primary key default gen_random_uuid(), post_id uuid not null references public.posts(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade, content text not null check(char_length(content) between 1 and 1000),
 created_at timestamptz not null default now()
);
alter table public.post_comments enable row level security;
drop policy if exists "comments visible to authenticated" on public.post_comments;
create policy "comments visible to authenticated" on public.post_comments for select to authenticated using(true);
drop policy if exists "users create own comments" on public.post_comments;
create policy "users create own comments" on public.post_comments for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "users delete own comments" on public.post_comments;
create policy "users delete own comments" on public.post_comments for delete to authenticated using(auth.uid()=user_id);
grant select,insert,update,delete on public.post_comments to authenticated;

create table if not exists public.stories (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 media_path text not null, caption text not null default '' check(char_length(caption)<=500),
 created_at timestamptz not null default now(), expires_at timestamptz not null default(now()+interval '24 hours')
);
create index if not exists stories_expiry_idx on public.stories(expires_at);
alter table public.stories enable row level security;
drop policy if exists "active stories visible to authenticated" on public.stories;
create policy "active stories visible to authenticated" on public.stories for select to authenticated using(expires_at>now());
drop policy if exists "users create own stories" on public.stories;
create policy "users create own stories" on public.stories for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "users delete own stories" on public.stories;
create policy "users delete own stories" on public.stories for delete to authenticated using(auth.uid()=user_id);
grant select,insert,update,delete on public.stories to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('nova-media','nova-media',false,52428800,array['image/jpeg','image/png','image/webp','image/gif','audio/webm','audio/ogg','audio/mp4','audio/mpeg'])
on conflict(id) do update set public=false,file_size_limit=52428800,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "nova media conversation members read" on storage.objects;
create policy "nova media conversation members read" on storage.objects for select to authenticated using(bucket_id='nova-media' and exists(select 1 from public.conversation_members cm where cm.conversation_id::text=(storage.foldername(name))[1] and cm.user_id=auth.uid()));
drop policy if exists "nova media conversation members upload" on storage.objects;
create policy "nova media conversation members upload" on storage.objects for insert to authenticated with check(bucket_id='nova-media' and (storage.foldername(name))[2]=auth.uid()::text and exists(select 1 from public.conversation_members cm where cm.conversation_id::text=(storage.foldername(name))[1] and cm.user_id=auth.uid()));
drop policy if exists "nova media owners delete" on storage.objects;
create policy "nova media owners delete" on storage.objects for delete to authenticated using(bucket_id='nova-media' and (storage.foldername(name))[2]=auth.uid()::text);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('nova-social','nova-social',false,52428800,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict(id) do update set public=false,file_size_limit=52428800,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "nova social authenticated read" on storage.objects;
create policy "nova social authenticated read" on storage.objects for select to authenticated using(bucket_id='nova-social');
drop policy if exists "nova social owner upload" on storage.objects;
create policy "nova social owner upload" on storage.objects for insert to authenticated with check(bucket_id='nova-social' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "nova social owner delete" on storage.objects;
create policy "nova social owner delete" on storage.objects for delete to authenticated using(bucket_id='nova-social' and (storage.foldername(name))[1]=auth.uid()::text);

do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='call_signals') then
  alter publication supabase_realtime add table public.call_signals;
 end if;
end $$;

-- FATOOM story likes, comments and optional music.
alter table public.stories add column if not exists music_path text;
alter table public.stories add column if not exists music_title text;
create table if not exists public.story_likes (
 story_id uuid not null references public.stories(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(story_id,user_id)
);
create table if not exists public.story_comments (
 id uuid primary key default gen_random_uuid(),
 story_id uuid not null references public.stories(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 content text not null check (char_length(content) between 1 and 1000),
 created_at timestamptz not null default now()
);
create index if not exists story_comments_story_created_idx on public.story_comments(story_id,created_at);
alter table public.story_likes enable row level security;
alter table public.story_comments enable row level security;
drop policy if exists "story likes visible to authenticated" on public.story_likes;
create policy "story likes visible to authenticated" on public.story_likes for select to authenticated using (true);
drop policy if exists "users like stories as themselves" on public.story_likes;
create policy "users like stories as themselves" on public.story_likes for insert to authenticated with check (auth.uid()=user_id);
drop policy if exists "users unlike stories as themselves" on public.story_likes;
create policy "users unlike stories as themselves" on public.story_likes for delete to authenticated using (auth.uid()=user_id);
drop policy if exists "story comments visible to authenticated" on public.story_comments;
create policy "story comments visible to authenticated" on public.story_comments for select to authenticated using (exists(select 1 from public.stories s where s.id=story_id and s.expires_at>now()));
drop policy if exists "users comment on stories as themselves" on public.story_comments;
create policy "users comment on stories as themselves" on public.story_comments for insert to authenticated with check (auth.uid()=user_id and exists(select 1 from public.stories s where s.id=story_id and s.expires_at>now()));
drop policy if exists "users delete own story comments" on public.story_comments;
create policy "users delete own story comments" on public.story_comments for delete to authenticated using (auth.uid()=user_id);
grant select,insert,delete on public.story_likes to authenticated;
grant select,insert,delete on public.story_comments to authenticated;


-- FATOOM media and profile enhancements (applied 2026-11-23)
alter table public.posts add column if not exists media_type text not null default 'image' check (media_type in ('image','video'));
alter table public.stories add column if not exists media_type text not null default 'image' check (media_type in ('image','video'));
alter table public.profiles add column if not exists bio text not null default '';
alter table public.messages drop constraint if exists messages_message_type_check;
alter table public.messages add constraint messages_message_type_check check (message_type = any (array['text'::text,'image'::text,'file'::text,'audio'::text,'video'::text]));
