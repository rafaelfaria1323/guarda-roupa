# ADR-006 — Ficheiros, PWA e recuperação

Estado: estratégia recomendada; POC Safari, offline e recuperação por realizar.

## Persistência de ficheiros

| Opção | Benefícios | Limitações |
|---|---|---|
| Ficheiros privados nativos + IndexedDB Web | Recomendado: bytes locais e adaptadores explícitos | Gestão de quota, referências e limpeza |
| Binários dentro de SQLite | Transação SQL mais próxima dos dados | Bases/backups maiores e pressão no mecanismo de sync |
| Só cloud | Menos cópias locais | Não satisfaz offline e aumenta transferências |
| Só cache de URLs | Simples | Eviction/expiração e ausência de garantia de reabertura |

Guardar identidade de asset, não signed URL ou blob URL. Media e dados relacionais têm estados de sincronização próprios.

## Offline Web

Flutter recente não gera por defeito o service worker de cache pretendido. Recomendação: Workbox explícito para assets da aplicação.

Não fazer cache indiscriminada de endpoints autenticados ou media privados via service worker. Dados de utilizador ficam no subsistema local apropriado.

WASM/worker SQLite, manifest e bundle precisam de publicação coerente. Atualizações não podem apagar a base ou ativar uma migração destrutiva com operações pendentes.

Headers COOP/COEP podem habilitar certas estratégias, mas também afetar OAuth/popups. Validar o conjunto, não copiar headers de um exemplo isolado.

## Alojamento

| Opção | Avaliação |
|---|---|
| Cloudflare Pages | Recomendado: HTTPS, domínio gratuito e possibilidade de função leve |
| Firebase Hosting | Alternativa válida; rever limites e alinhamento do backend |
| Netlify/Vercel | Alternativas; condições/quotas do plano atual a confirmar |
| Servidor próprio | Mais controlo, mais operação/custo |
| Servir localmente | Bom para desenvolvimento, não distribui PWA entre dispositivos |

Usar Git integration para evolução contínua é a recomendação. Direct Upload é alternativa rápida, mas o mesmo projeto não é depois convertido em Git integrado; pode exigir outro projeto/origin.

Mudança de origin afeta armazenamento local e callbacks. Sincronizar/exportar antes de migrar; não assumir que a nova URL vê a IndexedDB antiga.

## Backup

JSON versionado + assets num ZIP. Portabilidade acima de copiar só a base. Hash não é encriptação. Exportação completa verificada antes de declarar sucesso.

Recuperação sobre conta existente exige protocolo próprio; não pode ser reduzida a “importar linhas e voltar a ligar sync”.

## Consequências e revisão

Maior trabalho de plataforma, mas offline verificável e menor dependência de URLs externas. Se Safari não cumprir os gates de persistência/fotografia, ajustar a solução antes de o utilizador confiar nela.

Fontes: Flutter FAQ, Drift Web, WebKit e Cloudflare em [Fontes](../fontes.md).

Guias: [publicação](../guias/04-publicar-pwa.md), [operação](../guias/07-operacao-backups-e-limites.md).
