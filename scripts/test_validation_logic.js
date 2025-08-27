#!/usr/bin/env node

// Test the validation logic to understand the issue
console.log('🔍 Testing Stripe validation logic...\n');

// Simulate the validation function from useForm
function validateField(value, rules) {
  console.log(`🧪 Testing value: "${value}"`);
  console.log(`📋 Rules:`, {
    required: rules.required,
    hasCustom: !!rules.custom
  });

  // Required validation (from useForm hook)
  if (rules.required && (value === undefined || value === null || value === '')) {
    console.log('❌ Required validation failed');
    return 'publishable_key is required';
  }

  // Skip other validations if value is empty and not required
  if (!value && !rules.required) {
    console.log('✅ Empty value, not required - validation passed');
    return null;
  }

  // Custom validation
  if (rules.custom) {
    const customError = rules.custom(value);
    if (customError) {
      console.log('❌ Custom validation failed:', customError);
      return customError;
    }
    console.log('✅ Custom validation passed');
  }

  console.log('✅ All validation passed');
  return null;
}

// Simulate the validation rules from GatewayConfigModal
const publishableKeyRules = {
  required: true,
  custom: (value) => {
    if (!value) return null; // Required validation is handled separately
    if (!/^pk_(test_|live_)[a-zA-Z0-9_]{20,}$/.test(value)) {
      return 'Publishable key must start with pk_test_ or pk_live_ followed by at least 20 characters';
    }
    return null;
  }
};

console.log('📝 Test Cases:\n');

// Test Case 1: Empty value
console.log('1️⃣ Empty value:');
const result1 = validateField('', publishableKeyRules);
console.log(`   Result: ${result1 || 'null'}\n`);

// Test Case 2: Valid publishable key
console.log('2️⃣ Valid publishable key:');
const result2 = validateField('pk_test_51HqJJ2SdqwBTp5JxeQvl8o1y2', publishableKeyRules);
console.log(`   Result: ${result2 || 'null'}\n`);

// Test Case 3: Invalid publishable key
console.log('3️⃣ Invalid publishable key:');
const result3 = validateField('pk_test_123', publishableKeyRules);
console.log(`   Result: ${result3 || 'null'}\n`);

// Test Case 4: Undefined value
console.log('4️⃣ Undefined value:');
const result4 = validateField(undefined, publishableKeyRules);
console.log(`   Result: ${result4 || 'null'}\n`);

// Test Case 5: Whitespace value
console.log('5️⃣ Whitespace value:');
const result5 = validateField('   ', publishableKeyRules);
console.log(`   Result: ${result5 || 'null'}\n`);

console.log('🔍 Analysis:');
console.log('- Empty string should show "required" error');
console.log('- Valid key should show no error');
console.log('- Invalid key should show format error');
console.log('- The issue might be in form state management or timing');