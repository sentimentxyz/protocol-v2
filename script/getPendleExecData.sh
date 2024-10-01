#!/bin/bash

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <receiverAddr> <amountTokenIn>"
  exit 1
fi
# echo $1 $2

receiverAddr=$1
amountTokenIn=$2
# echo $receiverAddr $amountTokenIn

url="https://api-v2.pendle.finance/sdk/api/v1/swapExactTokenForPt?chainId=42161&receiverAddr=$receiverAddr&marketAddr=0x2Dfaf9a5E4F293BceedE49f2dBa29aACDD88E0C4&tokenInAddr=0xaf88d065e77c8cC2239327C5EDb3A432268e5831&syTokenInAddr=0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34&amountTokenIn=$amountTokenIn&slippage=0.004"
# echo $url

response=$(curl -s -X 'GET' "$url" -H 'accept: application/json')
# echo $response

exec_data=$(echo "$response" | jq -r '.transaction.data')
# echo "$exec_data"

if [ "$transaction_data" == "null" ]; then
  echo "Error: Unable to fetch transaction data"
  exit 1
fi

echo "$exec_data"
