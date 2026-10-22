# eu-disposable-income-etl

Pipeline ETL para monitorização da evolução do poder de compra na União Europeia.  
Projeto académico — ISI 2026/27, IPCA.

---

## Problema

Analisar como o rendimento discricionário (salário líquido menos habitação e despesas essenciais) evoluiu entre 2015 e 2025 em 13 países da UE, e comparar a posição de Portugal face à média europeia.

---

## Arquitetura

```
Eurostat API ──┐
World Bank API ─┤
Frankfurter API ┤──▶ Node-RED (publishers) ──▶ RabbitMQ ──▶ Node-RED (subscribers) ──▶ PostgreSQL
config.yaml ───┘                                                        │                    │
                                                                        │                    ▼
                                                              knime_trigger.txt ──▶ KNIME (transform)
                                                              (PowerShell watch)         │
                                                                                 ┌────────┴────────┐
                                                                                 ▼                 ▼
                                                                              Grafana          Telegram
                                                                           (11 dashboards)    (alertas PT)
```

**Ferramentas:**
- **Node-RED** — extração, publicação (publishers) e subscrição (subscribers) via AMQP; tab `knime_trigger` gera o ficheiro de trigger após todas as extrações
- **RabbitMQ** — broker de mensagens com exchange Direct `isi.etl` e 6 filas (uma por fonte de dados)
- **PostgreSQL 16** — armazenamento dos dados extraídos; upserts idempotentes via `ON CONFLICT DO UPDATE`
- **KNIME** — transformação e cálculo do rendimento discricionário; arranca em batch via NodePIT Batch Executor
- **Grafana** — 11 painéis de visualização com datasource PostgreSQL
- **Docker** — orquestração de PostgreSQL, RabbitMQ e Grafana via `docker-compose`
- **PowerShell** — script `knime_batch.ps1` em loop que deteta o ficheiro de trigger e arranca o KNIME automaticamente

---

## Fontes de dados

| Fonte | Dataset | Descrição |
|---|---|---|
| Eurostat | `earn_nt_net` | Salários médios líquidos anuais |
| Eurostat | `prc_hicp_midx` | Inflação HICP mensal (`&freq=M`, base 2015=100) |
| Eurostat | `ilc_lvho07a` | Taxa de sobrecarga com habitação (% rendimento) |
| Eurostat | `prc_ppp_ind` | Paridades de poder de compra (índice EU27=100) |
| World Bank | `NY.GDP.PCAP.CD` | PIB per capita (USD) |
| Frankfurter API | — | Taxas de câmbio USD→EUR (média anual por par) |
| `config.yaml` | — | Lista de países, códigos ISO e parâmetros do pipeline |

Os dados originais nunca são apagados — novas extrações usam `ON CONFLICT DO UPDATE`.

---

## Países monitorizados

13 países da UE: Portugal (PT), Alemanha (DE), França (FR), Espanha (ES), Itália (IT), Países Baixos (NL), Polónia (PL), Áustria (AT), Bélgica (BE), Suécia (SE), Finlândia (FI), República Checa (CZ), Hungria (HU).

---

## Estrutura do projeto

```
eu-disposable-income-etl/
├── docker/
│   └── docker-compose.yml            # PostgreSQL 16, RabbitMQ 3, Grafana
├── knime/
│   └── disposable-income-transform/  # Workflow KNIME (calcular rendimento discricionário)
├── exports/
│   ├── knime_trigger.txt             # Criado pelo Node-RED para desencadear o KNIME
│   ├── knime_batch.log               # Log de execuções batch do KNIME
│   └── etl.log                       # Log do pipeline Node-RED
├── scripts/
│   └── knime_batch.ps1               # Loop PowerShell que deteta o trigger e executa o KNIME
├── schema.sql                        # DDL das 7 tabelas PostgreSQL
└── config.yaml                       # Países, thresholds e parâmetros de extração
```

O Node-RED é gerido internamente (flows em `~/.node-red/`). O flow está organizado em 9 tabs:
`config` · `pub_net_earnings` · `pub_inflation_hicp` · `pub_housing_cost` · `pub_purchasing_power_parity` · `pub_gdp_per_capita` · `pub_exchange_rates` · `subscribers` · `knime_trigger` · `telegram_alert`

---

## Base de dados

| Tabela | Origem | Registos (aprox.) | Descrição |
|---|---|---|---|
| `net_earnings` | Eurostat | ~143 | Salários líquidos anuais por país |
| `inflation_hicp` | Eurostat | ~1716 | Índice HICP mensal (ano + mês) |
| `housing_cost` | Eurostat | ~142 | % do rendimento gasto em habitação |
| `purchasing_power_parity` | Eurostat | ~143 | Índice PPP relativo à média EU27 |
| `gdp_per_capita` | World Bank | ~130 | PIB per capita em USD |
| `exchange_rates` | Frankfurter | ~10 | Taxa de câmbio USD→EUR média anual |
| `disposable_income` | KNIME | ~129 | Rendimento discricionário calculado + classificação LOW/MEDIUM/HIGH |

Query de verificação rápida:

```sql
SELECT 'net_earnings'           AS tabela, COUNT(*) AS registos FROM net_earnings
UNION ALL SELECT 'inflation_hicp',          COUNT(*) FROM inflation_hicp
UNION ALL SELECT 'housing_cost',            COUNT(*) FROM housing_cost
UNION ALL SELECT 'purchasing_power_parity', COUNT(*) FROM purchasing_power_parity
UNION ALL SELECT 'gdp_per_capita',          COUNT(*) FROM gdp_per_capita
UNION ALL SELECT 'exchange_rates',          COUNT(*) FROM exchange_rates
UNION ALL SELECT 'disposable_income',       COUNT(*) FROM disposable_income
ORDER BY tabela;
```

---

## Como executar

### Pré-requisitos

- Docker Desktop
- Node-RED (`npm install -g node-red`) com packages:
  - `node-red-contrib-amqp`
  - `node-red-node-postgresql`
- KNIME 5.x LTS com **NodePIT Batch Executor** instalado
- PowerShell 5.1+ (incluído no Windows 10/11)

### 1. Levantar os serviços

```bash
cd docker
docker-compose up -d
```

| Serviço | URL | Credenciais |
|---|---|---|
| RabbitMQ Management | http://localhost:15672 | isi / isi |
| Grafana | http://localhost:3000 | admin / admin |
| PostgreSQL | localhost:5432 | isi / isi · db: disposable_income |

### 2. Criar o schema

```bash
psql -U isi -d disposable_income -f schema.sql
```

### 3. Importar o dashboard Grafana

Em Grafana → **Dashboards → Import → Upload JSON file**, importar `grafana_dashboard.json`.  
Mapear o datasource para a ligação PostgreSQL configurada (`host.docker.internal:5432`).

### 4. Iniciar o Node-RED

```bash
node-red
```

Aceder em http://localhost:1880. O flow `config` lê o `config.yaml` e carrega os países no contexto global. Os publishers disparam automaticamente 0,1 s após o deploy.

### 5. Iniciar o trigger do KNIME

```powershell
powershell -ExecutionPolicy Bypass -File scripts\knime_batch.ps1
```

O script fica em loop a cada 10 segundos à espera de `exports\knime_trigger.txt`. Quando o Node-RED termina todas as extrações, cria esse ficheiro; o script deteta-o, apaga-o e executa o KNIME em batch mode com NodePIT Batch Executor. O resultado é escrito em `exports\knime_batch.log`.

---

## Alertas Telegram

Após cada extração completa, o flow `telegram_alert` compara Portugal com a média europeia em 3 métricas:

| Métrica | Tabela | Condição de alerta |
|---|---|---|
| Salário líquido | `net_earnings` | PT < média EU |
| % habitação | `housing_cost` | PT > média EU |
| Índice PPP | `purchasing_power_parity` | PT < média EU |

Se alguma condição se verificar, é enviada uma mensagem via Telegram Bot com os desvios em percentagem. O flow usa um nó de debounce (10 s) para evitar mensagens duplicadas quando múltiplos subscribers terminam em simultâneo.

---

## Mecanismo de trigger KNIME

O trigger entre o Node-RED e o KNIME é feito por ficheiro:

1. O último subscriber (sub_exchange_rates) envia uma mensagem via **link out** para a tab `knime_trigger`
2. Um nó **trigger** com debounce de 10 s aguarda que não cheguem mais mensagens
3. Um nó **file** escreve `exports\knime_trigger.txt`
4. O `knime_batch.ps1` deteta o ficheiro, apaga-o e executa:

```
knime.exe -application com.nodepit.batch.application.NodePitBatchExecutor
          --reset --no-save "<caminho para o workflow>"
```

---

## Expressões regulares utilizadas

- Validação de formato de datas `YYYY-MM` na série HICP mensal
- Extração de campos da resposta JSON da API Eurostat (índices de dimensão `geo` e `time`)
- Parsing do ficheiro YAML de configuração (`config.yaml`)

---

