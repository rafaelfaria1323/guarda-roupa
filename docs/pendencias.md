# Pendências, riscos e provas de viabilidade

Data: 2026-10-31. Nenhuma POC da aplicação foi executada durante a criação deste dossier.

Uma pendência não deve desaparecer por estar descrita em Markdown. Fechar apenas com decisão/evidência e data.

| ID | Tema e estado | Como fechar | Bloqueia |
|---|---|---|---|
| P-01 | Backend — Supabase recomendado | Aprovar após comparar custos, quotas, localização e requisitos | Criação da infraestrutura |
| P-02 | Login — método não escolhido | Escolher Google OAuth, email/password ou outro com recuperação real | Fluxo de conta |
| P-03 | Sync — engine não escolhido | POC PowerSync/Drift versus protocolo próprio; dados e media em Android/Safari | Fundação |
| P-04 | Conflitos e privacidade | Definir semântica, autorização, logout e confirmação idempotente | Uso da conta em dois dispositivos |
| P-05 | PWA/fotografias | Demonstrar armazenamento persistente, quotas, HEIC e reabertura offline no iPhone | Onboarding real |
| P-06 | Política de rotatividade | Definir modos e valores iniciais editáveis para tops/calças; calçado/acessórios já podem repetir | Motor com políticas reais |
| P-07 | Recomendações de lavagem | Aprovar defaults informativos e overrides, sem automatismo implícito | Avisos iniciais |
| P-08 | UX e rotina semanal | Aprovar ecrãs, dias/ocasiões por defeito, edição e confirmação | MVP de utilização |
| P-09 | Perfis e desempenho | Escolher dispositivos de referência e orçamento mensurável | Gate de desempenho |
| P-10 | Automação E2E | POC Patrol Android/Chromium; guião iPhone real, sem equivalência fictícia | Evidência por plataforma |
| P-11 | Recuperação com cloud | Definir substituição/recuperação sem replay de eventos nem ressurreição silenciosa | Recuperação sobre conta existente |
| P-12 | Lojas suportadas | POC com links reais autorizados, metadados, variantes e imagens | Anunciar suporte a uma loja |
| P-13 | Pinterest | Confirmar permissões/API; link não garante imagem | Importação automática de Pins |
| P-14 | Modelo IA | Licença, operadores, tamanho, precisão e desempenho | Ativar análise visual automática |
| P-15 | Assinatura/distribuição Android | Definir applicationId, guardar chave e comprovar atualização sem apagar dados | Distribuição estável |
| P-16 | Registo pessoal/público | Definir quem pode criar conta e impor a regra no servidor | Expor login publicamente |

## O que já não está pendente como requisito

Sync desde o início; sync em primeiro plano suficiente; apenas uso confirmado; replaneamento com confirmação; inspirações assistidas primeiro; t-shirt como top único possível; repetição de calçado/acessórios para este utilizador.

## POC mínima de sincronização

1. Criar conta de experiência isolada.
2. Adicionar peça/foto no Android e observar na PWA.
3. Editar offline e reconectar sem perder a alteração.
4. Confirmar a mesma entrada nos dois dispositivos sem duplicar o evento.
5. Produzir um conflito de disponibilidade e observar a resolução definida.
6. Eliminar/arquivar, reconectar um dispositivo antigo e impedir recuperação involuntária.
7. Interromper upload de imagem e retomar com estado honesto.
8. Comprovar isolamento com outra conta.

Idempotência de retries e da mesma entrada de plano não deduplica magicamente duas utilizações manuais independentes.

## Riscos que permanecem mesmo com boa implementação

- Offline não conhece alterações recentes de outro dispositivo.
- Previsões mudam; uma recomendação não controla o tempo real.
- Aparência e conforto são subjetivos.
- Browser/OS podem remover dados locais.
- Free tiers podem alterar limites ou suspender por inatividade.
- Lojas e plataformas podem mudar acessos.

## Registo futuro de fecho

Para cada ID: decisão, responsável, data, versões, procedimento, resultado observado e limitações. Se falhar, documentar alternativa e impacto no roadmap, não improvisar um fallback pago ou silencioso.
