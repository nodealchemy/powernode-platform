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

  // Regression: the hex-line strips matched ANY all-hex line, so a final/leading/inline
  // line that is an English word made only of a-f letters was deleted. Real chunk-size
  // markers contain digits; pure-letter words do not.
  it('preserves a trailing all-hex WORD line (no digits — not a chunk marker)', () => {
    expect(cleanStreamingContent('It lasted a\nDECADE')).toContain('DECADE');
    expect(cleanStreamingContent('Meet me at the\nCAFE')).toContain('CAFE');
  });

  it('preserves a leading all-hex WORD line', () => {
    expect(cleanStreamingContent('FACADE\nof the old building')).toContain('FACADE');
  });

  it('preserves an inline all-hex WORD line', () => {
    expect(cleanStreamingContent('first line\nBEEF\nlast line')).toContain('BEEF');
  });

  it('still strips hex chunk markers that contain digits (leading/trailing/inline)', () => {
    expect(cleanStreamingContent('The answer is here\n1a2f')).not.toContain('1a2f');
    expect(cleanStreamingContent('1a2f\nThe answer is here')).not.toContain('1a2f');
    expect(cleanStreamingContent('Hello world\n1a3\nGoodbye world')).not.toContain('1a3');
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
