-- Aplicar SOLO si ya habia ejecutado una version anterior de schema.sql.
-- Habilita: control gestiona solicitudes y admin transforma clientes en control.

create or replace function public.is_control()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'control'
  );
$$;

create or replace function public.can_manage_requests()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or public.is_control();
$$;

drop policy if exists "ver perfil propio o admin" on public.profiles;
drop policy if exists "ver perfil propio o admin o control" on public.profiles;
create policy "ver perfil propio o admin o control"
on public.profiles for select to authenticated
using (id = auth.uid() or public.is_admin() or public.is_control());

create or replace function public.decide_request(target uuid, approve boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_manage_requests() then
    raise exception 'Solo un administrador o control puede decidir solicitudes';
  end if;

  update public.profiles
     set role = case when approve then requested_role else role end,
         requested_role = null
   where id = target and requested_role is not null;
end;
$$;

revoke execute on function public.decide_request(uuid, boolean) from public, anon;
grant execute on function public.decide_request(uuid, boolean) to authenticated;

create or replace function public.promote_to_control(target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede asignar el rol de control';
  end if;

  update public.profiles
     set role = 'control', requested_role = null
   where id = target and role = 'cliente';
end;
$$;

revoke execute on function public.promote_to_control(uuid) from public, anon;
grant execute on function public.promote_to_control(uuid) to authenticated;

create or replace function public.list_clients()
returns table (id uuid, full_name text, email text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede listar clientes';
  end if;

  return query
    select p.id, p.full_name, coalesce(u.email, '')
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.role = 'cliente'
     order by p.full_name, u.email;
end;
$$;

revoke execute on function public.list_clients() from public, anon;
grant execute on function public.list_clients() to authenticated;
