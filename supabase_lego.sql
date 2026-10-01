-- Svet Lego junakov — fotografije izdelkov
--
-- Zaženi enkrat v Supabase → SQL Editor (isti projekt kot Brihta-MAT).
-- Vse je ločeno od Matematike: nova tabela in funkcije imajo predpono
-- "lego_". Obstoječih tabel in funkcij ta datoteka ne spreminja — tabelo
-- teachers samo bere, da preveri, ali je fotografijo dodal potrjen učitelj.
--
-- ZAKAJ SLIKE V TABELI IN NE V STORAGE: v Storage bi lahko z javnim ključem
-- nalagal vsak. Tukaj gre vsako nalaganje skozi funkcijo, ki preveri
-- učitelja, tabela sama pa je z javnim ključem nedostopna (RLS brez politik).
-- Stran slike pomanjša na ~100–150 KB, zato jih gre v brezplačno bazo na
-- tisoče.

-- ── 1. Tabela ─────────────────────────────────────────────────────────────
create table if not exists lego_izdelki (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  teacher_id  uuid references teachers(id) on delete set null,
  image       text not null   -- data:image/jpeg;base64,...
);
alter table lego_izdelki enable row level security;

-- ── 2. Branje (javno — stran je javna) ───────────────────────────────────
-- Najprej samo seznam id-jev, da stran ob vsakem preverjanju ne prenaša
-- vseh slik znova; slike nato pobere le za nove id-je.
create or replace function public.lego_seznam()
returns table(id uuid, created_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select i.id, i.created_at from lego_izdelki i
   order by i.created_at desc
   limit 200;
$$;

create or replace function public.lego_slike(p_ids uuid[])
returns table(id uuid, image text)
language sql stable security definer set search_path = public
as $$
  select i.id, i.image from lego_izdelki i
   where i.id = any(p_ids)
   limit 20;
$$;

-- ── 3. Dodajanje in brisanje (samo potrjen učitelj) ──────────────────────
create or replace function public.lego_dodaj(p_teacher uuid, p_image text)
returns uuid
language plpgsql volatile security definer set search_path = public
as $$
declare v_id uuid;
begin
  if not exists (select 1 from teachers t where t.id = p_teacher and t.approved) then
    return null;
  end if;
  -- samo slika in ne prevelika (stran pošlje ~150 KB, meja je velikodušna)
  if coalesce(p_image, '') !~ '^data:image/(jpeg|png|webp);base64,'
     or length(p_image) > 900000 then
    return null;
  end if;

  insert into lego_izdelki (teacher_id, image)
  values (p_teacher, p_image)
  returning id into v_id;
  return v_id;
end; $$;

create or replace function public.lego_izbrisi(p_teacher uuid, p_id uuid)
returns boolean
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not exists (select 1 from teachers t where t.id = p_teacher and t.approved) then
    return false;
  end if;
  delete from lego_izdelki where id = p_id;
  return found;
end; $$;

-- ── Pregled (neobvezno) ───────────────────────────────────────────────────
-- select id, created_at, length(image) / 1024 as kb from lego_izdelki order by created_at desc;
--
-- Vse izdelke izbrišeš z:
-- delete from lego_izdelki;
