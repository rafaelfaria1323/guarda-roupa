# Custos, quotas e limitações

Data de consulta: 2026-10-31. “Gratuito” significa sem pagamentos obrigatórios dentro das condições atuais; não significa capacidade, disponibilidade ou licenças ilimitadas.

## Serviços e distribuição

| Componente | Condições atuais/proposta | Limitação relevante |
|---|---|---|
| Flutter e bibliotecas open source | Sem custo por execução das bibliotecas propostas | Verificar licenças de dependências/assets e modelos separadamente |
| Android pessoal | APK próprio instalado diretamente | Chave de assinatura tem de ser preservada; distribuição/atualizações manuais inicialmente |
| iPhone/PWA | Acesso por HTTPS e adição ao ecrã principal | Não equivale a app nativa; não exige publicação App Store |
| Cloudflare Pages Free | Alojamento estático; 500 builds/mês; 20 mil ficheiros segundo limites publicados | 25 MiB por ficheiro; upload pelo dashboard tem limite de ficheiros diferente |
| Pages Functions/Workers Free | 100 mil pedidos/dia e 10 ms de CPU por execução | Não adequado a scraping pesado ou executar browsers |
| Supabase Free | 500 MB de base de dados, 1 GB de ficheiros, 5 GB de egress e rubrica própria de cached egress | Pausa após uma semana de inatividade; backups automáticos não incluídos |
| PowerSync Cloud Free, alternativa | 2 GB/mês de dados sincronizados, 500 MB alojados, 50 clientes simultâneos, sem cartão anunciado | Acrescenta outro serviço; limites e inatividade; media não passa a ser grátis |
| Open-Meteo gratuito | Uso pessoal não comercial, com atribuição e limites | Apps com subscrições/publicidade não cabem no endpoint gratuito não comercial |

Na página PowerSync consultada, o resumo refere desativação após uma semana e uma nota detalhada refere duas semanas. **Confirmar no serviço antes de escolher; não assumir um prazo garantido.**

## Firebase como alternativa

Cloud Storage for Firebase exige Blaze e conta de faturação, segundo a documentação atual. Existem quotas sem custo em Blaze, logo seria incorreto dizer que é sempre pago.

Contudo, ativar faturação por consumo não satisfaz da mesma forma o objetivo inicial de evitar risco de custos. Não confundir alertas de orçamento com um bloqueio rígido de despesa.

## Onde o espaço é realmente consumido

Fotografias e inspirações pesam mais do que centenas de linhas do catálogo. Gerar miniaturas e uma versão otimizada no cliente; não guardar todas as variantes originais sem uma necessidade definida.

Uma estimativa ilustrativa: 100 imagens de 250 KB representam cerca de 25 MB, antes de miniaturas, inspirações, backups e transferências entre dispositivos. Não é uma promessa de tamanho real.

Mostrar consumo e falhas. Quota cheia não pode apagar alterações locais nem ativar automaticamente um plano pago.

## Limitações de auth e email

O SMTP padrão do Supabase só envia para endereços autorizados da equipa e anuncia atualmente 2 mensagens/hora. Não assumir entrega de emails de produção a qualquer pessoa.

OAuth Google é uma recomendação para avaliar no uso pessoal, não uma escolha do utilizador já confirmada. Email/password e magic links continuam alternativas, com custos/limites de entrega documentados.

## Offline e persistência

O armazenamento da PWA é sujeito às políticas do browser. Pedir persistência, tratar falta de quota e manter backup/sync não cria uma garantia absoluta de retenção.

A primeira abertura precisa de rede para obter a aplicação. O funcionamento offline só é prometido depois de preparar os recursos necessários.

PWA fechada não executa sync contínua garantida no iPhone. Isto é compatível com a escolha confirmada de sincronizar ao abrir e durante utilização.

## Importação e conteúdo de terceiros

Lojas podem omitir metadados, alterar páginas ou bloquear pedidos. Um backend remove a limitação CORS do browser, não concede permissão nem torna todos os sites acessíveis. A importação aceita qualquer site, mas os que bloqueiam pedidos automáticos continuam a falhar (o perfil do domínio mostra “costuma falhar”); não se contorna anti-bot.

Um link Pinterest pode ser apenas um bookmark. Acesso à imagem/API e direitos de utilização são questões separadas. Uma imagem carregada por alguém não prova automaticamente que pode ser redistribuída comercialmente.

## IA local

Sem custo por inferência cloud, mas há download, RAM, CPU, bateria e licença do modelo. O limite de 25 MiB por ficheiro no Pages afeta tanto pesos como binários WASM. Atual (2026-11-04): `u2netp.onnx` 4,6 MB e `ort-wasm-simd-threaded.wasm` 11 MB, ambos abaixo do limite; o FashionCLIP q4 (80,9 MB) não cabe num só ficheiro do Pages e vem direto do Hugging Face (revisão fixa, sha256 confirmado, com CORS), sem custo. Se o Hugging Face o tirar ou limitar, a sugestão de categoria deixa de se poder descarregar; o resto da app não muda.

Não contratar um alojamento de modelos ou API paga como fallback silencioso.

## Futuro comercial

Prever custos de backend, armazenamento, emails, meteorologia comercial, comissões de pagamento, lojas e suporte. Publicação nativa iOS e subscrições não fazem parte da promessa de custo zero pessoal.

Rever estas condições antes de monetizar. Fontes: [registo de fontes](fontes.md).
