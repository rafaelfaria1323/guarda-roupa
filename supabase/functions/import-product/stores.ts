/**
 * Lojas com nome conhecido (P-12). Qualquer outro site também se pode
 * importar; estas só ganham um nome bonito. O estado de cada site vem do
 * perfil que a base cria sozinha (`record_import`), não desta lista.
 */
export interface Store {
  id: string;
  name: string;
  /** Domínios exatos das páginas de produto. */
  hosts: string[];
}

export const STORES: readonly Store[] = [
  { id: 'zara', name: 'Zara', hosts: ['www.zara.com', 'zara.com'] },
  { id: 'uniqlo', name: 'Uniqlo', hosts: ['www.uniqlo.com', 'uniqlo.com'] },
  {
    id: 'pullandbear',
    name: 'Pull&Bear',
    hosts: ['www.pullandbear.com', 'pullandbear.com'],
  },
  { id: 'bershka', name: 'Bershka', hosts: ['www.bershka.com', 'bershka.com'] },
  {
    id: 'massimodutti',
    name: 'Massimo Dutti',
    hosts: ['www.massimodutti.com', 'massimodutti.com'],
  },
];

/** Nome a mostrar: o da lista, ou o domínio sem `www.`. */
export function siteName(host: string, stores = STORES): string {
  return stores.find((s) => s.hosts.includes(host))?.name ??
    host.replace(/^www\./, '');
}
