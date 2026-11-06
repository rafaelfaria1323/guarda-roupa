-- Acessórios por tipo (2026-11-06): o antigo `accessory` divide-se em
-- cachecol, gorro, luvas, chapéu ou boné, óculos de sol, chapéu-de-chuva,
-- cinto e mala; `accessory` fica para "outro acessório" (gravata, meias,
-- joias...). Servem a sugestão do dia, que junta os que fazem sentido
-- com a previsão. As peças existentes continuam como `accessory`.

alter table public.garments
  drop constraint garments_category_check,
  add constraint garments_category_check check (category in (
    't_shirt', 'shirt', 'polo', 'top', 'sweater', 'sweatshirt', 'cardigan',
    'trousers', 'jeans', 'shorts', 'skirt', 'dress', 'jumpsuit',
    'jacket', 'blazer', 'coat', 'raincoat',
    'sneakers', 'shoes', 'boots', 'sandals',
    'scarf', 'beanie', 'gloves', 'hat', 'sunglasses', 'umbrella', 'belt',
    'bag', 'accessory', 'other'
  ));
