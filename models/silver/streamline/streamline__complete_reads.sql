{{ config (
    materialized = "incremental",
    unique_key = "id",
    cluster_by = "function_signature"
) }}

WITH meta AS (

    SELECT
        registered_on,
        file_name
    FROM
        TABLE(
            information_schema.external_table_files(
                table_name => '{{ source( "bronze_streamline", "reads") }}'
            )
        ) A

{% if is_incremental() %}
WHERE
    registered_on >= (
        SELECT
            COALESCE(MAX(_INSERTED_TIMESTAMP), '1970-01-01' :: DATE) max_INSERTED_TIMESTAMP
        FROM
            {{ this }})
    ),
    partitions AS (
        SELECT
            DISTINCT SPLIT_PART(SPLIT_PART(file_name, '/', 6), '_', 0) AS partition_by_function_signature
        FROM
            meta
    ),
    max_date AS (
        SELECT
            COALESCE(MAX(_INSERTED_TIMESTAMP), '1970-01-01' :: DATE) max_INSERTED_TIMESTAMP
        FROM
            {{ this }})
        {% else %}
    )
{% endif %}
SELECT
    {{ dbt_utils.surrogate_key(
        ['contract_address', 'function_signature', 'call_name', 'function_input', 'block_number']
    ) }} AS id,
    contract_address,
    function_signature,
    call_name,
    function_input,
    block_number,
    registered_on AS _inserted_timestamp
FROM
    {{ source(
        "bronze_streamline",
        "reads"
    ) }} AS s
    JOIN meta b
    ON b.file_name = metadata$filename

{% if is_incremental() %}
JOIN partitions p
ON p.partition_by_function_signature = s._PARTITION_BY_FUNCTION_SIGNATURE 
{% endif %}

qualify(ROW_NUMBER() over (PARTITION BY id
ORDER BY
    _inserted_timestamp DESC)) = 1
