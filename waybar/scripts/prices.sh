#!/bin/bash

response=$(curl -s https://api.coinbase.com/v2/exchange-rates?currency=USDT)

btc_rate=$(echo "$response" | jq -r '.data.rates.BTC')
sol_rate=$(echo "$response" | jq -r '.data.rates.SOL')

btc_usd_rate=$(echo "scale=2; 1 / $btc_rate" | bc)
sol_usd_rate=$(echo "scale=2; 1 / $sol_rate" | bc)

echo '{"text": "BTC: $'$btc_usd_rate' | SOL: $'$sol_usd_rate'"}'
