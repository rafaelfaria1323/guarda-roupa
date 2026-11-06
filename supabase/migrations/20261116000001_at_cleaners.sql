-- Limpeza profissional (2026-11-06): estado `at_cleaners` ("Na
-- lavandaria"), a peça está fora de casa numa lavandaria ou limpeza a
-- seco. Na resolução de conflitos (ADR-008) fica entre `washing` e
-- `needs_cleaning`: só uma peça ainda por limpar é menos disponível.

alter table public.garments
  drop constraint garments_availability_check,
  add constraint garments_availability_check
    check (availability in ('available', 'drying', 'washing', 'at_cleaners',
                            'needs_cleaning'));

create or replace function public.availability_caution(value text)
returns int
language sql
immutable
set search_path = ''
as $$
  select case value
    when 'available' then 0
    when 'drying' then 1
    when 'washing' then 2
    when 'at_cleaners' then 3
    when 'needs_cleaning' then 4
  end;
$$;
