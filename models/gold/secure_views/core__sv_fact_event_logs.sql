{{ config(
    materialized = 'view',
    secure = true
) }}

SELECT
    *
FROM
    {{ ref('core__fact_event_logs') }}
