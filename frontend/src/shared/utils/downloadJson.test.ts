import { downloadJson } from './downloadJson';

// jsdom's Blob has no .text()/.arrayBuffer(); FileReader is the one thing it
// actually implements for reading Blob content back out.
function readBlobAsText(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = reject;
    reader.readAsText(blob);
  });
}

describe('downloadJson', () => {
  const originalCreateObjectURL = URL.createObjectURL;
  const originalRevokeObjectURL = URL.revokeObjectURL;
  let createObjectURL: jest.Mock;
  let revokeObjectURL: jest.Mock;
  let clickSpy: jest.SpyInstance;

  beforeEach(() => {
    jest.useFakeTimers();
    createObjectURL = jest.fn().mockReturnValue('blob:mock-url');
    revokeObjectURL = jest.fn();
    URL.createObjectURL = createObjectURL;
    URL.revokeObjectURL = revokeObjectURL;
    clickSpy = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
  });

  afterEach(() => {
    clickSpy.mockRestore();
    URL.createObjectURL = originalCreateObjectURL;
    URL.revokeObjectURL = originalRevokeObjectURL;
    jest.useRealTimers();
  });

  it('downloads the exact filename and the exact JSON payload, and defers revoking the object URL', async () => {
    downloadJson({ foo: 'bar' }, 'conversation-1.json');

    expect(createObjectURL).toHaveBeenCalledTimes(1);
    const blob = createObjectURL.mock.calls[0][0] as Blob;
    expect(blob.type).toBe('application/json');
    await expect(readBlobAsText(blob)).resolves.toBe(JSON.stringify({ foo: 'bar' }, null, 2));

    expect(clickSpy).toHaveBeenCalledTimes(1);
    const link = clickSpy.mock.contexts[0] as HTMLAnchorElement;
    expect(link.download).toBe('conversation-1.json');

    // Revoking must NOT happen synchronously with click() — doing so can
    // race the browser's own click-triggered download and cancel it.
    expect(revokeObjectURL).not.toHaveBeenCalled();
    jest.runAllTimers();
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:mock-url');
  });
});
