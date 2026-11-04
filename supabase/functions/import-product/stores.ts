/**
 * Lojas que a função aceita (docs/features/importacao-de-links.md, P-12).
 *
 * `poc`: em teste. Nenhuma loja é anunciada como suportada sem um smoke com
 * links reais (tool/import/README.md) e comportamento conhecido para
 * variantes e erros.
 */
export type StoreStatus = 'poc' | 'supported';

export interface Store {
  id: string;
  name: string;
  /** Domínios exatos das páginas de produto. */
  hosts: string[];
  /** Domínios exatos de onde se podem copiar imagens. A confirmar no smoke. */
  imageHosts: string[];
  status: StoreStatus;
}

export const STORES: readonly Store[] = [
  {
    id: 'zara',
    name: 'Zara',
    hosts: ['www.zara.com', 'zara.com'],
    imageHosts: ['static.zara.net'],
    status: 'poc',
  },
  {
    id: 'uniqlo',
    name: 'Uniqlo',
    hosts: ['www.uniqlo.com', 'uniqlo.com'],
    imageHosts: ['image.uniqlo.com'],
    status: 'poc',
  },
  {
    id: 'pullandbear',
    name: 'Pull&Bear',
    hosts: ['www.pullandbear.com', 'pullandbear.com'],
    imageHosts: ['static.pullandbear.net'],
    status: 'poc',
  },
  {
    id: 'bershka',
    name: 'Bershka',
    hosts: ['www.bershka.com', 'bershka.com'],
    imageHosts: ['static.bershka.net'],
    status: 'poc',
  },
];
