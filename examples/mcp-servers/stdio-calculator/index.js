#!/usr/bin/env node
/**
 * MCP Calculator Server
 *
 * A simple example MCP server that provides basic arithmetic operations.
 * Demonstrates stdio connection type and tool implementation patterns.
 *
 * Connection Type: stdio
 * Tools: add, subtract, multiply, divide, power, sqrt, calculate
 *
 * Usage:
 *   node index.js
 *
 * Or register in Powernode as an MCP server with:
 *   connection_type: stdio
 *   command: node
 *   args: ["/path/to/examples/mcp-servers/stdio-calculator/index.js"]
 */

const { McpBaseServer } = require('../shared/mcp-base');

// Create server instance
const server = new McpBaseServer({
  name: 'calculator-server',
  version: '1.0.0',
  description: 'A simple calculator MCP server providing arithmetic operations'
});

// Register tools
server.registerTool({
  name: 'add',
  description: 'Add two numbers together',
  inputSchema: {
    type: 'object',
    properties: {
      a: { type: 'number', description: 'First number' },
      b: { type: 'number', description: 'Second number' }
    },
    required: ['a', 'b']
  },
  outputSchema: {
    type: 'object',
    properties: {
      result: { type: 'number', description: 'Sum of a and b' }
    }
  },
  handler: ({ a, b }) => {
    const result = a + b;
    return { result, expression: `${a} + ${b} = ${result}` };
  }
});

server.registerTool({
  name: 'subtract',
  description: 'Subtract the second number from the first',
  inputSchema: {
    type: 'object',
    properties: {
      a: { type: 'number', description: 'Number to subtract from' },
      b: { type: 'number', description: 'Number to subtract' }
    },
    required: ['a', 'b']
  },
  handler: ({ a, b }) => {
    const result = a - b;
    return { result, expression: `${a} - ${b} = ${result}` };
  }
});

server.registerTool({
  name: 'multiply',
  description: 'Multiply two numbers',
  inputSchema: {
    type: 'object',
    properties: {
      a: { type: 'number', description: 'First number' },
      b: { type: 'number', description: 'Second number' }
    },
    required: ['a', 'b']
  },
  handler: ({ a, b }) => {
    const result = a * b;
    return { result, expression: `${a} × ${b} = ${result}` };
  }
});

server.registerTool({
  name: 'divide',
  description: 'Divide the first number by the second',
  inputSchema: {
    type: 'object',
    properties: {
      a: { type: 'number', description: 'Dividend (number to divide)' },
      b: { type: 'number', description: 'Divisor (number to divide by)' }
    },
    required: ['a', 'b']
  },
  handler: ({ a, b }) => {
    if (b === 0) {
      throw new Error('Division by zero is not allowed');
    }
    const result = a / b;
    return { result, expression: `${a} ÷ ${b} = ${result}` };
  }
});

server.registerTool({
  name: 'power',
  description: 'Raise a number to a power (exponentiation)',
  inputSchema: {
    type: 'object',
    properties: {
      base: { type: 'number', description: 'Base number' },
      exponent: { type: 'number', description: 'Exponent' }
    },
    required: ['base', 'exponent']
  },
  handler: ({ base, exponent }) => {
    const result = Math.pow(base, exponent);
    return { result, expression: `${base}^${exponent} = ${result}` };
  }
});

server.registerTool({
  name: 'sqrt',
  description: 'Calculate the square root of a number',
  inputSchema: {
    type: 'object',
    properties: {
      number: { type: 'number', description: 'Number to find square root of' }
    },
    required: ['number']
  },
  handler: ({ number }) => {
    if (number < 0) {
      throw new Error('Cannot calculate square root of a negative number');
    }
    const result = Math.sqrt(number);
    return { result, expression: `√${number} = ${result}` };
  }
});

server.registerTool({
  name: 'modulo',
  description: 'Calculate the remainder of division (modulo operation)',
  inputSchema: {
    type: 'object',
    properties: {
      a: { type: 'number', description: 'Dividend' },
      b: { type: 'number', description: 'Divisor' }
    },
    required: ['a', 'b']
  },
  handler: ({ a, b }) => {
    if (b === 0) {
      throw new Error('Modulo by zero is not allowed');
    }
    const result = a % b;
    return { result, expression: `${a} mod ${b} = ${result}` };
  }
});

server.registerTool({
  name: 'calculate',
  description: 'Evaluate a mathematical expression (supports +, -, *, /, ^, sqrt, parentheses)',
  inputSchema: {
    type: 'object',
    properties: {
      expression: {
        type: 'string',
        description: 'Mathematical expression to evaluate (e.g., "2 + 3 * 4")'
      }
    },
    required: ['expression']
  },
  permissionLevel: 'account', // Requires account-level permission due to eval-like behavior
  handler: ({ expression }) => {
    // Safe expression evaluation (no eval, only math operations)
    const sanitized = expression
      .replace(/\s+/g, '')
      .replace(/sqrt\(([^)]+)\)/g, 'Math.sqrt($1)')
      .replace(/\^/g, '**');

    // Validate expression contains only allowed characters
    if (!/^[\d+\-*/().Math,sqrt\s]+$/.test(sanitized)) {
      throw new Error('Invalid characters in expression. Only numbers and basic operators allowed.');
    }

    try {
      // Use Function constructor for safer evaluation than eval
      const result = new Function(`return ${sanitized}`)();

      if (!Number.isFinite(result)) {
        throw new Error('Result is not a finite number');
      }

      return {
        result,
        expression: `${expression} = ${result}`,
        sanitized
      };
    } catch (error) {
      throw new Error(`Invalid expression: ${error.message}`);
    }
  }
});

// Register some informational resources
server.registerResource({
  uri: 'calculator://help',
  name: 'Calculator Help',
  description: 'Help documentation for the calculator',
  mimeType: 'text/plain'
});

// Start the server
server.startStdio();
