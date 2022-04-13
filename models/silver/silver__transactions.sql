{{ config(
    materialized = 'incremental',
    unique_key = "tx_hash",
    cluster_by = ['ingested_at::DATE']
) }}

WITH base_table AS (

    SELECT
        record_id,
        tx_id,
        tx_block_index,
        offset_id,
        block_id,
        block_timestamp,
        network,
        chain_id,
        tx,
        ingested_at
    FROM
        {{ ref('bronze__transactions') }}

{% if is_incremental() %}
WHERE
    ingested_at >= (
        SELECT
            MAX(
                ingested_at
            )
        FROM
            {{ this }}
    )
{% endif %}
),
block_hashes AS (
    SELECT
        block_number,
        HASH
    FROM
        {{ ref('silver__blocks') }}
),
remove_uncles AS (
    SELECT
        *
    FROM
        base_table
        INNER JOIN block_hashes
        ON block_hashes.block_number = COALESCE(
            tx :block_number :: INTEGER,
            tx :blockNumber :: INTEGER
        )
        AND block_hashes.hash = COALESCE(
            tx :block_hash :: STRING,
            tx :blockHash :: STRING
        )
),
FINAL AS (
    SELECT
        block_timestamp,
        COALESCE(
            tx :block_number :: INTEGER,
            tx :blockNumber :: INTEGER
        ) AS block_number,
        tx_id :: STRING AS tx_hash,
        silver.js_hex_to_int(
            tx :nonce :: STRING
        ) AS nonce,
        tx_block_index AS POSITION,
        tx :from :: STRING AS from_address,
        tx :to :: STRING AS to_address,
        tx :value / pow(
            10,
            18
        ) AS eth_value,
        COALESCE(
            tx :block_hash :: STRING,
            tx :blockHash :: STRING
        ) AS block_hash,
        COALESCE(
            tx :gas_price / pow(
                10,
                9
            ),
            tx :gasPrice / pow(
                10,
                9
            )
        ) AS gas_price,
        tx :gas :: INTEGER AS gas_limit,
        tx :input :: STRING AS DATA,
        CASE
            WHEN tx :receipt :status :: STRING = '0x1' THEN 'SUCCESS'
            ELSE 'FAIL'
        END AS status,
        silver.js_hex_to_int(
            tx :receipt :gasUsed :: STRING
        ) AS gas_used,
        silver.js_hex_to_int(
            tx :receipt :cumulativeGasUsed :: STRING
        ) AS cumulative_Gas_Used,
        silver.js_hex_to_int(
            tx :receipt :effectiveGasPrice :: STRING
        ) AS effective_Gas_Price,
        (
            gas_price * silver.js_hex_to_int(
                tx :receipt :gasUsed :: STRING
            )
        ) / pow(
            10,
            9
        ) AS tx_fee,
        ingested_at :: TIMESTAMP AS ingested_at,
        OBJECT_DELETE(
            tx,
            'traces'
        ) AS tx_json
    FROM
        remove_uncles
)
SELECT
    block_timestamp,
    block_number,
    tx_hash,
    nonce,
    POSITION,
    from_address,
    to_address,
    eth_value,
    block_hash,
    gas_price,
    gas_limit,
    DATA,
    status,
    gas_used,
    cumulative_Gas_Used,
    effective_Gas_Price,
    tx_fee,
    ingested_at,
    tx_json
FROM
    FINAL qualify(ROW_NUMBER() over(PARTITION BY tx_hash
ORDER BY
    ingested_at DESC)) = 1
