import { cleanStreamingContent, cleanMessageContent, parseMentions } from './utils';

describe('cleanStreamingContent', () => {
  it('returns empty for falsy input', () => {
    expect(cleanStreamingContent('')).toBe('');
  });

  it('strips a leading hex chunk header', () => {
    expect(cleanStreamingContent('1a3\r\nHello world')).toBe('Hello world');
  });

  it('strips a trailing hex chunk marker', () => {
    expect(cleanStreamingContent('Hello world\r\n1a3')).toBe('Hello world');
  });

  it('collapses an inline hex chunk marker to a single newline', () => {
    expect(cleanStreamingContent('Hello\r\n1a3\r\nworld')).toBe('Hello\nworld');
  });

  it("strips the final '0' chunk terminator (incl. after punctuation)", () => {
    expect(cleanStreamingContent('Hello\r\n0')).toBe('Hello');
    expect(cleanStreamingContent('Done.\r\n0')).toBe('Done.');
  });

  it('returns empty when the content is only zeros', () => {
    expect(cleanStreamingContent('0')).toBe('');
  });

  it('does NOT touch hex characters inside normal words', () => {
    expect(cleanStreamingContent('Code cafe')).toBe('Code cafe');
    expect(cleanStreamingContent('deadbeef face')).toBe('deadbeef face');
  });
});

describe('cleanMessageContent (role gating)', () => {
  it('applies chunk stripping for assistant/ai roles', () => {
    expect(cleanMessageContent('Hello\r\n1a3', 'assistant')).toBe('Hello');
    expect(cleanMessageContent('Hello\r\n1a3', 'ai')).toBe('Hello');
  });

  it('does NOT strip chunk markers for user/system roles (markdown sanitize only)', () => {
    expect(cleanMessageContent('Hello\r\n1a3', 'user')).toBe('Hello\r\n1a3');
  });

  it('returns empty for falsy content', () => {
    expect(cleanMessageContent('', 'assistant')).toBe('');
  });
});

describe('parseMentions', () => {
  it('returns a single text part when no mention names are provided', () => {
    expect(parseMentions('hello there')).toEqual([{ type: 'text', value: 'hello there' }]);
    expect(parseMentions('hello there', [])).toEqual([{ type: 'text', value: 'hello there' }]);
  });

  it('returns an empty text part for empty input', () => {
    expect(parseMentions('', ['Bob'])).toEqual([{ type: 'text', value: '' }]);
  });

  it('splits text and mention parts', () => {
    expect(parseMentions('hello @Bob bye', ['Bob'])).toEqual([
      { type: 'text', value: 'hello ' },
      { type: 'mention', value: '@Bob' },
      { type: 'text', value: ' bye' },
    ]);
  });

  it('handles a mention at the start', () => {
    expect(parseMentions('@Bob hi', ['Bob'])).toEqual([
      { type: 'mention', value: '@Bob' },
      { type: 'text', value: ' hi' },
    ]);
  });

  it('prefers the longest match (Claude Code over Claude)', () => {
    expect(parseMentions('@Claude Code rocks', ['Claude', 'Claude Code'])).toEqual([
      { type: 'mention', value: '@Claude Code' },
      { type: 'text', value: ' rocks' },
    ]);
  });

  it('escapes regex metacharacters in mention names', () => {
    expect(parseMentions('hey @C++ Bot!', ['C++ Bot'])).toEqual([
      { type: 'text', value: 'hey ' },
      { type: 'mention', value: '@C++ Bot' },
      { type: 'text', value: '!' },
    ]);
  });
});
