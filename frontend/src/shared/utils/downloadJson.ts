/**
 * Triggers a client-side download of a JSON payload as a file, by creating a
 * Blob URL and clicking a throwaway <a download> element.
 *
 * Several conversation-export call sites used to open a `download_url` the
 * server never returns (it returns the export payload inline instead) — this
 * is the shared replacement for `window.open(response.download_url, ...)`.
 */
export function downloadJson(payload: unknown, filename: string): void {
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  // Deferred: revoking the object URL synchronously can race the browser's
  // own click-triggered download and cancel it before the download starts.
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
