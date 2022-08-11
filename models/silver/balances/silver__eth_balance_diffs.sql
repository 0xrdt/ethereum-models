{{ config(
    materialized = 'incremental',
    unique_key = 'id',
    cluster_by = ['block_timestamp::date'],
    tags = ['balances','diffs'],
    merge_update_columns = ["id"],
    post_hook = "ALTER TABLE {{ this }} ADD SEARCH OPTIMIZATION"
) }}

WITH base_table AS (

    SELECT
        block_number,
        block_timestamp,
        address,
        balance,
        _inserted_timestamp
    FROM
        {{ ref('silver__eth_balances') }}

{% if is_incremental() %}
WHERE
    _inserted_timestamp >= (
        SELECT
            MAX(
                _inserted_timestamp
            )
        FROM
            {{ this }}
    )
{% endif %}
)

{% if is_incremental() %},
last_record AS (
    SELECT
        A.block_number,
        A.block_timestamp,
        A.address,
        A.current_bal_unadj AS balance,
        A._inserted_timestamp
    FROM
        {{ this }} A
        INNER JOIN base_table b
        ON A.block_number >= b.block_number
        AND A.address = b.address
),
all_records AS (
    SELECT
        block_number,
        block_timestamp,
        address,
        balance,
        _inserted_timestamp
    FROM
        base_table
    UNION ALL
    SELECT
        block_number,
        block_timestamp,
        address,
        balance,
        _inserted_timestamp
    FROM
        last_record
),
incremental AS (
    SELECT
        block_number,
        block_timestamp,
        address,
        balance,
        _inserted_timestamp
    FROM
        all_records qualify(ROW_NUMBER() over (PARTITION BY address, block_number
    ORDER BY
        _inserted_timestamp DESC)) = 1
)
{% endif %},
FINAL AS (
    SELECT
        block_number,
        block_timestamp,
        address,
        COALESCE(LAG(balance) ignore nulls over(PARTITION BY address
    ORDER BY
        block_number ASC), 0) AS prev_bal_unadj,
        balance AS current_bal_unadj,
        _inserted_timestamp,
        {{ dbt_utils.surrogate_key(
            ['block_number', 'address']
        ) }} AS id

{% if is_incremental() %}
FROM
    incremental
{% else %}
FROM
    base_table
{% endif %}
)
SELECT
    *
FROM
    FINAL
WHERE
    prev_bal_unadj <> current_bal_unadj
