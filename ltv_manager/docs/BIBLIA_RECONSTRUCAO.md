# BÍBLIA DE RECONSTRUÇÃO — LTV MANAGER

**Documento técnico de referência para manutenção, evolução ou reconstrução do sistema.**

## 1. Propósito e limites

O LTV Manager é um módulo Django isolado para mensurar o valor acumulado de comissões atribuídas a aquisições ao longo do tempo. Possui banco próprio e pode ser integrado no futuro ao ROI Manager/Skallora por API.

O sistema não deve ser tratado como sistema de garantia de receita. O indicador observado representa somente dados existentes, aprovados e atribuídos. Pendente não é realizado. Projeção não é faturamento confirmado.

Esta versão implementa CRUD, importação CSV/XLSX, relatórios CSV, cálculos de coorte, uma projeção histórica simplificada, snapshots e automação local. Não implementa conectores reais com marketplaces.

## 2. Arquitetura

### 2.1 Camadas

- **Configuração (`config/`)**: settings, roteamento, ASGI e WSGI.
- **Persistência (`ltv/models.py`)**: modelos Django, índices, chaves e restrições.
- **Entrada/validação (`ltv/forms.py`)**: formulários com QuerySets limitados ao usuário autenticado.
- **Aplicação HTTP (`ltv/views.py`, `ltv/urls.py`)**: renderização, autenticação, CRUD, importação e exportação.
- **Analytics (`ltv/analytics/metrics.py`)**: agregações, horizontes de LTV, matriz de coortes, projeção e alertas.
- **Serviços (`ltv/services/importer.py`)**: leitura, normalização, pré-validação e gravação transacional dos extratos.
- **Automação (`ltv/automation/tasks.py`)**: snapshot diário e log de execução.
- **Comando de gestão (`ltv/management/commands/run_automations.py`)**: loop local de manutenção, verificando usuários habilitados.
- **Integrações (`ltv/integrations/base.py`)**: contrato abstrato, ainda sem adaptadores de marketplace.
- **Interface (`templates/`, `static/`)**: Django Templates, CSS modular e JavaScript.

### 2.2 Princípios arquiteturais

1. Não importar models do ROI Manager.
2. Não compartilhar o banco SQLite com o ROI Manager.
3. Usar `settings.AUTH_USER_MODEL` nas relações de conta.
4. Filtrar todos os registros de operação por `request.user`.
5. Usar `DecimalField` e `Decimal` em valores monetários.
6. Não inferir atribuição pela proximidade de datas.
7. Não transformar comissão pendente em receita aprovada.
8. Não apresentar projeção como resultado observado.
9. Não presumir endpoints de API nem contornar autenticação/termos de marketplaces.
10. Manter migrações versionadas no repositório.

## 3. Entidades e relacionamentos

### 3.1 Marketplace

Representa uma origem de venda: Magalu, Mercado Livre, Amazon, Shopee ou outros. É individual por usuário, com `code` único por conta. O sinal pós-criação de usuário cadastra opções padrão.

### 3.2 Channel

Representa a origem de divulgação: Telegram, WhatsApp, Instagram, TikTok, YouTube, Facebook, site/blog ou outros. É individual por usuário e possui código único por conta.

### 3.3 Product

Produto acompanhado na operação. Pode estar associado a um marketplace. O identificador externo é opcional; nunca presumir identidade de produto apenas pelo texto do nome.

### 3.4 Campaign

Campanha associada opcionalmente a marketplace e canal, com início, fim e status.

### 3.5 Acquisition

É a unidade de atribuição e de coorte. Campos principais:

- `external_reference`: referência pseudonimizada/externa, sem informação pessoal direta.
- `acquired_at`: data-hora de entrada.
- dimensões opcionais: marketplace, produto, campanha e canal.
- `attribution_method`: fonte da evidência.
- `confidence`: percentual de confiança declarado.

A referência externa é única por usuário quando preenchida. Uma aquisição pode existir sem identificação individual de consumidor. Exemplos aceitáveis incluem uma referência de campanha/pedido anonimizada ou um código interno não reversível.

### 3.6 Commission

Registro financeiro da comissão, com ID externo, fonte, valor, data de venda, aprovação, status, dimensões e aquisição opcional.

Status: `pending`, `approved`, `cancelled`, `refunded`, `reversed`.

Uma comissão pode ficar sem aquisição. O vínculo é opcional para não fabricar atribuição. O campo `attribution_evidence` deve explicar por que o vínculo foi feito manualmente. A ação operacional de remoção da comissão marca o status como `reversed` e preserva o registro; não deve ser substituída por exclusão física.

A restrição de unicidade usa usuário + fonte + ID externo quando o ID está preenchido. Na reimportação, o registro existente é atualizado quando status, valor, data ou dimensões mudaram; sem mudanças, a linha é ignorada. Registros sem ID externo não são deduplicados por uma heurística fraca de valor/data.

### 3.7 AttributionHistory

Guarda mudanças de relacionamento entre comissão e aquisição: comissão, aquisição anterior, aquisição nova, motivo, responsável e data. Alterações via formulário e vínculos resolvidos durante importação geram eventos.

### 3.8 ImportBatch

Guarda nome do arquivo, estado, linhas totais, importadas, atualizadas, ignoradas, com erro e prévia JSON. A prévia fica persistida para que a confirmação não dependa de manter o arquivo temporário aberto.

### 3.9 AutomationSettings / AutomationRun

Configuração individual e histórico das rotinas locais. `enabled=False` por padrão. O processo externo só executa usuários que habilitaram o recurso.

### 3.10 LTVSnapshot

Snapshot diário por usuário. A chave única é usuário + data. Os valores são atualizados no dia da execução, sem criar snapshots duplicados para cada ciclo do loop.

## 4. Regras financeiras e fórmulas

### 4.1 LTV observado por aquisição

Para uma aquisição `a` no instante `t0`, o LTV observado no horizonte `H` é:

`LTV(a, H) = soma das comissões aprovadas, atribuídas a a, cuja data de venda esteja entre t0 e t0 + H`.

O modelo não usa o GMV nem o valor bruto do pedido como receita do afiliado.

### 4.2 LTV médio por coorte e horizonte

`LTV médio da coorte em H = total das comissões acumuladas até H das aquisições elegíveis / quantidade de aquisições elegíveis`.

Uma aquisição só é elegível para D30 quando completou 30 dias. Aquisições elegíveis que não tiveram comissões entram como zero no denominador. Aquisições ainda imaturas não entram naquele horizonte.

### 4.3 LTV médio no dashboard

`LTV médio observado = comissões aprovadas e atribuídas / total de aquisições cadastradas`.

O valor é acumulado desde a entrada de cada aquisição até a data da consulta; por isso, coortes mais antigas tiveram mais tempo para gerar comissão. A análise por coorte é necessária para comparar horizontes equivalentes.

### 4.4 Totais

- `approved_total`: todas as comissões aprovadas da conta, mesmo que sem atribuição.
- `attributed_total`: comissões aprovadas com `acquisition` preenchida.
- `pending_total`: comissões pendentes, exibidas separadamente.
- canceladas/reembolsadas/revertidas: não integram LTV aprovado.

### 4.5 Projeção

`build_projection` seleciona a coorte de aquisições mais recente e usa as coortes anteriores como referência. Para cada faixa de idade em janelas de 30 dias, soma comissões aprovadas daquela janela por aquisição madura e calcula a média incremental. Os incrementos são adicionados ao valor observado da coorte alvo.

Condições atuais de amostra:

- ao menos 10 aquisições no histórico;
- ao menos 5 aquisições na base de referência;
- ao menos 2 aquisições na coorte alvo;
- ao menos 5 aquisições de referência maduras em cada janela necessária.

Quando não há amostra suficiente, retorna `available=False` e explica o motivo. O intervalo apresentado é uma aproximação estatística da média, não um intervalo calibrado de previsão individual. Não interpretar como promessa de receita.

## 5. Atribuição e integridade

Prioridade de atribuição futura:

1. identificador externo comprovado;
2. código de tracking ou referência que relacione explicitamente o registro;
3. evidência documental de campanha/canal;
4. atribuição manual com motivo e responsável.

Proibido:

- vincular por data próxima;
- presumir que todo clique representa venda;
- atribuir todas as comissões de uma campanha a uma aquisição;
- inventar ID de cliente;
- substituir pendente por aprovada sem informação da origem.

Durante uma importação, o sistema só relaciona a aquisição quando `acquisition_external_id` corresponde exatamente a `Acquisition.external_reference` dentro da mesma conta. A ausência de correspondência deixa a comissão não atribuída.

## 6. Fluxo de importação

1. Validar extensão e tamanho (10 MB).
2. Ler CSV (UTF-8/CP1252/Latin-1) ou XLSX (openpyxl).
3. Normalizar cabeçalhos com aliases em português/inglês.
4. Exigir valor e data da venda.
5. Converter valor para `Decimal` e data para timezone ativo.
6. Normalizar status.
7. Construir prévia JSON, com erro por linha.
8. Criar `ImportBatch` em estado `preview`.
9. Exibir primeiras 30 linhas para revisão.
10. Na confirmação, executar gravação em `transaction.atomic()`.
11. Criar/recuperar dimensões textuais associadas ao arquivo.
12. Vincular aquisição apenas por referência exata.
13. Atualizar comissão existente quando ID externo e origem coincidirem e os dados mudarem; ignorar quando não houver alteração.
14. Salvar contadores e resumo no lote.

Cabeçalhos mínimos: valor e data da venda. Um modelo vazio de cabeçalhos está em `docs/modelo_importacao_comissoes.csv`. Linhas totalmente vazias são ignoradas; arquivos sem registros úteis são rejeitados. O mapeamento de nomes alternativos está em `ltv/services/importer.py` na constante `ALIASES`.

## 7. Automação atual e extensões

### 7.1 Implementado

- execução manual pelo botão de manutenção;
- execução em loop por comando Django;
- filtro de usuários com automação habilitada;
- respeita intervalo individual por usuário;
- cria ou atualiza snapshot do dia;
- registra início, fim, status, total processado e detalhes;
- permite interromper com `CTRL+C`.

Comando:

`python manage.py run_automations --loop --interval 900`

O processo usa o banco local e não deve ser iniciado em duplicidade sem controle. A rotina depende do Windows ligado e do terminal aberto.

### 7.2 Ainda não implementado

- coleta de pedidos/comissões em marketplace;
- autenticação OAuth ou tokens específicos;
- sincronização incremental com APIs;
- envio de alertas por Telegram, WhatsApp ou e-mail;
- tarefas distribuídas Celery/Redis;
- previsão de coorte por modelo estatístico de sobrevivência.

### 7.3 Como implementar conector real

Estenda `MarketplaceConnector` de `ltv/integrations/base.py`. O conector precisa implementar `authenticate`, `fetch_commissions` e `normalize_commission`. Antes de codificar, obtenha documentação atual e credenciais oficiais. Inclua paginação, rate limits, janelas de sobreposição, retentativas com backoff, idempotência, atualização de status e logs sem segredos.

Não implemente scraping contra barreiras de acesso, autenticação ou termos da plataforma.

## 8. Rotas principais

| Rota | Finalidade |
|---|---|
| `/accounts/login/` | Login |
| `/accounts/register/` | Cadastro |
| `/dashboard/` | Dashboard |
| `/aquisicoes/` | Lista de aquisições |
| `/comissoes/` | Lista de comissões |
| `/marketplaces/` | Marketplaces |
| `/produtos/` | Produtos |
| `/campanhas/` | Campanhas |
| `/canais/` | Canais |
| `/analises/` | Análise de LTV e projeção |
| `/coortes/` | Matriz D7 a D365 |
| `/importacoes/` | Prévia/confirmar CSV-XLSX |
| `/automacoes/` | Configuração e histórico |
| `/relatorios/` | Resumo e exportação |
| `/relatorios/exportar-comissoes/` | CSV de comissões |
| `/api/graficos/` | JSON dos gráficos do dashboard |
| `/admin/` | Administração Django |

## 9. Interface e identidade visual

### 9.1 Paleta

- verde principal `#018D3E`;
- verde escuro `#006B30`;
- verde profundo `#004B23`;
- verde vivo `#2ECC71`;
- creme `#FDF7E6`;
- vermelho principal `#E71506`;
- vermelho vivo `#FF4D43`;
- texto escuro `#10251A`;
- texto secundário `#65756A`.

O verde é a identidade dominante. Creme sustenta a área de leitura. Vermelho deve ser uma cor de acento visível, não apenas uma cor de erro: aparece na marca, nos destaques da sidebar, em bordas superiores de cards selecionados, em alertas, ações destrutivas e série de projeção.

### 9.2 Design system CSS

Arquivos carregados pelo `templates/base.html` em ordem:

1. `variables.css` — design tokens.
2. `base.css` — reset, fontes, fundo, textos, mensagens.
3. `layout.css` — app shell, sidebar, header, footer, superfícies glass.
4. `components.css` — botões, badges, painéis, alertas, empty states.
5. `dashboard.css` — KPIs, grids, charts, métricas, painéis específicos.
6. `charts.css` — canvas, áreas vazias e dimensionamento de gráficos.
7. `forms.css` — campos, validações, auth e upload.
8. `tables.css` — tabelas, estados e ações.
9. `responsive.css` — breakpoints e acessibilidade de movimento.

#### Tokens centrais

`--primary`, `--primary-dark`, `--primary-deep`, `--primary-light`, `--cream`, `--danger`, `--danger-light`, `--text-primary`, `--text-secondary`, `--glass-bg`, `--glass-border`, `--radius-*`, `--shadow-*`, `--blur-glass`, `--sidebar-width`, `--header-height` e `--transition-*`.

Não duplicar hexadecimais em dezenas de seletores. Quando uma nova variação for necessária, adicionar token em `variables.css`.

### 9.3 Glassmorphism

`.glass-panel` implementa:

- `background: var(--glass-bg)`;
- `backdrop-filter: blur(var(--blur-glass))`;
- `-webkit-backdrop-filter` para Safari/WebKit;
- borda creme translúcida;
- sombra exterior suave;
- brilho interno com `inset 0 1px`.

`.glass-dark` é a superfície escura para sidebar e destaques, com transparência verde, blur maior e borda branca de baixa opacidade.

Manter contraste de texto. Não usar vidro em campos com baixo contraste ou blur sobre texto pequeno sem superfície opaca suficiente.

### 9.4 Fundo

O `body` usa gradientes radiais verde e vermelho por cima de gradiente linear verde. `.ambient-red` e `.ambient-green` adicionam luzes desfocadas fixas. As camadas decorativas usam `pointer-events:none` e ficam atrás do conteúdo.

### 9.5 Tipografia

Família: Inter. A fonte é carregada pelo Google Fonts no HTML; para operação totalmente offline, deve ser substituída por fonte local licenciada ou sistema sans-serif. Escalas, pesos e tracking devem seguir tokens definidos em `variables.css` e títulos compactos com `letter-spacing` negativo.

### 9.6 Layout

- Sidebar fixa em desktop, 258 px de largura, com painel `glass-dark`.
- Conteúdo principal usa margem equivalente à sidebar.
- Header horizontal com título, indicador local e avatar.
- Dashboard usa grids fluidos, cinco cards KPI em desktop e duas colunas em telas intermediárias.
- Em largura até 900 px, sidebar passa a drawer controlado por `main.js`.
- Em largura até 650 px, grids viram coluna única; formulários passam a uma coluna; tabelas continuam com scroll horizontal.

### 9.7 Vermelho — frequência de uso

A cor `#E71506` não deve ficar restrita a mensagens negativas. Preservar presença de aproximadamente 15%–20% dos acentos cromáticos em telas de análise, balanceando com o verde. Aplicações atuais: borda superior de KPI alternado, ícones vermelhos, rótulos eyebrow-red, marca do logo, destaque do item ativo, alertas, botões destrutivos, badges de atribuição pendente e curva de projeção.

## 10. Templates e componentes de interface

- `base.html`: estrutura autenticada, sidebar, header, mensagens, footer e inclusão de CSS/JS.
- `dashboard.html`: KPIs, alertas, série histórica, distribuição por produto/campanha/canal/marketplace, variação mensal, atividade recente.
- `form_page.html`: formulário padrão de duas colunas, erros e ações.
- `acquisition_list.html`: busca e tabela de aquisição.
- `commission_list.html`: filtros por status, vínculo e ações.
- `resource_list.html`: listagem reutilizável para marketplace/produto/campanha/canal.
- `analysis.html`: gráficos, resumo e projeção.
- `cohorts.html`: tabela D7/D30/D60/D90/D180/D365.
- `import.html`: upload, validação e confirmação.
- `automation.html`: configuração local e histórico de tarefas.
- `reports.html`: resumo e exportações.
- `registration/login.html` e `register.html`: autenticação sem sidebar.

Botões de exclusão usam POST, CSRF e confirmação. Não transformar exclusão em links GET.

## 11. JavaScript e gráficos

- `main.js`: drawer mobile, confirmação de formulários e fechamento de mensagens.
- `charts.js`: consome JSON embutido por `json_script`, inicializa gráficos Chart.js por mês, produto, campanha, canal e marketplace, incluindo barras horizontais com escalas e tooltips monetários corretos, e mostra empty states. Para classificar uma comissão, a dimensão registrada diretamente nela tem prioridade; se estiver vazia, os gráficos usam a dimensão da aquisição vinculada.
- `dashboard.js`: ponto de extensão do dashboard.
- `analysis.js`: série observada/projetada e faixas aproximadas de incerteza.

Chart.js está referenciado por CDN versão 4.4.8. Se a biblioteca não carregar ou a série não possuir dados, o sistema mostra uma mensagem de ausência em vez de gráfico inventado. Para implantação offline, manter o mesmo código e distribuir a biblioteca em `static/vendor/` com licença e versão documentadas.

Nunca montar JavaScript com texto não confiável sem escape. Para dados Django, usar `json_script`, não interpolar dicionários diretamente em `<script>`.

## 12. Segurança e isolamento

- As páginas de negócio usam `login_required`.
- QuerySets das telas são filtrados por `request.user`.
- ModelChoiceField nos formulários usa QuerySets do usuário atual.
- ForeignKey de comissão valida que a aquisição pertence à mesma conta.
- IDs externos são únicos por conta/fonte quando informados.
- Formulários POST usam CSRF.
- As senhas usam o hash do Django.
- Credenciais de implantação ficam no `.env`.
- Não coletar dados pessoais identificáveis de consumidores.
- `.env` e `db.sqlite3` não devem ser commitados.

Em produção, adicionar rate limiting de login, política de backup, rotação de segredo, revisão de dependências e configuração HTTPS/hosts.

## 13. Testes

Localização: `ltv/tests/`.

Cobertura inicial:

- LTV médio usa comissões aprovadas e atribuídas, excluindo pendentes e aprovadas sem atribuição;
- D7 disponível quando a coorte amadureceu e D30 ausente antes da maturidade;
- dashboard exige autenticação e inclui referência CSS absoluta `/static/`;
- isolamento de aquisições entre usuários;
- leitura de CSV com valor brasileiro e status localizado.

Executar com `scripts/verificar_projeto.bat`. O teste `makemigrations --check --dry-run` verifica divergência entre models e migrações.

## 14. Evolução recomendada

Ordem segura de evolução:

1. Adicionar testes de importação XLSX, status de reembolso, atribuição e duplicidade em arquivos reais anonimizados.
2. Separar o importador por perfil de marketplace e permitir mapeamento salvo de colunas.
3. Criar uma tabela de fontes/conectores e credenciais criptografadas, sem guardar segredo em texto claro.
4. Implementar primeiro um conector oficial com documentação, credenciais e ambiente de testes.
5. Adicionar Celery/Redis ou worker apropriado para execução distribuída quando necessário.
6. Acrescentar alertas configuráveis e trilha de auditoria completa.
7. Refinar modelo estatístico somente depois de acumular histórico suficiente.
8. Definir API versionada para integrar ao ROI Manager/Skallora.

## 15. Procedimento de reconstrução

1. Criar ambiente Python compatível.
2. Instalar `requirements.txt`.
3. Configurar `.env`.
4. Aplicar `ltv/migrations/0001_initial.py` com `manage.py migrate`.
5. Criar superusuário se necessário.
6. Validar `manage.py check` e `manage.py test ltv.tests`.
7. Conferir que todos os CSS/JS são servidos em `/static/`.
8. Conferir login, cadastro, dashboard vazio, CRUD, prévia de importação, confirmação, coortes e exportação.
9. Rodar automação com uma conta explicitamente habilitada.
10. Só então habilitar conectores reais, com credenciais oficiais.

## 16. Itens não implementados que não devem ser anunciados como prontos

- APIs de afiliados de marketplaces;
- OAuth/autorização de conta de marketplace;
- importação automática por pasta monitorada;
- sync incremental de status com API;
- classificação de vendas baseada em modelos ML;
- alertas por Telegram/WhatsApp/e-mail;
- previsão de churn ou LTV individual por modelo avançado;
- integração de API com ROI Manager/Skallora.

Esses itens são pontos de evolução, não funcionalidades disponíveis no pacote atual.
