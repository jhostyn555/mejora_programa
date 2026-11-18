-- Aplicar en el SQL Editor si ya tenias aplicado schema.sql o
-- roles_control_migration.sql. Agrega asignacion de roles desde el panel admin.

create or replace function public.list_users()
returns table (id uuid, full_name text, email text, role public.app_role)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede listar usuarios';
  end if;

  return query
    select p.id, p.full_name, coalesce(u.email, ''), p.role
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.role <> 'admin'
     order by p.full_name, u.email;
end;
$$;

revoke execute on function public.list_users() from public, anon;
grant execute on function public.list_users() to authenticated;

create or replace function public.admin_set_role(target uuid, new_role public.app_role)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Solo un administrador puede asignar roles';
  end if;

  if new_role = 'admin' then
    raise exception 'El rol de administrador no se asigna desde el panel';
  end if;

  if target = auth.uid() then
    raise exception 'No puedes cambiar tu propio rol';
  end if;

  update public.profiles
     set role = new_role, requested_role = null
   where id = target and role <> 'admin';
end;
$$;

revoke execute on function public.admin_set_role(uuid, public.app_role) from public, anon;
grant execute on function public.admin_set_role(uuid, public.app_role) to authenticated;
