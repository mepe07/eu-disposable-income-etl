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
YAML config ───┘                                                                              │
                                                                                              ▼
                                                                                           KNIME
                                                                                        (transform)
                                                                                              │
                                                                                     ┌────────┴────────┐
                                                                                     ▼                 ▼
                                                                                  Grafana          Telegram
                                                                               (dashboards)         (alertas)
```

**Ferramentas:**
- **Node-RED** — extração, publicação e subscrição via AMQP
- **RabbitMQ** — broker de mensagens (exchange Direct `isi.etl`, 5 queues)
- **PostgreSQL 16** — armazenamento dos dados extraídos
- **KNIME** — transformação e cálculo do rendimento discricionário
- **Grafana** — visualização de dashboards
- **Docker** — orquestração de PostgreSQL, RabbitMQ e Grafana
- **PowerShell** — trigger automático do KNIME via NodePIT Batch Executor

---

## Fontes de dados

| Fonte | Dataset | Descrição |
|---|---|---|
| Eurostat | `earn_nt_net` | Salários médios líquidos anuais |
| Eurostat | `prc_hicp_midx` | Inflação HICP mensal (freq=M) |
| Eurostat | `ilc_lvho07a` | Custo de habitação (% rendimento) |
| Eurostat | `prc_ppp_ind` | Paridades de poder de compra |
| World Bank | `NY.GDP.PCAP.CD` | PIB per capita (USD) |
| Frankfurter API | — | Taxas de câmbio USD→EUR (média anual) |
| `config.yaml` | — | Lista de países e parâmetros do pipeline |

Os dados originais nunca são apagados — novas extrações usam `ON CONFLICT DO UPDATE`.

---

## Países monitorizados

Portugal, Alemanha, França, Espanha, Itália, Países Baixos, Polónia, Áustria, Bélgica, Suécia, Finlândia, República Checa, Hungria.

---

## Estrutura do projeto

```
eu-disposable-income-etl/
├── docker/
│   └── docker-compose.yml       # PostgreSQL, RabbitMQ, Grafana
├── knime/
│   └── disposable-income-transform/   # Workflow KNIME
├── exports/
│   ├── knime_trigger.txt        # Ficheiro de trigger (criado pelo Node-RED)
│   ├── knime_batch.log          # Log de execuções KNIME
│   └── etl.log                  # Log do pipeline Node-RED
├── scripts/
│   └── knime_batch.ps1          # Script PowerShell de trigger automático
├── schema.sql                   # Schema da base de dados
└── config.yaml                  # Configuração do pipeline (países, thresholds, fontes)
```

O Node-RED é gerido internamente (flows em `~/.node-red/`).

---

## Base de dados

| Tabela | Origem | Descrição |
|---|---|---|
| `net_earnings` | Eurostat | Salários líquidos anuais por país |
| `inflation_hicp` | Eurostat | Índice HICP mensal |
| `housing_cost` | Eurostat | % rendimento gasto em habitação |
| `purchasing_power_parity` | Eurostat | Índice PPP relativo à média EU27 |
| `gdp_per_capita` | World Bank | PIB per capita em EUR |
| `exchange_rates` | Frankfurter | Taxa de câmbio USD→EUR média anual |
| `disposable_income` | KNIME | Rendimento discricionário calculado |

---

## Como executar

### Pré-requisitos

- Docker Desktop
- Node-RED (`npm install -g node-red`)
- KNIME 5.12 LTS com NodePIT Batch Executor instalado
- Node-RED packages: `node-red-contrib-amqp`, `node-red-node-postgresql`

### 1. Levantar os serviços

```bash
cd docker
docker-compose up -d
```

- RabbitMQ Management: http://localhost:15672 (isi/isi)
- Grafana: http://localhost:3000 (admin/admin)
- PostgreSQL: localhost:5432 (isi/isi, db: disposable_income)

### 2. Criar o schema

```bash
psql -U isi -d disposable_income -f schema.sql
```

### 3. Iniciar o Node-RED

```bash
node-red
```

Aceder em http://localhost:1880. O flow de configuração (`config`) lê o `config.yaml` e carrega os países no contexto global. Os publishers disparam automaticamente 0.1s após o deploy.

### 4. Iniciar o trigger do KNIME

```powershell
powershell -ExecutionPolicy Bypass -File scripts\knime_batch.ps1
```

O script fica em loop a cada 10 segundos à espera do ficheiro `exports\knime_trigger.txt`. Quando o Node-RED termina a extração, cria esse ficheiro e o KNIME executa automaticamente.

---

## Alertas Telegram

Após cada extração, o pipeline compara Portugal com a média europeia em 3 métricas (salário líquido, custo de habitação, PPP). Se Portugal estiver abaixo da média, é enviada uma notificação via Telegram Bot.

---

## Expressões regulares utilizadas

O pipeline usa regex na extração e validação de dados:
- Validação de formato de datas `YYYY-MM` na série HICP mensal
- Extração de campos de resposta JSON da API Eurostat
- Parsing do ficheiro YAML de configuração

---

## Limitações conhecidas

- O GDP per capita (World Bank) tem cobertura incompleta para alguns anos recentes.
- O PPP da Eurostat (`prc_ppp_ind`) pode apresentar inconsistências para anos mais recentes ainda não revistos.
- O KNIME Desktop Community Edition não suporta batch mode nativo (exit code 5); contornado via NodePIT Batch Executor.