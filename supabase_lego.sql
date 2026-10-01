-- Svet Lego junakov — fotografije izdelkov
--
-- Zaženi enkrat v Supabase → SQL Editor (isti projekt kot Brihta-MAT).
--
-- LOČENO OD MATEMATIKE: vse je v svoji shemi "lego" (svoj predal v bazi).
-- V Table Editorju jo izbereš v spustnem meniju "schema" zgoraj levo.
-- Matematika je v shemi "public" in je ta datoteka ne spreminja — tabelo
-- public.teachers samo bere, da preveri, ali je fotografijo dodal potrjen
-- učitelj (prijava je ista kot pri Brihta-MAT).
--
-- PO ZAGONU ŠE EN KORAK (brez njega stran sheme ne vidi):
--   Project Settings → Data API → Exposed schemas → dodaj "lego" → Save
--
-- ZAKAJ SLIKE V TABELI IN NE V STORAGE: v Storage bi lahko z javnim ključem
-- nalagal vsak. Tukaj gre vsako nalaganje skozi funkcijo, ki preveri
-- učitelja, tabela sama pa je z javnim ključem nedostopna (RLS brez politik).
-- Stran slike pomanjša na ~100–150 KB, zato jih gre v brezplačno bazo na
-- tisoče.

-- ── 0. Pospravi prejšnjo različico v "public", če si jo že zagnal ─────────
-- Tabela je bila takrat še prazna, zato se nič ne izgubi.
drop function if exists public.lego_seznam();
drop function if exists public.lego_slike(uuid[]);
drop function if exists public.lego_dodaj(uuid, text);
drop function if exists public.lego_izbrisi(uuid, uuid);
drop table if exists public.lego_izdelki;

-- ── 1. Shema in tabela ────────────────────────────────────────────────────
create schema if not exists lego;
grant usage on schema lego to anon, authenticated;

create table if not exists lego.izdelki (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  teacher_id  uuid references public.teachers(id) on delete set null,
  image       text not null   -- data:image/jpeg;base64,...
);
alter table lego.izdelki enable row level security;

-- ── 2. Branje (javno — stran je javna) ───────────────────────────────────
-- Najprej samo seznam id-jev, da stran ob vsakem preverjanju ne prenaša
-- vseh slik znova; slike nato pobere le za nove id-je.
create or replace function lego.seznam()
returns table(id uuid, created_at timestamptz)
language sql stable security definer set search_path = lego, public
as $$
  select i.id, i.created_at from lego.izdelki i
   order by i.created_at desc
   limit 200;
$$;

create or replace function lego.slike(p_ids uuid[])
returns table(id uuid, image text)
language sql stable security definer set search_path = lego, public
as $$
  select i.id, i.image from lego.izdelki i
   where i.id = any(p_ids)
   limit 20;
$$;

-- ── 3. Dodajanje in brisanje (samo potrjen učitelj) ──────────────────────
create or replace function lego.dodaj(p_teacher uuid, p_image text)
returns uuid
language plpgsql volatile security definer set search_path = lego, public
as $$
declare v_id uuid;
begin
  if not exists (select 1 from public.teachers t where t.id = p_teacher and t.approved) then
    return null;
  end if;
  -- samo slika in ne prevelika (stran pošlje ~150 KB, meja je velikodušna)
  if coalesce(p_image, '') !~ '^data:image/(jpeg|png|webp);base64,'
     or length(p_image) > 900000 then
    return null;
  end if;

  insert into lego.izdelki (teacher_id, image)
  values (p_teacher, p_image)
  returning id into v_id;
  return v_id;
end; $$;

-- Briše samo en izdelek iz lego.izdelki, in to le, ko ga učitelj na strani
-- izbriše z gumbom. Ob zagonu te datoteke se nič ne briše.
create or replace function lego.izbrisi(p_teacher uuid, p_id uuid)
returns boolean
language plpgsql volatile security definer set search_path = lego, public
as $$
begin
  if not exists (select 1 from public.teachers t where t.id = p_teacher and t.approved) then
    return false;
  end if;
  delete from lego.izdelki where id = p_id;
  return found;
end; $$;

grant execute on all functions in schema lego to anon, authenticated;

-- ── Pregled (neobvezno) ───────────────────────────────────────────────────
-- select id, created_at, length(image) / 1024 as kb from lego.izdelki order by created_at desc;
