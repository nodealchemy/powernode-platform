import { downloadJson } from './downloadJson';

describe('downloadJson', () => {
  let createObjectURL: jest.Mock;
  let revokeObjectURL: jest.Mock;
  let clickSpy: jest.SpyInstance;

  beforeEach(() => {
    createObjectURL = jest.fn().mockReturnValue('blob:mock-url');
    revokeObjectURL = jest.fn();
    (URL as unknown as { createObjectURL: jest.Mock }).createObjectURL = createObjectURL;
    (URL as unknown as { revokeObjectURL: jest.Mock }).revokeObjectURL = revokeObjectURL;
    clickSpy = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
  });

  afterEach(() => {
    clickSpy.mockRestore();
  });

  it('creates a Blob URL from the JSON payload and clicks a download link for it', () => {
    downloadJson({ foo: 'bar' }, 'conversation-1.json');

    expect(createObjectURL).toHaveBeenCalledTimes(1);
    const blob = createObjectURL.mock.calls[0][0] as Blob;
    expect(blob.type).toBe('application/json');

    expect(clickSpy).toHaveBeenCalledTimes(1);
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:mock-url');
  });
});
