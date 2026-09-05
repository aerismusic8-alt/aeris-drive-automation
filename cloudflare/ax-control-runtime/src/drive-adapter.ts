export type DriveFile = {
  id: string;
  name: string;
};

export type DriveResult =
  | { ok: true; files: DriveFile[] }
  | { ok: false; error: string };

type DriveListResponse = { files?: Array<{ id?: unknown; name?: unknown }> };
type FetchImpl = typeof fetch;

const DRIVE_FILES_URL = 'https://www.googleapis.com/drive/v3/files';

export class DriveAdapter {
  constructor(
    private readonly accessToken: string,
    private readonly fetchImpl: FetchImpl = fetch,
  ) {}

  async list(query = ''): Promise<DriveResult> {
    if (!this.accessToken) {
      return { ok: false, error: 'GOOGLE_DRIVE_CREDENTIAL_MISSING' };
    }

    const params = new URLSearchParams({ pageSize: '100', fields: 'files(id,name)' });
    if (query) params.set('q', `name contains '${query.replace(/'/g, "\\'")}' and trashed = false`);

    try {
      const response = await this.fetchImpl(`${DRIVE_FILES_URL}?${params.toString()}`, {
        method: 'GET',
        headers: { Authorization: `Bearer ${this.accessToken}` },
      });
      if (!response.ok) return { ok: false, error: `GOOGLE_DRIVE_HTTP_${response.status}` };

      const data = await response.json() as DriveListResponse;
      const files = (data.files ?? [])
        .filter(file => typeof file.id === 'string' && typeof file.name === 'string')
        .map(file => ({ id: file.id as string, name: file.name as string }));
      return { ok: true, files };
    } catch {
      return { ok: false, error: 'GOOGLE_DRIVE_NETWORK_ERROR' };
    }
  }
}
