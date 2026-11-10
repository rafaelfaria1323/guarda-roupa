// Valores aceites (os ids estáveis da app: lib/features/wardrobe/domain/).

export const CATEGORIES = [
  't_shirt',
  'shirt',
  'polo',
  'top',
  'sweater',
  'sweatshirt',
  'cardigan',
  'trousers',
  'jeans',
  'shorts',
  'skirt',
  'dress',
  'jumpsuit',
  'jacket',
  'blazer',
  'coat',
  'raincoat',
  'sneakers',
  'shoes',
  'boots',
  'sandals',
  'scarf',
  'beanie',
  'gloves',
  'hat',
  'sunglasses',
  'umbrella',
  'belt',
  'bag',
  'accessory',
  'other',
] as const;

export const COLORS = [
  'white',
  'cream',
  'beige',
  'khaki',
  'brown',
  'grey',
  'charcoal',
  'black',
  'navy',
  'blue',
  'light_blue',
  'denim',
  'green',
  'mint',
  'turquoise',
  'olive',
  'yellow',
  'orange',
  'terracotta',
  'red',
  'burgundy',
  'pink',
  'purple',
  'lilac',
  'silver',
  'gold',
] as const;

export const PATTERNS = [
  'plain',
  'stripes',
  'checks',
  'dots',
  'floral',
  'print',
  'other',
] as const;
export const TEXTURES = [
  'smooth',
  'ribbed',
  'knit',
  'textured',
  'fuzzy',
] as const;
export const WARMTH = ['light', 'medium', 'warm'] as const;
export const FORMALITY = ['relaxed', 'smart_casual', 'dressy'] as const;
export const WASH = [
  'machine_30',
  'machine_40',
  'machine_60',
  'hand',
  'professional',
] as const;

const str = (values?: readonly string[]) => ({
  type: 'STRING',
  nullable: true,
  ...(values ? { enum: [...values] } : {}),
});

/** Esquema de resposta pedido ao Gemini (subconjunto OpenAPI). */
export const GARMENT_SCHEMA = {
  type: 'OBJECT',
  properties: {
    category: str(CATEGORIES),
    name: str(),
    colors: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          color: { type: 'STRING', enum: [...COLORS] },
          share: { type: 'INTEGER' },
        },
        required: ['color', 'share'],
      },
    },
    pattern: str(PATTERNS),
    texture: str(TEXTURES),
    warmth: str(WARMTH),
    formality: str(FORMALITY),
  },
  required: ['category', 'name', 'colors'],
};

/** O que se viu nas fotos: a etiqueta de cuidados ou outra coisa. */
export const FOUND = [
  'care_label',
  'brand_or_size_label',
  'not_label',
] as const;

export const LABEL_SCHEMA = {
  type: 'OBJECT',
  properties: {
    found: { type: 'STRING', enum: [...FOUND] },
    wash: str(WASH),
    tumble_dry: { type: 'BOOLEAN', nullable: true },
    material: str(),
    care: str(),
  },
  required: ['found'],
};

export const GARMENT_PROMPT =
  `The photo shows one clothing item or accessory (flat, on a hanger, or worn).
Describe only the main item; ignore background, skin, hangers and other items.
- category: the best fit from the list ("accessory" for ties, socks, jewellery; "other" if none fits).
- name: a short name in European Portuguese (pt-PT), 2 to 4 words, without brand, e.g. "Camisa às riscas", "Calças de ganga claras", "Ténis brancos".
- colors: up to 3 main colors of the item from the list, with "share" = approximate percentage of the item's visible area (multiples of 5, total at most 100). Use silver or gold only for clearly metallic parts.
- pattern, texture: as seen; null if unsure.
- warmth: light (summer, thin), medium, warm (winter, thick); null if unsure.
- formality: relaxed, smart_casual or dressy; null if unsure.`;

export const LABEL_PROMPT =
  `The photos (one or more) show the labels of ONE clothing item, possibly both sides of the same label or several pages of a folded, multilingual care label. Combine what you read in all of them.
- found: "care_label" if any photo shows a care label (wash/dry/iron symbols or fibre composition); "brand_or_size_label" if they only show a brand patch, leather patch, logo or size tag; "not_label" otherwise. If not "care_label", set the other fields to null.
- Read the care symbols in their usual order: washtub (wash), triangle (bleach), square with circle (tumble dry), iron, circle (dry clean). A cross over a symbol means "do not". Dots or a number inside the washtub give the temperature (1 dot = 30, 2 dots = 40, 3 dots = 60). A hand in the washtub means hand wash. Text in any language counts too (e.g. "machine wash cold" = 30).
- wash: the highest allowed machine temperature as machine_30, machine_40 or machine_60 (use the nearest lower one); "hand" if only hand wash; "professional" if dry clean only or do not wash. null if not visible.
- tumble_dry: true if tumble drying is allowed, false if the tumble dry symbol is crossed out, null if not shown.
- material: the fibre composition as written, translated to European Portuguese (pt-PT), e.g. "95% algodão, 5% elastano". If the label lists parts (shell, lining, pocketing), keep only the main fabric. null if not visible.
- care: other instructions in short European Portuguese (pt-PT) sentences, e.g. "Lavar do avesso. Não usar lixívia. Passar a ferro a baixa temperatura." null if none.
Never guess: use null for anything you cannot read.`;
