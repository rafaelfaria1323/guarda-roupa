# Feature — Lembretes por notificação

Estado: implementado a 2026-11-06 (pedido do utilizador: tornar a app mais automática). Falta experimentar no iPhone.

## O que faz

Dois lembretes, cada um ligado ou desligado em **Definições › Lembretes**, com a hora escolhida:

| Lembrete | Hora inicial | Quando sai | Ao tocar |
|---|---|---|---|
| **“Vestiste isto?”** | 21:30 | Se ainda não registaste nada nesse dia. Com roupa planeada, diz quais são as peças (“Vestiste a t-shirt branca e as calças de ganga? Toca para confirmar.”); sem plano, só lembra que falta registar | Abre o “Vesti hoje” com as peças planeadas já escolhidas. **Nada conta como uso sem tocares em Guardar** (P-08) |
| **Véspera** | 20:00 | Se o dia seguinte tem roupa planeada: “Amanhã: T-shirt, Calças de ganga e Ténis. Leva também: Chapéu-de-chuva.” Os acessórios só aparecem quando o tempo os pede (chuva, frio, sol), como no motor | Abre o Planeador |

- A hora é a hora local do fuso do aparelho onde ligaste os lembretes.
- Cada lembrete sai no máximo uma vez por dia. Se o servidor se atrasar, ainda sai até 2 horas depois da hora marcada, mas nunca passa da meia-noite.
- Recebem-se nos aparelhos onde se ligaram. Noutro aparelho, o ecrã mostra “Receber também neste aparelho”. Desligar os dois lembretes tira este aparelho da lista.

## No iPhone

- Só funciona com o fio **instalado no ecrã principal** (Safari → Partilhar → Adicionar ao ecrã principal), iOS 16.4 ou mais recente. No Safari normal, o ecrã explica isso.
- O iPhone pede autorização da primeira vez que ligas um lembrete. Se recusares, só se volta a ligar em Ajustes › Notificações › fio.

## Como funciona

- **Textos:** a app escreve o texto de cada um dos próximos dias (nomes das peças e acessórios pelo tempo) e guarda-o em `day_summaries` com a versão da entrada do plano. Se o plano mudar depois e a app não voltar a abrir, o servidor manda um texto genérico (“Já tens roupa planeada para amanhã. Toca para ver.”). Assim os nomes das peças nunca ficam desatualizados.
- **Envio:** o `pg_cron` chama a Edge Function `reminders` de 5 em 5 minutos. A função pede à base os lembretes que chegaram à hora (`claim_due_reminders`), que os marca como enviados de uma só vez (`reminder_sends`), e manda-os por Web Push (VAPID). Aparelhos que o serviço de push dá como desaparecidos (404/410) são apagados.
- **Segurança:** a função não tem privilégios. O cron passa-lhe um token gerado dentro da base (`private.reminder_cron`), que nunca sai de lá, e só com esse token a base devolve lembretes. As chaves VAPID são geradas pelo workflow “Supabase” na primeira publicação e ficam só nos secrets da função. Um `GET` à função devolve a chave pública, a única que a app precisa.
- **Só a allowlist:** as definições e os aparelhos só se guardam para quem está em `allowed_users`, e o servidor confirma isso outra vez antes de enviar.
- **Abrir a app no sítio certo:** o service worker abre `#/vesti?pecas=…&plano=…`. Se a app já estiver aberta, manda-lhe uma mensagem e a app navega.

Código: `lib/features/reminders/`, `supabase/functions/reminders/`, `supabase/migrations/20261121000001_reminders.sql`, `web/push_worker.js`. Dados em [modelo de dados](../modelo-de-dados.md#lembretes-2026-11-06).

## Limites

- Precisa de rede no aparelho e de o serviço de push do navegador (Apple, Google, Mozilla) entregar a mensagem. Não há garantia de hora exata: o cron corre de 5 em 5 minutos.
- Não há lembretes no Android nativo nem no desktop sem PWA. Na build Web do Chrome funciona.
- O texto com as peças só existe para dias que a app viu desde a última mudança no plano.
