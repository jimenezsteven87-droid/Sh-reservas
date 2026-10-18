-- PUNTO DE VENTA: ventas, pagos, gastos y caja (requiere haber ejecutado antes la parte 2: es_dueno)
create table if not exists ventas (
  id uuid primary key default gen_random_uuid(),
  numero bigint generated always as identity,
  fecha date not null, hora time not null,
  cita_id uuid references citas(id) on delete set null,
  cliente text, telefono text,
  profesional_id uuid references profesionales(id),
  subtotal numeric not null check (subtotal >= 0),
  descuento numeric not null default 0 check (descuento >= 0),
  total numeric not null check (total >= 0),
  propina numeric not null default 0 check (propina >= 0),
  nota text,
  anulada boolean not null default false, anulada_motivo text,
  creada timestamptz not null default now());

create table if not exists venta_items (
  id uuid primary key default gen_random_uuid(),
  venta_id uuid not null references ventas(id) on delete cascade,
  tipo text not null check (tipo in ('servicio','producto')),
  servicio_id uuid references servicios(id),
  descripcion text not null,
  cantidad int not null default 1 check (cantidad > 0),
  precio numeric not null check (precio >= 0),
  profesional_id uuid references profesionales(id));

create table if not exists venta_pagos (
  id uuid primary key default gen_random_uuid(),
  venta_id uuid not null references ventas(id) on delete cascade,
  metodo text not null check (metodo in ('efectivo','nequi','daviplata','tarjeta','transferencia','otro')),
  monto numeric not null check (monto > 0));

create table if not exists gastos (
  id uuid primary key default gen_random_uuid(),
  fecha date not null, concepto text not null, monto numeric not null check (monto > 0),
  metodo text not null default 'efectivo' check (metodo in ('efectivo','nequi','daviplata','tarjeta','transferencia','otro')),
  creado timestamptz not null default now());

create table if not exists cajas (
  fecha date primary key, apertura numeric not null default 0 check (apertura >= 0),
  contado numeric check (contado >= 0), cerrada_at timestamptz);

do $$ declare r record; begin
  for r in select * from (values ('ventas','negocio_ventas'),('venta_items','negocio_venta_items'),('venta_pagos','negocio_venta_pagos'),('gastos','negocio_gastos'),('cajas','negocio_cajas')) as v(tabla, pol) loop
    execute format('alter table public.%I enable row level security', r.tabla);
    execute format('drop policy if exists %I on public.%I', r.pol, r.tabla);
    execute format('create policy %I on public.%I for all to authenticated using (es_dueno()) with check (es_dueno())', r.pol, r.tabla);
  end loop;
end $$;

create or replace function registrar_venta(p_cita uuid, p_cliente text, p_telefono text, p_pro uuid, p_items jsonb,
  p_descuento numeric, p_propina numeric, p_pagos jsonb, p_nota text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_sub numeric; v_tot numeric; v_pag numeric; v_now timestamp := ahora_local(); v_met text;
begin
  if not es_dueno() then raise exception 'Sin permiso.'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'Agrega al menos un servicio o producto.'; end if;
  select coalesce(sum((i->>'cantidad')::int * (i->>'precio')::numeric), 0) into v_sub from jsonb_array_elements(p_items) i;
  if p_descuento < 0 or p_descuento > v_sub then raise exception 'El descuento no puede ser mayor que el subtotal.'; end if;
  if p_propina < 0 then raise exception 'La propina no puede ser negativa.'; end if;
  v_tot := v_sub - p_descuento;
  select coalesce(sum((x->>'monto')::numeric), 0) into v_pag from jsonb_array_elements(coalesce(p_pagos, '[]'::jsonb)) x;
  if round(v_pag, 2) <> round(v_tot + p_propina, 2) then raise exception 'Los pagos no coinciden con el total a cobrar.'; end if;
  if p_cita is not null and exists (select 1 from ventas where cita_id = p_cita and not anulada) then raise exception 'Esta cita ya fue cobrada.'; end if;
  insert into ventas (fecha, hora, cita_id, cliente, telefono, profesional_id, subtotal, descuento, total, propina, nota)
    values (v_now::date, v_now::time, p_cita, nullif(trim(p_cliente), ''), nullif(trim(p_telefono), ''), p_pro, v_sub, p_descuento, v_tot, p_propina, nullif(trim(p_nota), ''))
    returning id into v_id;
  insert into venta_items (venta_id, tipo, servicio_id, descripcion, cantidad, precio, profesional_id)
    select v_id, i->>'tipo', nullif(i->>'servicio_id', '')::uuid, i->>'descripcion', (i->>'cantidad')::int, (i->>'precio')::numeric, nullif(i->>'profesional_id', '')::uuid
    from jsonb_array_elements(p_items) i;
  insert into venta_pagos (venta_id, metodo, monto)
    select v_id, x->>'metodo', (x->>'monto')::numeric from jsonb_array_elements(coalesce(p_pagos, '[]'::jsonb)) x where (x->>'monto')::numeric > 0;
  if p_cita is not null then
    select x->>'metodo' into v_met from jsonb_array_elements(coalesce(p_pagos, '[]'::jsonb)) x order by (x->>'monto')::numeric desc limit 1;
    update citas set estado = 'atendida', cobrado = v_tot, metodo_pago = v_met where id = p_cita;
  end if;
  return v_id;
end $$;

create or replace function anular_venta(p_venta uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare v_cita uuid;
begin
  if not es_dueno() then raise exception 'Sin permiso.'; end if;
  update ventas set anulada = true, anulada_motivo = nullif(trim(p_motivo), '') where id = p_venta and not anulada returning cita_id into v_cita;
  if not found then raise exception 'La venta no existe o ya está anulada.'; end if;
  if v_cita is not null then update citas set estado = 'confirmada', cobrado = null, metodo_pago = null where id = v_cita; end if;
end $$;

revoke execute on function registrar_venta(uuid, text, text, uuid, jsonb, numeric, numeric, jsonb, text), anular_venta(uuid, text) from public, anon;
grant execute on function registrar_venta(uuid, text, text, uuid, jsonb, numeric, numeric, jsonb, text), anular_venta(uuid, text) to authenticated;
