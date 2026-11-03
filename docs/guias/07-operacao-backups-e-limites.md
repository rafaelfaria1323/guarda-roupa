# Guia 07 — Operação, backups e limites

Quando: depois de existirem catálogo, sync e exportação funcionais. Tu guardas cópias externas e acompanhas contas/limites. O responsável pela implementação fornece exportação consistente, recuperação segura, estados de erro e diagnóstico.

**Os menus da app abaixo são propostas de UX e ainda não existem.** Não executar uma recuperação só porque estes passos estão documentados.

Referências: [backups](../features/backups-e-recuperacao.md), [limites Free](../custos-e-limitacoes.md) e P-11 de [Pendências](../pendencias.md).

## 1. Antes de depender da aplicação

1. Confirmar que a mesma conta sincroniza dados e fotografias nos dois aparelhos.
2. Confirmar que a app distingue alterações locais, linhas sincronizadas e media pendentes.
3. Executar pelo menos uma exportação completa e uma recuperação de experiência num destino autorizado.
4. Escolher onde guardar cópias fora da app e uma rotina proporcional às alterações.
5. Fazer uma nova cópia antes de mudar de aparelho/origin, migrar dados, reinstalar ou executar operações destrutivas.

Sincronização não é backup: uma eliminação também se pode propagar. A cópia não deve existir apenas no armazenamento privado da aplicação ou no mesmo browser.

## 2. Exportar um backup completo

Pré-requisito bloqueante: o exportador já implementa snapshot consistente, dados versionados e imagens, conforme a especificação.

Implementado (2026-11-03): **Definições > Dados e backup > Exportar backup**. Hoje o âmbito são as peças (incluindo arquivadas) e as suas fotografias; conjuntos, planos e histórico entram quando existirem. Fotos que não estejam neste dispositivo são descarregadas da cloud; se alguma faltar, a exportação falha com a contagem e não grava nada.

1. Abrir a app e consultar o estado de sync e a data da última atualização.
2. Se houver rede, permitir que a sincronização termine quando for seguro. Não descartar operações locais para conseguir um indicador verde.
3. Se só existir acesso offline, permitir exportação apenas quando todos os assets necessários estão locais; o manifest deve identificar o corte e as pendências.
4. Abrir o percurso proposto **Definições > Dados > Exportar backup completo**.
5. Confirmar o âmbito apresentado: peças, conjuntos, planos, histórico, políticas, preferências e ficheiros referenciados.
6. Se faltarem fotos ou houver falha de integridade, resolver/repetir. Um inventário sem as imagens referenciadas não pode ser anunciado como backup completo.
7. Selecionar uma localização fora da app e terminar a gravação/download.
8. No Android, usar o seletor de ficheiros/partilha implementado e confirmar no gestor de ficheiros que a cópia existe no destino.
9. No iPhone, concluir o fluxo de guardar/partilhar e abrir **Ficheiros** para confirmar o ficheiro no destino escolhido. “Downloads” pode pertencer a iCloud Drive ou “No meu iPhone”; verificar qual foi usado.
10. No Mac/Web, confirmar o download no Finder e, se necessário, mover a cópia para uma localização privada e protegida.
11. Registar data, revisão da app e contagens apresentadas.

Cancelar o seletor não é exportação concluída. Gravar apenas na pasta privada Android também não é cópia externa.

O ZIP normal **não é encriptado**. Contém informação pessoal e fotografias: não colocar em Git, pasta pública ou serviço de partilha aberto. Uma cópia adicional num destino já disponível pode ajudar, mas não contratar armazenamento como consequência automática deste guia.

## 3. Verificar o ficheiro

1. Confirmar nome, tamanho não nulo e data do ficheiro realmente guardado.
2. O formato proposto inclui manifest, dados JSON e assets; os nomes concretos são definidos pela implementação.
3. Verificar que as contagens correspondem ao preview da exportação e que existem as imagens referenciadas.
4. Usar a validação do importador para conferir schema, caminhos, limites e hashes de todos os assets antes de aplicar dados.
5. Conservar o ficheiro original. Se fizeres uma inspeção manual, usar uma cópia e não voltar a empacotar o original por tentativa.

Opcionalmente, no Mac, registar o hash do ficheiro completo:

```bash
shasum -a 256 "/CAMINHO/REAL/backup-guarda-roupa.zip"
```

Substituir pelo caminho real. Este hash ajuda a comparar cópias, mas não verifica sozinho os hashes internos do manifest, não prova recuperação e não encripta nada.

## 4. Ensaiar a recuperação sem arriscar o original

Pré-requisito: importador implementado e modo de recuperação aprovado. Até P-11 estar fechada, não fazer merge/substituição sobre uma conta cloud com dados existentes.

1. Manter a instalação/conta original intacta e o backup guardado.
2. Preparar um destino de experiência vazio, autenticado e autorizado para aquele modo de recuperação.
3. Confirmar isolamento e regras de ownership: o importador não pode recuperar tokens nem contornar autorização para copiar dados entre contas.
4. Abrir o percurso proposto **Definições > Dados > Recuperar backup**.
5. Selecionar uma cópia do ZIP.
6. Aguardar validação de versão, limites, caminhos, hashes e relações.
7. Ler o preview e o destino exato. Se o impacto não estiver claro, cancelar.
8. Confirmar apenas quando o modo permitir aplicar sem tocar nos dados originais.
9. Aguardar conclusão observável; ficheiro corrupto/incompatível deve ser rejeitado antes de alterações parciais.
10. Confirmar catálogo, fotografias, conjuntos, planos, histórico e contagens.
11. Fechar/reabrir e repetir a inspeção offline dos dados locais.
12. Retomar sync apenas pelo protocolo aprovado, preservando identidades/semântica sem repetir eventos antigos como novos usos.
13. Registar E2E-13 e eliminar apenas dados de experiência identificados, depois de validar o resultado.

Uma conta nova não autoriza automaticamente importar um backup de outra identidade; esse caminho tem de estar explicitamente suportado pelo importador.

Se falhar, preservar ZIP, dados originais e diagnóstico redigido. Não testar apagando a base pessoal e “vendo se volta”.

## 5. Acompanhar Supabase Free

Condições de referência de 31-10-2026: 500 MB de base, 1 GB de ficheiros, 5 GB de egress com rubrica separada de cached egress, pausa por inatividade e ausência de backups automáticos Free. Rever a página oficial antes de decisões operacionais.

1. Abrir https://supabase.com/dashboard e selecionar a organização/projeto correto.
2. Consultar **Usage**, no painel da organização ou no local equivalente da interface, e o período de consumo.
3. Separar base de dados, Storage e transferências; não interpretar “poucas peças” como garantia de consumo baixo.
4. Abrir o projeto > **Storage** e rever os buckets privados definidos, sem os tornar públicos para facilitar downloads.
5. Identificar crescimento de imagens e inspirações. Limpeza de ficheiros só com referências verificadas e mecanismo de retenção aprovado.
6. Registar aproximação aos limites e erros observados.
7. Se o serviço exigir upgrade, parar e decidir entre reduzir consumo de forma segura, esperar a renovação aplicável ou mudar a solução. Não introduzir cartão/planos pagos sem aprovação.

Quota cheia pode impedir novas transferências sem impedir o trabalho local: a UI deve mostrar a pendência/falha e preservar os dados. Não apagar a outbox ou as fotos locais para esconder o erro.

## 6. Pausa e retoma do serviço

1. Se a app deixar de contactar o backend, confirmar primeiro rede e o estado do projeto no dashboard.
2. Se aparecer projeto pausado, abrir o detalhe e seguir a ação de retoma disponível, por exemplo **Restore/Resume**. Confirmar o rótulo e as condições efetivas.
3. Esperar pelo estado operacional e executar um teste limitado de login/leitura.
4. Abrir ambos os clientes e observar retoma da sync, incluindo operações e fotografias pendentes.
5. Se o dashboard não permitir retoma no Free, preservar dados locais e backups e rever recuperação/exportações disponibilizadas pelo fornecedor.

Não gerar tráfego artificial para contornar políticas de inatividade. Não ativar faturação nem limpar os clientes para “desbloquear” uma pausa.

Se PowerSync for escolhido, monitorizar também o seu painel e limites: é um serviço adicional. A divergência publicada entre uma e duas semanas de inatividade permanece por confirmar; não tomar nenhum prazo como garantia.

## 7. Cloudflare, login e manutenção

| Área | Ação |
|---|---|
| Publicações | Cloudflare > Workers & Pages > projeto > Deployments: confirmar produção, revisão e erros |
| Limites Pages | Rever builds, número de ficheiros e limite de 25 MiB por ficheiro antes de aumentar assets |
| Functions/Workers | Se existirem, acompanhar pedidos/CPU/erros no painel e condições Free atuais |
| Login por email | Rever SMTP, destinatários e quotas; falha de envio não se resolve com secret key no cliente |
| OAuth | Manter callbacks e acesso à conta; testar novamente depois de mudar origin/assinatura quando aplicável |
| Atualizações | Preservar dados pendentes, aplicar versão compatível e verificar migrações |
| Chave Android | Guardar keystore e passwords separadamente do backup do guarda-roupa; conservar identidade de atualização |

Backups do guarda-roupa não incluem passwords, refresh tokens, secrets, keystores nem signed URLs como única identidade de imagens. Logs partilháveis também não devem conter esses valores.

## 8. Diagnóstico sem perda de dados

| Problema | Ação segura |
|---|---|
| Metadata chegou mas foto não | Ver estado do asset, rede, quota e retry; não afirmar sync completa |
| Alterações ficam pendentes | Guardar diagnóstico, confirmar sessão/serviço e repetir pelo mecanismo suportado |
| Browser avisa falta de espaço | Preservar/exportar; rever cache recuperável com política segura, não limpar toda a IndexedDB |
| Conflito de disponibilidade | Aplicar resolução aprovada; não forçar “limpa” para gerar conjuntos |
| Recuperação incompatível | Parar antes da aplicação e conservar o original; não editar JSON à mão para forçar versão |
| Mudança de domínio | Sincronizar/exportar no origin antigo e validar o novo antes de abandonar o anterior |
| Perda da chave Android | Não gerar outra e prometer atualização direta; rever distribuição e salvaguarda dos dados |

Registar data, aparelho, revisão, estado local/cloud, última sync e passos observados. Não colar secrets ou um backup pessoal no chat para obter ajuda.

O resultado operacional esperado é recuperabilidade comprovada e erros visíveis, não a ausência fictícia de falhas dos serviços gratuitos.
