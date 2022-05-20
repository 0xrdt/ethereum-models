{{ config(
    materialized = 'view',
    persist_docs ={ "relation": true,
    "columns": true }
) }}

SELECT
    block_number,
    block_timestamp,
    tx_hash,
    'sale' AS event_type,
    platform_address,
    platform_name,
    nft_from_address AS seller_address,
    nft_to_address AS buyer_address,
    nft_address,
    project_name,
    erc1155_value,
    tokenId,
    token_metadata,
    currency_symbol,
    currency_address,
    price,
    price_usd,
    total_fees,
    platform_fee,
    creator_fee,
    total_fees_usd,
    platform_fee_usd,
    creator_fee_usd,
    tx_fee,
    tx_fee_usd,
    origin_from_address,
    origin_to_address,
    origin_function_signature
FROM
    {{ ref('silver_nft__opensea_sales') }}
UNION ALL
SELECT
    block_number,
    block_timestamp,
    tx_hash,
    'sale' AS event_type,
    platform_address,
    platform_name,
    nft_from_address AS seller_address,
    nft_to_address AS buyer_address,
    nft_address,
    project_name,
    erc1155_value,
    tokenId,
    token_metadata,
    currency_symbol,
    currency_address,
    price,
    price_usd,
    total_fees,
    platform_fee,
    creator_fee,
    total_fees_usd,
    platform_fee_usd,
    creator_fee_usd,
    tx_fee,
    tx_fee_usd,
    origin_from_address,
    origin_to_address,
    origin_function_signature
FROM
    {{ ref('silver_nft__looksrare_sales') }}
