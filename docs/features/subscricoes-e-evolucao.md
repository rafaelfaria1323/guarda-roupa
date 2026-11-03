# Feature futura — Subscrições e evolução comercial

Estado: adiada. A versão pessoal não precisa de pagamentos, paywalls ou SDKs de billing.

## Objetivo futuro

Permitir planos comerciais sem reescrever regras de outfits nem sacrificar propriedade/portabilidade dos dados.

Não existe preço, plano comercial ou funcionalidade paga aprovada.

## Direção técnica

| Canal | Candidato | Condições |
|---|---|---|
| Web | Stripe Checkout/Billing | Comissões e termos comerciais; não é um serviço “totalmente grátis” |
| Lojas nativas | `in_app_purchase` e billing das lojas | Regras para bens digitais, contas de developer e comissões |
| Abstração de billing | RevenueCat ou equivalente | Facilita gestão, mas quotas/preços e dependência a comparar na altura |
| Sem pagamentos | Escolhido agora | Todo o foco no produto pessoal útil |

Entitlements validados no servidor por eventos/webhooks idempotentes. Uma flag no cliente não prova uma subscrição.

Regras de capacidade devem ser explícitas, não repartidas por widgets. Não criar já uma arquitetura genérica de feature flags sem uso.

## Antes de vender

1. Rever licenças de modelos, imagens, assets e packages.
2. Trocar/recontratar meteorologia conforme uso comercial.
3. Reavaliar quotas, pausas, backups e egress.
4. Definir suporte, eliminação/exportação de conta e obrigações legais aplicáveis.
5. Avaliar proteção de dados e consentimentos com aconselhamento adequado.
6. Testar compra, cancelamento, expiração, falha e recuperação de acesso.

Uso comercial pode exigir serviços pagos; não estender a promessa de custo zero pessoal a esta fase.

## Alternativas e impacto

Subscrição, compra única e versão gratuita com extras são modelos de negócio por comparar depois de validar valor e custos. Não escolher limites artificiais de guarda-roupa agora para servir um plano ainda inexistente.

Separação por utilizador é necessária já para privacidade/sync. Microserviços, organização empresarial e sistema de cobrança não são necessários já para “escalabilidade”.

## Ações e aceitação

O utilizador decide modelo comercial, cria contas comerciais e aceita termos/custos apenas nessa fase.

E2E-20 do [plano](../plano-e2e.md) será definido com o provedor escolhido. Este dossier não afirma compras ou conformidade já verificadas.
