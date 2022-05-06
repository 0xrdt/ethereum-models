{{ config(
    materialized = 'incremental',
    persist_docs ={ "relation": true,
    "columns": true },
    unique_key = '_log_id',
    cluster_by = ['block_timestamp::DATE']
) }}

WITH metadata AS (

    SELECT
        LOWER(address) AS address,
        symbol,
        NAME,
        decimals
    FROM
        {{ ref('core__dim_contracts') }}
    WHERE
        decimals IS NOT NULL
),
transfers AS (
    SELECT
        block_number,
        block_timestamp,
        tx_hash,
        LOWER(contract_address) AS contract_address,
        from_address,
        to_address,
        raw_amount,
        _log_id,
        ingested_at
    FROM
        {{ ref('silver__transfers') }}

{% if is_incremental() %}
WHERE
    ingested_at >= (
        SELECT
            MAX(
                ingested_at
            ) :: DATE - 2
        FROM
            {{ this }}
    )
{% endif %}
),
hourly_prices AS (
    SELECT
        HOUR,
        LOWER(token_address) AS token_address,
        AVG(price) AS price
    FROM
        {{ ref('core__fact_hourly_token_prices') }}
    WHERE
        1 = 1

{% if is_incremental() %}
AND HOUR :: DATE IN (
    SELECT
        DISTINCT block_timestamp :: DATE
    FROM
        transfers
)
{% else %}
    AND HOUR :: DATE >= '2020-05-05'
{% endif %}
GROUP BY
    HOUR,
    token_address
)
SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    from_address,
    to_address,
    raw_amount,
    decimals,
    symbol,
    price AS token_price,
    CASE
        WHEN decimals IS NOT NULL THEN raw_amount / pow(
            10,
            decimals
        )
        ELSE NULL
    END AS amount,
    CASE
        WHEN decimals IS NOT NULL
        AND price IS NOT NULL THEN amount * price
        ELSE NULL
    END AS amount_usd,
    CASE
        WHEN decimals IS NULL THEN 'false'
        ELSE 'true'
    END AS has_decimal,
    CASE
        WHEN price IS NULL THEN 'false'
        ELSE 'true'
    END AS has_price,
    _log_id,
    ingested_at
FROM
    transfers
    LEFT JOIN metadata
    ON contract_address = address
    LEFT JOIN hourly_prices
    ON contract_address = token_address
    AND DATE_TRUNC(
        'hour',
        block_timestamp
    ) = HOUR
