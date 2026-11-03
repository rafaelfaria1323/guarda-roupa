# Roadmap incremental

Estado: proposta de execução; não são tarefas já realizadas. Data: 2026-10-31.

Não há estimativas de calendário sem conhecer disponibilidade e resultados das POCs. Cada incremento tem uma demonstração de valor e um gate explícito.

| Incremento | Entrega | Dependência | Gate para avançar |
|---|---|---|---|
| 0 — Fecho técnico | Login, backend, motor sync, baseline de dispositivos e UX essencial | Aprovar decisões abertas relevantes | P-01 a P-04 com plano claro |
| 1 — Fundação nos dois dispositivos | Conta, SQLite, uma peça com foto, sync, reabertura offline | Incremento 0 | A mesma peça/imagem existe no Android e iPhone/PWA; sem perda ao retomar |
| 2 — Catálogo e recuperação | CRUD, filtros, atributos, arquivo e exportação/recuperação inicial | Fundação | Dados e fotografias persistem; backups verificáveis |
| 3 — Uso e lavandaria | Confirmação real, histórico, recomendações e disponibilidade | Catálogo | Planeamento não conta como uso; indisponíveis não são candidatos |
| 4 — Conjuntos e estilo assistido | Guardar/classificar conjuntos e referências | Catálogo e histórico | Inspirações não aparecem como posse; categorias não fixam layers |
| 5 — Motor diário | Contexto, cores, padrões/texturas, conforto e razões | Atributos, políticas, estilo | Conjuntos completos válidos, incluindo t-shirt como top único |
| 6 — Semana utilizável | Reservas, pesquisa conjunta, diversidade e alterações propostas | Motor diário e eventos | Sete datas tratadas coerentemente, ou limitações explicadas |
| 7 — Entrada assistida por lojas | POC por loja e importador limitado | Infraestrutura estável e regras de acesso | Dados/variante confirmáveis, erros e alternativa manual |
| 8 — IA local | POC de modelo e runtime | Dados de qualidade e licença | Precisão/desempenho úteis na PWA, sem tornar a app dependente do modelo |
| 9 — Produto comercial | Multiutilizador público, pagamentos e operação | Utilidade validada e revisão de custos | Regras das lojas, autorização e obrigações operacionais |

## MVP versus incremento

Incremento 1 é uma fundação, não o produto prometido. O MVP de planeamento semanal culmina no incremento 6, incluindo sync e estilo assistido.

Importação automática universal, Pinterest automático e IA visual avançada não bloqueiam esse MVP. Links podem ser guardados antes de serem interpretados automaticamente.

## Procedimento em cada incremento

1. Rever a feature, ADRs e pendências relevantes.
2. Resolver o gate que possa invalidar a implementação.
3. Identificar ações humanas e seguir o guia correspondente.
4. Implementar apenas o incremento e manter os contratos necessários.
5. Demonstrar os cenários de comportamento com dados isolados e persistência real.
6. Registar evidência, limitações, versões e decisões novas.
7. Só depois avançar.

## Ações do utilizador por fase

| Fase | Ação humana |
|---|---|
| Antes de criar serviços | Aprovar fornecedor/login e confirmar aceitação dos limites Free |
| Fundação | Criar contas, autorizar OAuth e disponibilizar Android/iPhone |
| Catálogo | Utilizar um conjunto de dados de experiência, sem necessidade de contar todo o guarda-roupa |
| Políticas | Rever limites de repetição e recomendações editáveis |
| UX/motor | Avaliar se propostas fazem sentido e indicar preferências explícitas |
| Distribuição | Instalar APK/PWA e preservar chave de assinatura |
| Operação | Confirmar recuperação e acompanhar consumo/pausas |

Ações com login, 2FA, aceitação de termos, segredos ou eventual pagamento são do utilizador. Não assumir que foram feitas sem confirmação.

## Critério de conclusão

Não basta compilar ou apresentar coverage. Os percursos relevantes de [Plano E2E](plano-e2e.md) devem ter resultado documentado no ambiente correspondente. Limitações de hardware/automação ficam “pendente”, não “passou”.
