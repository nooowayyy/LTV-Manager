# LTV Manager

Aplicação Django independente para acompanhar o **Lifetime Value (LTV)** de operações de afiliados, com foco em comissões atribuídas, análise por coortes, importação de dados e manutenção automatizada.

> **Importante:** esta versão é funcional como sistema local de registro, importação e análise. Os conectores de API de Magalu, Mercado Livre, Amazon e Shopee ainda não estão implementados nem autorizados. Não há sincronização automática de pedidos/comissões diretamente com esses marketplaces nesta entrega.

## 1. O que o sistema faz

- Registra aquisições, comissões, produtos, campanhas, canais e marketplaces.
- Permite administrar marketplaces e dimensões cadastradas pela própria interface.
- Separa comissões aprovadas, pendentes, canceladas, reembolsadas e revertidas.
- Calcula LTV realizado usando somente comissões aprovadas e atribuídas a uma aquisição.
- Exibe LTV médio observado, comissões aprovadas, pendentes, variação mensal e volume de aquisições.
- Compara comissões atribuídas por produto, campanha, canal e marketplace, usando os dados da aquisição como fallback quando a dimensão não está repetida na comissão.
- Constrói matriz de coortes com horizontes D7, D30, D60, D90, D180 e D365.
- Gera uma projeção experimental baseada em incrementos históricos por idade da aquisição, somente quando há amostra suficiente.
- Importa arquivos CSV e XLSX com pré-visualização, validação por linha e confirmação antes da gravação.
- Detecta duplicidade por identificador externo e origem de importação.
- Registra histórico quando uma comissão é vinculada ou transferida entre aquisições pelo formulário.
- Exporta comissões em CSV.
- Gera snapshots diários e mantém histórico de execução da manutenção local.
- Oferece telas responsivas com a identidade visual verde, creme e vermelha, usando glassmorphism.

## 2. Requisitos

- Windows 10 ou 11.
- Python 3.12 ou 3.13, disponível no CMD como `python` (recomendado: Python 3.12).
- Conexão com a internet durante a primeira instalação para baixar as dependências Python e carregar fontes/gráficos externos.
- Navegador moderno.

Dependências principais: Django 5.2, dj-database-url, openpyxl, python-dotenv, WhiteNoise e psycopg.

## 3. Instalação pelo CMD

Extraia o ZIP em uma pasta simples, por exemplo `C:\Projetos\ltv_manager`.

Abra o **Prompt de Comando (CMD)** nessa pasta e execute:

```cmd
scripts\preparar_ambiente.bat
```

O instalador:

1. Cria `.env` a partir de `.env.example`, caso ainda não exista.
2. Cria o ambiente virtual `venv`.
3. Instala as dependências de `requirements.txt`.
4. Aplica as migrações incluídas no projeto.
5. Executa `manage.py check`.

Não é necessário usar PowerShell.

### Comandos manuais equivalentes

```cmd
python -m venv venv
venv\Scripts\activate.bat
python -m pip install --upgrade pip
pip install -r requirements.txt
python manage.py migrate
python manage.py check
```

## 4. Configuração

O arquivo `.env` fica na raiz do projeto. O instalador copia o exemplo automaticamente. Ajuste, quando necessário:

```env
SECRET_KEY=troque-por-uma-chave-longa-e-aleatoria
DEBUG=True
ALLOWED_HOSTS=127.0.0.1,localhost
CSRF_TRUSTED_ORIGINS=
DATABASE_URL=sqlite:///db.sqlite3
TIME_ZONE=America/Sao_Paulo
AUTOMATION_INTERVAL_SECONDS=900
```

Para uso local, SQLite é suficiente. Para PostgreSQL, configure `DATABASE_URL` com a URL de conexão do banco e mantenha as credenciais fora do repositório.

**Antes de disponibilizar o sistema em uma rede ou hospedá-lo:** use `DEBUG=False`, `SECRET_KEY` exclusiva, `ALLOWED_HOSTS` restritos, HTTPS, `CSRF_TRUSTED_ORIGINS` correto, PostgreSQL e backup. Não publique o `.env`.

## 5. Iniciar a aplicação

Execute:

```cmd
scripts\iniciar_servidor.bat
```

Acesse no navegador:

**http://127.0.0.1:8000/**

O primeiro acesso redireciona para a tela de login. Crie sua conta em **Criar conta**. Os marketplaces e canais padrão são adicionados automaticamente ao criar um usuário.

Para criar um usuário administrador do Django:

```cmd
venv\Scripts\python.exe manage.py createsuperuser
```

O painel administrativo fica em `http://127.0.0.1:8000/admin/`.

## 6. Como usar

### 6.1 Cadastrar uma aquisição

Cadastre primeiro as dimensões em **Marketplaces**, **Produtos**, **Campanhas** e **Canais**, quando necessário. Depois abra **Aquisições → Nova aquisição**. Informe a data, marketplace, produto, campanha e canal, quando conhecidos. A referência externa deve ser pseudonimizada ou não identificável. Não armazene nome, telefone, CPF, e-mail ou outros dados pessoais de consumidores.

O método de atribuição deve refletir a evidência disponível. Use **Não atribuída** quando não houver evidência para relacionar a origem.

### 6.2 Cadastrar uma comissão

Abra **Comissões → Nova comissão**. Informe o valor da comissão, a data da venda e o status. Uma comissão só entra no LTV realizado quando:

- seu status é `Aprovada`; e
- está vinculada a uma aquisição da mesma conta.

A comissão pode permanecer sem aquisição. Ela continua visível no total geral de comissões aprovadas, mas não deve ser distribuída artificialmente no LTV por aquisição. A ação **Reverter** preserva o registro e altera seu status, em vez de apagá-lo.

Ao vincular uma comissão manualmente, informe a evidência no campo correspondente. Alterações de vínculo pelo formulário deixam um registro no histórico de atribuição. Ao remover uma aquisição, os vínculos são encerrados com histórico e as comissões ficam preservadas sem atribuição.

### 6.3 Importar CSV ou XLSX

Abra **Importações**, selecione um arquivo e clique em **Analisar arquivo**. Um modelo de cabeçalhos está em `docs/modelo_importacao_comissoes.csv`; preencha as linhas com seus dados antes de enviar. Revise a prévia. Somente depois clique em **Confirmar importação**.

Campos mínimos reconhecidos:

| Campo | Obrigatório | Exemplos de cabeçalho reconhecidos |
|---|---:|---|
| Valor da comissão | Sim | `valor`, `comissao`, `amount`, `commission_amount` |
| Data da venda | Sim | `data`, `data_venda`, `sale_date`, `date` |
| ID externo | Não | `id`, `id_externo`, `external_id`, `order_id` |
| Status | Não | `status`, `situacao` |
| Marketplace | Não | `marketplace`, `origem`, `plataforma` |
| Produto | Não | `produto`, `product`, `item` |
| Campanha | Não | `campanha`, `campaign` |
| Canal | Não | `canal`, `channel` |
| Referência da aquisição | Não | `acquisition_id`, `tracking_id`, `aquisicao_id` |
| Evidência | Não | `evidencia`, `attribution_evidence` |

O valor pode estar em formato brasileiro (`1.234,56`) ou internacional (`1234.56`). Datas aceitas incluem `DD/MM/AAAA` e `AAAA-MM-DD`.

Status reconhecidos: aprovada/approved, pendente/pending, cancelada/cancelled, reembolsada/refunded e revertida/reversed. Se o status estiver ausente, será considerado pendente.

O vínculo por referência de aquisição só ocorre quando o identificador informado corresponde exatamente a uma aquisição existente da mesma conta. Não existe atribuição por proximidade de data.

Ao importar novamente o mesmo ID externo da mesma origem, o sistema atualiza o registro existente quando valor, data, status ou dimensões mudaram; se nada mudou, ignora a linha. Registros sem ID externo não são deduplicados automaticamente, pois uma repetição de valor e data não prova que se trata da mesma comissão.

Limites atuais: 10 MB e 2.000 linhas por arquivo; a prévia mostra as primeiras 30 linhas, mas a confirmação processa as linhas analisadas.

### 6.4 Entender o dashboard

- **LTV médio:** soma das comissões aprovadas e atribuídas dividida pelo número de aquisições cadastradas. É uma média observada até hoje, não uma garantia de valor final.
- **Comissões aprovadas:** total de comissões aprovadas, incluindo registros ainda não atribuídos.
- **Comissões pendentes:** valor aguardando aprovação; não é receita realizada.
- **Aquisições:** unidades registradas na base.
- **Evolução mensal:** série de comissões aprovadas e atribuídas.

### 6.5 Coortes

A matriz agrupa aquisições pelo mês de entrada e calcula a comissão acumulada por aquisição até D7, D30, D60, D90, D180 e D365. Só exibe um horizonte quando as aquisições usadas no denominador já tiveram tempo para completá-lo. Aquisições elegíveis sem comissão aprovada contam como zero, evitando inflar o resultado.

### 6.6 Projeção

A projeção é uma estimativa exploratória, baseada na média de comissões incrementais de coortes históricas por faixa de idade da aquisição. A tela exige amostras mínimas e informa quando não há evidência suficiente.

A projeção não é receita confirmada, não é garantia de comissão futura e não deve ser usada isoladamente para decisões financeiras. A faixa de incerteza é aproximada e depende da qualidade e representatividade do histórico.

### 6.7 Automações

1. Abra **Automações**.
2. Ative a manutenção automática e defina o intervalo.
3. Salve as configurações.
4. Abra um segundo CMD e execute `scripts\iniciar_automacao.bat`.

A rotina cria/atualiza o snapshot diário de comissões, aquisições e LTV médio, e registra o histórico de execução. O CMD deve permanecer aberto. Para interromper, use `CTRL+C`.

A rotina **não consulta marketplaces** nesta versão. A importação de extratos continua sendo manual. O conector abstrato está preparado para desenvolvimento de integrações oficiais futuras, mas nenhum marketplace está conectado.

## 7. Testes e verificação

Com o ambiente instalado, execute:

```cmd
scripts\verificar_projeto.bat
```

O script executa:

- `manage.py check`;
- `makemigrations --check --dry-run`;
- `manage.py test ltv.tests`;
- compilação sintática dos módulos Python.

Também é possível executar os testes diretamente:

```cmd
venv\Scripts\python.exe manage.py test ltv.tests
```

## 8. Banco de dados e backups

O banco local fica em `db.sqlite3`. Faça uma cópia com o servidor parado ou usando uma rotina de backup consistente. Não apague o banco para resolver erros de migração. Não rode `flush` em um banco que contenha dados importantes.

As migrações iniciais estão incluídas em `ltv/migrations/0001_initial.py`. Em alterações futuras nos models, gere e versione novas migrações:

```cmd
python manage.py makemigrations ltv
python manage.py migrate
```

## 9. Estrutura do projeto

- `config/`: configurações Django, URLs, WSGI e ASGI.
- `ltv/models.py`: entidades e regras de persistência.
- `ltv/forms.py`: formulários e filtragem por usuário.
- `ltv/views.py`: fluxo HTTP e páginas.
- `ltv/analytics/`: cálculos de LTV, coortes, projeções e alertas.
- `ltv/services/`: importação e regras de aplicação.
- `ltv/automation/`: manutenção agendada e snapshots.
- `ltv/integrations/`: contrato-base para conectores futuros.
- `templates/`: interface Django.
- `static/css/`: identidade visual modular.
- `static/js/`: navegação e gráficos.
- `scripts/`: atalhos para CMD.
- `docs/BIBLIA_RECONSTRUCAO.md`: documentação técnica completa para reconstrução.

## 10. Integração futura com o ROI Manager / Skallora

O LTV Manager tem banco e models próprios. Ele não importa models internos do ROI Manager. Uma integração futura deve utilizar API versionada, contratos de dados, autenticação entre serviços, IDs externos e logs de sincronização. Não compartilhe diretamente o `db.sqlite3` dos dois sistemas.

## 11. Limitações conhecidas desta versão

- Não há conectores oficiais ativos para Magalu, Mercado Livre, Amazon ou Shopee.
- Não há coleta automática de pedidos nem autenticação OAuth de marketplace.
- A importação é CSV/XLSX, com prévia e confirmação manual.
- A projeção é exploratória e baseada em faixas mensais de idade; não é um modelo de sobrevivência ou previsão avançada.
- Não há ainda alertas configuráveis por e-mail, Telegram ou WhatsApp.
- A execução em segundo plano local depende de o Windows e o CMD permanecerem ativos.
- A biblioteca Chart.js e a fonte Inter são carregadas por CDN; para uso sem internet, deve-se adicionar cópias locais autorizadas e apontar os templates para esses arquivos.

## 12. Documentação técnica

Consulte `docs/BIBLIA_RECONSTRUCAO.md` para entender a arquitetura, os cálculos, as entidades, o front-end, os componentes CSS, os fluxos, os testes e as decisões de reconstrução.
