#!/bin/bash

# Fix remaining specific no-misused-promises patterns

echo "Fixing remaining no-misused-promises patterns..."

# Fix service file patterns like setTimeout/setInterval with async callbacks
find src -name "*.ts" -not -path "*/node_modules/*" -exec sed -i 's/setTimeout(\([^,]*async[^,]*\),/setTimeout(() => void \1(), /g' {} \;
find src -name "*.ts" -not -path "*/node_modules/*" -exec sed -i 's/setInterval(\([^,]*async[^,]*\),/setInterval(() => void \1(), /g' {} \;

# Fix callback prop patterns that pass async functions directly
find src -name "*.tsx" -not -path "*/node_modules/*" -exec sed -i 's/onSave={\([a-zA-Z][a-zA-Z0-9]*\)}/onSave={(data) => void \1(data)}/g' {} \;
find src -name "*.tsx" -not -path "*/node_modules/*" -exec sed -i 's/onUpdate={\([a-zA-Z][a-zA-Z0-9]*\)}/onUpdate={(data) => void \1(data)}/g' {} \;
find src -name "*.tsx" -not -path "*/node_modules/*" -exec sed -i 's/onRefresh={\([a-zA-Z][a-zA-Z0-9]*\)}/onRefresh={() => void \1()}/g' {} \;
find src -name "*.tsx" -not -path "*/node_modules/*" -exec sed -i 's/onLoad={\([a-zA-Z][a-zA-Z0-9]*\)}/onLoad={() => void \1()}/g' {} \;

# Fix specific component prop patterns
find src -name "*.tsx" -not -path "*/node_modules/*" -exec sed -i 's/loadApiKeys={loadApiKeys}/loadApiKeys={() => void loadApiKeys()}/g' {} \;

echo "Fixed remaining patterns"