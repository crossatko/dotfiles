#!/bin/bash

# Fetch exchange rates from Coinbase API
response=$(curl -s https://api.coinbase.com/v2/exchange-rates?currency=USDT)

# Extract BTC and SOL rates from JSON response
btc_rate=$(echo "$response" | jq -r '.data.rates.BTC')
ltc_rate=$(echo "$response" | jq -r '.data.rates.LTC')
sol_rate=$(echo "$response" | jq -r '.data.rates.SOL')
shib_rate=$(echo "$response" | jq -r '.data.rates.SHIB')

# Calculate the BTC/USD and SOL/USD prices and round them to two decimal places
btc_usd_rate=$(echo "scale=2; 1 / $btc_rate" | bc)
ltc_usd_rate=$(echo "scale=2; 1 / $ltc_rate" | bc)
sol_usd_rate=$(echo "scale=2; 1 / $sol_rate" | bc)
shib_usd_rate=$(echo "scale=8; 1 / $shib_rate" | bc)

# Echo the BTC and SOL prices in Waybar style JSON format
echo '{"text": "BTC: '$btc_usd_rate' USD   |   SOL: '$sol_usd_rate' USD   |   LTC: '$ltc_usd_rate' USD   |   SHIB: '$shib_usd_rate' USD"}'
