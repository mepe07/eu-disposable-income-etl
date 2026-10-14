-- ============================================================
-- ISI 2026/27 — Evolução do Poder de Compra na União Europeia
-- Schema da base de dados
-- ============================================================

-- Países monitorizados
CREATE TABLE IF NOT EXISTS countries (
    code        CHAR(2)      PRIMARY KEY,  -- ISO 3166-1 alpha-2 (ex: PT, DE, FR)
    name        VARCHAR(100) NOT NULL
);

INSERT INTO countries (code, name) VALUES
    ('PT', 'Portugal'),
    ('DE', 'Germany'),
    ('FR', 'France'),
    ('ES', 'Spain'),
    ('IT', 'Italy'),
    ('NL', 'Netherlands'),
    ('PL', 'Poland')
ON CONFLICT (code) DO NOTHING;

-- Salários médios líquidos anuais (Eurostat: earn_nt_net)
CREATE TABLE IF NOT EXISTS net_earnings (
    id              SERIAL PRIMARY KEY,
    country_code    CHAR(2)        NOT NULL REFERENCES countries(code),
    year            SMALLINT       NOT NULL,
    annual_net_eur  NUMERIC(10,2),
    extracted_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    UNIQUE (country_code, year)
);

-- Inflação HICP mensal (Eurostat: prc_hicp_midx)
CREATE TABLE IF NOT EXISTS inflation_hicp (
    id              SERIAL PRIMARY KEY,
    country_code    CHAR(2)        NOT NULL REFERENCES countries(code),
    year            SMALLINT       NOT NULL,
    month           SMALLINT       NOT NULL CHECK (month BETWEEN 1 AND 12),
    index_value     NUMERIC(8,2),
    extracted_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    UNIQUE (country_code, year, month)
);

-- Custo de habitação como % do rendimento (Eurostat: ilc_lvho07a)
CREATE TABLE IF NOT EXISTS housing_cost (
    id              SERIAL PRIMARY KEY,
    country_code    CHAR(2)        NOT NULL REFERENCES countries(code),
    year            SMALLINT       NOT NULL,
    housing_pct     NUMERIC(5,2),  -- percentagem do rendimento gasto em habitação
    extracted_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    UNIQUE (country_code, year)
);

-- Paridades de poder de compra (Eurostat: prc_ppp_ind)
CREATE TABLE IF NOT EXISTS purchasing_power_parity (
    id              SERIAL PRIMARY KEY,
    country_code    CHAR(2)        NOT NULL REFERENCES countries(code),
    year            SMALLINT       NOT NULL,
    ppp_index       NUMERIC(8,3),  -- índice relativo à média EU27
    extracted_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    UNIQUE (country_code, year)
);

-- Rendimento discricionário calculado (produzido pelo KNIME)
CREATE TABLE IF NOT EXISTS disposable_income (
    id                      SERIAL PRIMARY KEY,
    country_code            CHAR(2)        NOT NULL REFERENCES countries(code),
    year                    SMALLINT       NOT NULL,
    month                   SMALLINT       CHECK (month BETWEEN 1 AND 12),
    net_earnings_eur        NUMERIC(10,2),
    housing_cost_eur        NUMERIC(10,2),
    estimated_food_eur      NUMERIC(10,2),
    estimated_transport_eur NUMERIC(10,2),
    disposable_income_eur   NUMERIC(10,2), -- calculado pelo KNIME
    ppp_adjusted            NUMERIC(10,2), -- ajustado por paridade de poder de compra
    calculated_at           TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    UNIQUE (country_code, year, month)
);

-- Log de execuções do pipeline
CREATE TABLE IF NOT EXISTS pipeline_log (
    id              SERIAL PRIMARY KEY,
    run_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    source          VARCHAR(50),   -- ex: 'eurostat_earnings', 'eurostat_hicp'
    status          VARCHAR(20)    NOT NULL CHECK (status IN ('success', 'error', 'warning')),
    records_loaded  INTEGER,
    message         TEXT
);

-- ============================================================
-- Views úteis para o Grafana
-- ============================================================

-- Evolução do rendimento discricionário por país
CREATE OR REPLACE VIEW vw_disposable_income_trend AS
SELECT
    d.country_code,
    c.name AS country_name,
    d.year,
    d.month,
    d.disposable_income_eur,
    d.ppp_adjusted,
    d.net_earnings_eur,
    d.housing_cost_eur
FROM disposable_income d
JOIN countries c ON c.code = d.country_code
ORDER BY d.country_code, d.year, d.month;

-- Última inflação disponível por país
CREATE OR REPLACE VIEW vw_latest_inflation AS
SELECT DISTINCT ON (country_code)
    h.country_code,
    c.name AS country_name,
    h.year,
    h.month,
    h.index_value
FROM inflation_hicp h
JOIN countries c ON c.code = h.country_code
ORDER BY country_code, year DESC, month DESC;

-- Comparação atual entre países
CREATE OR REPLACE VIEW vw_country_comparison AS
SELECT
    c.code,
    c.name,
    ne.annual_net_eur,
    hc.housing_pct,
    ppp.ppp_index,
    ne.year AS earnings_year
FROM countries c
LEFT JOIN LATERAL (
    SELECT annual_net_eur, year FROM net_earnings
    WHERE country_code = c.code ORDER BY year DESC LIMIT 1
) ne ON true
LEFT JOIN LATERAL (
    SELECT housing_pct FROM housing_cost
    WHERE country_code = c.code ORDER BY year DESC LIMIT 1
) hc ON true
LEFT JOIN LATERAL (
    SELECT ppp_index FROM purchasing_power_parity
    WHERE country_code = c.code ORDER BY year DESC LIMIT 1
) ppp ON true;
