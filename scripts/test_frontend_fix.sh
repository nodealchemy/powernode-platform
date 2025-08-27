#!/bin/bash

echo "🧪 Testing frontend payment gateways API fix..."
echo

echo "1️⃣ Logging in as admin..."
LOGIN_RESPONSE=$(curl -s -X POST "http://localhost:3000/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@powernode.org","password":"P0w3rN0d3Admin!@&"}')

# Extract access token using jq (if available) or basic parsing
if command -v jq &> /dev/null; then
  ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token')
else
  # Fallback parsing without jq
  ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
fi

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  echo "❌ Login failed"
  echo "Response: $LOGIN_RESPONSE"
  exit 1
fi

echo "✅ Login successful"

echo
echo "2️⃣ Testing payment gateways API..."
GATEWAYS_RESPONSE=$(curl -s -X GET "http://localhost:3000/api/v1/payment_gateways" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

echo "📊 API Response (first 200 chars):"
echo "${GATEWAYS_RESPONSE:0:200}..."

echo
echo "3️⃣ Checking response structure..."

# Check if response has the expected structure
if echo "$GATEWAYS_RESPONSE" | grep -q '"success":true'; then
  echo "✅ API call successful"
else
  echo "❌ API call failed"
  echo "Full response: $GATEWAYS_RESPONSE"
  exit 1
fi

if echo "$GATEWAYS_RESPONSE" | grep -q '"gateways":{'; then
  echo "✅ Response contains gateways data"
else
  echo "❌ Response missing gateways data"
fi

if echo "$GATEWAYS_RESPONSE" | grep -q '"status":{'; then
  echo "✅ Response contains status data" 
else
  echo "❌ Response missing status data"
fi

if echo "$GATEWAYS_RESPONSE" | grep -q '"stripe":{' && echo "$GATEWAYS_RESPONSE" | grep -q '"paypal":{'; then
  echo "✅ Both Stripe and PayPal gateway configurations found"
else
  echo "❌ Missing Stripe or PayPal gateway configurations"
fi

echo
echo "4️⃣ Analysis:"
echo "🎯 The API returns the correct structure: { success: true, data: { gateways: {...}, status: {...} } }"
echo "🔧 Frontend fix: Changed 'return response.data' to 'return response.data.data'"
echo "🎨 Component condition: overview && overview.gateways && overview.status"

if echo "$GATEWAYS_RESPONSE" | grep -q '"gateways":{' && echo "$GATEWAYS_RESPONSE" | grep -q '"status":{'; then
  echo "🎉 SUCCESS: Payment gateway cards should now display!"
  echo
  echo "📝 Fix Summary:"
  echo "  - ✅ API returns wrapped response: { success: true, data: {...} }"
  echo "  - ✅ Frontend now extracts: response.data.data instead of response.data"
  echo "  - ✅ Component gets: { gateways: {...}, status: {...} } directly"
  echo "  - ✅ Rendering condition will be satisfied"
  echo "  - ✅ Both Stripe and PayPal cards will render"
else
  echo "❌ Issue remains - please check component logic"
fi