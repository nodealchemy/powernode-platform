import { getUserInitials } from './userUtils';

describe('getUserInitials', () => {
  it("returns 'U' for null, undefined, empty, or missing name", () => {
    expect(getUserInitials(null)).toBe('U');
    expect(getUserInitials(undefined)).toBe('U');
    expect(getUserInitials({})).toBe('U');
    expect(getUserInitials({ name: '' })).toBe('U');
  });

  it("returns 'U' for a whitespace-only name instead of throwing", () => {
    expect(() => getUserInitials({ name: '   ' })).not.toThrow();
    expect(getUserInitials({ name: '   ' })).toBe('U');
  });

  it('returns a single initial for a one-word name', () => {
    expect(getUserInitials({ name: 'Madonna' })).toBe('M');
  });

  it('returns first + last initials for a multi-word name', () => {
    expect(getUserInitials({ name: 'John Doe' })).toBe('JD');
  });

  it('trims surrounding and collapses inner whitespace', () => {
    expect(getUserInitials({ name: '  John  ' })).toBe('J');
    expect(getUserInitials({ name: '  John   Doe  ' })).toBe('JD');
  });

  it('falls back to full_name when name is absent or whitespace-only', () => {
    expect(getUserInitials({ full_name: 'Jane Roe' })).toBe('JR');
    expect(getUserInitials({ name: '   ', full_name: 'Bob Smith' })).toBe('BS');
  });
});
