import {
  getInvoiceStatusColor,
  getInvoiceStatusText,
  getCustomerStatusColor,
  getSubscriptionStatusColor,
  getSubscriptionStatusText,
  getPaymentStatusColor,
  getPaymentStatusText,
  getStatusColor,
  getStatusText,
  getStatusBorderClass,
} from './statusHelpers';

describe('per-domain status colors', () => {
  it('maps invoice statuses, falling back to gray', () => {
    expect(getInvoiceStatusColor('paid')).toBe('green');
    expect(getInvoiceStatusColor('overdue')).toBe('red');
    expect(getInvoiceStatusColor('draft')).toBe('gray');
    expect(getInvoiceStatusColor('nonsense')).toBe('gray');
  });

  it('maps customer statuses', () => {
    expect(getCustomerStatusColor('active')).toBe('green');
    expect(getCustomerStatusColor('cancelled')).toBe('red');
    expect(getCustomerStatusColor('nonsense')).toBe('gray');
  });

  it('maps subscription statuses incl. underscore + orange', () => {
    expect(getSubscriptionStatusColor('past_due')).toBe('yellow');
    expect(getSubscriptionStatusColor('incomplete')).toBe('orange');
    expect(getSubscriptionStatusColor('nonsense')).toBe('gray');
  });

  it('maps payment statuses incl. requires_action', () => {
    expect(getPaymentStatusColor('succeeded')).toBe('green');
    expect(getPaymentStatusColor('failed')).toBe('red');
    expect(getPaymentStatusColor('requires_action')).toBe('orange');
    expect(getPaymentStatusColor('nonsense')).toBe('gray');
  });
});

describe('per-domain status text (capitalize fallback)', () => {
  it('returns mapped text or capitalizes unknown', () => {
    expect(getInvoiceStatusText('paid')).toBe('Paid');
    expect(getInvoiceStatusText('unknown_thing')).toBe('Unknown thing'); // capitalize: first upper, _ -> space
    expect(getSubscriptionStatusText('past_due')).toBe('Past Due');
    expect(getSubscriptionStatusText('trialing')).toBe('Trial');
    expect(getPaymentStatusText('requires_payment_method')).toBe('Payment Method Required');
  });
});

describe('getStatusColor', () => {
  it('uses the requested domain', () => {
    expect(getStatusColor('paid', 'invoice')).toBe('green');
    expect(getStatusColor('failed', 'payment')).toBe('red');
    expect(getStatusColor('trialing', 'subscription')).toBe('blue');
  });

  it('falls through invoice->customer->subscription->payment when no domain given (precedence)', () => {
    // 'pending' is customer:blue and payment:yellow — customer wins by precedence
    expect(getStatusColor('pending')).toBe('blue');
    // 'succeeded' only exists in payment
    expect(getStatusColor('succeeded')).toBe('green');
    // 'paused' only exists in subscription
    expect(getStatusColor('paused')).toBe('yellow');
  });

  it('returns gray for an unknown status with no domain', () => {
    expect(getStatusColor('totally-unknown')).toBe('gray');
  });
});

describe('getStatusText', () => {
  it('uses the requested domain', () => {
    expect(getStatusText('paid', 'invoice')).toBe('Paid');
    expect(getStatusText('requires_action', 'payment')).toBe('Requires Action');
  });

  it('falls through maps and capitalizes truly-unknown statuses', () => {
    expect(getStatusText('pending')).toBe('Pending'); // customer map
    expect(getStatusText('totally_unknown_status')).toBe('Totally unknown status');
  });
});

describe('getStatusBorderClass', () => {
  it('maps every StatusColor to a border class', () => {
    expect(getStatusBorderClass('green')).toBe('border-theme-success-border/30');
    expect(getStatusBorderClass('yellow')).toBe('border-theme-warning-border/30');
    expect(getStatusBorderClass('red')).toBe('border-theme-danger-border/30');
    expect(getStatusBorderClass('blue')).toBe('border-theme-info-border/30');
    expect(getStatusBorderClass('gray')).toBe('border-theme');
    expect(getStatusBorderClass('purple')).toBe('border-theme-info-border/30');
    expect(getStatusBorderClass('orange')).toBe('border-theme-warning-border/30');
  });
});
