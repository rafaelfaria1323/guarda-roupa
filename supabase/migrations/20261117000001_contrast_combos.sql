-- Contraste desejado (docs/features/motor-de-combinacoes.md): duas novas
-- combinações que se podem preferir ou evitar, "Claro com escuro"
-- (high_contrast) e "Contraste suave" (low_contrast). A função é usada
-- pela restrição de style_preferences; só passa a aceitar mais valores.

create or replace function public.style_preference_value_valid(subject text, value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case subject
    when 'color' then case when value ~ '^[0-9]{1,8}$'
      then value::bigint <= 16777215 else false end
    when 'pattern' then value in ('plain', 'stripes', 'checks', 'dots', 'floral', 'print', 'other')
    when 'texture' then value in ('smooth', 'ribbed', 'knit', 'textured', 'fuzzy')
    when 'formality' then value in ('relaxed', 'smart_casual', 'dressy')
    when 'combo' then value in ('neutral_base', 'single_accent', 'tonal', 'high_contrast', 'low_contrast')
    else false
  end;
$$;
