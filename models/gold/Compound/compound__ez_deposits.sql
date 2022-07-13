{{ config(
  materialized = 'incremental',
  unique_key = '_log_id',
  cluster_by = ['block_timestamp::DATE'],
  tags = ['compound']
) }}
-- pull all ctoken addresses and corresponding name
WITH asset_details AS (

  SELECT
    ctoken_address,
    ctoken_symbol,
    ctoken_name,
    ctoken_decimals,
    underlying_asset_address,
    ctoken_metadata,
    underlying_name,
    underlying_symbol,
    underlying_decimals,
    underlying_contract_metadata
  FROM
    {{ ref('compound__ez_asset_details') }}
),
comp_deposits AS (
  SELECT
    DISTINCT block_number,
    block_timestamp,
    contract_address AS ctoken,
    event_inputs :mintTokens AS mintTokens_raw,
    event_inputs :mintAmount AS mintAmount_raw,
    REGEXP_REPLACE(
      event_inputs :minter,
      '\"',
      ''
    ) AS supplier,
    tx_hash,
    _inserted_timestamp,
    _log_id
  FROM
    {{ ref('silver__logs') }}
  WHERE
    contract_address IN (
      SELECT
        ctoken_address
      FROM
        asset_details
    )
    AND event_name = 'Mint'

{% if is_incremental() %}
AND _inserted_timestamp >= (
  SELECT
    MAX(
      _inserted_timestamp
    ) :: DATE - 2
  FROM
    {{ this }}
)
{% endif %}
),
--pull hourly prices for each undelrying
prices AS (
  SELECT
    HOUR AS block_hour,
    token_address AS token_contract,
    ctoken_address,
    AVG(price) AS token_price
  FROM
    {{ ref('core__fact_hourly_token_prices') }}
    INNER JOIN asset_details
    ON token_address = underlying_asset_address
  WHERE
    HOUR :: DATE IN (
      SELECT
        block_timestamp :: DATE
      FROM
        comp_deposits
    )
  GROUP BY
    1,
    2,
    3
)
SELECT
  block_number,
  block_timestamp,
  ctoken,
  asset_details.ctoken_symbol AS ctoken_symbol,
  mintTokens_raw / pow(
    10,
    ctoken_decimals
  ) AS issued_ctokens,
  mintAmount_raw / pow(
    10,
    underlying_decimals
  ) AS supplied_base_asset,
  ROUND((mintAmount_raw * p.token_price) / pow(10, underlying_decimals), 2) AS supplied_base_asset_usd,
  CASE
    WHEN asset_details.underlying_asset_address = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' THEN NULL
    ELSE asset_details.underlying_asset_address
  END AS supplied_contract_addr,
  CASE
    WHEN asset_details.underlying_asset_address = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' THEN 'ETH'
    ELSE asset_details.underlying_symbol
  END AS supplied_symbol,
  supplier,
  tx_hash,
  _inserted_timestamp,
  _log_id
FROM
  comp_deposits
  LEFT JOIN prices p
  ON DATE_TRUNC(
    'hour',
    comp_deposits.block_timestamp
  ) = p.block_hour
  AND comp_deposits.ctoken = p.ctoken_address
  LEFT JOIN asset_details
  ON comp_deposits.ctoken = asset_details.ctoken_address
