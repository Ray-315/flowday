import { invoke, isTauri } from '@tauri-apps/api/core';
import { emptyWorkspace, parseWorkspace, type Workspace } from './workspace';

export const DEFAULT_ENDPOINT = 'https://flowday.mtrx.pro';
export type AccountUser = { id: string; email: string; displayName: string };
export type AuthSession = { token: string; user: AccountUser };
export type JsonObject = Record<string, unknown>;
export type ApiResponse = { status: number; body: string };
export type ApiTransport = (request: {
  baseUrl: string;
  path: string;
  method: string;
  token?: string;
  body?: string;
  signal: AbortSignal;
}) => Promise<ApiResponse>;
export class ApiException extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
    public currentVersion?: number,
  ) {
    super(message);
  }
}
export const object = (value: unknown): JsonObject => {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new ApiException(0, 'INVALID_RESPONSE', '服务器返回了无效数据');
  return value as JsonObject;
};
export const textField = (value: unknown): string => {
  if (typeof value !== 'string') throw new ApiException(0, 'INVALID_RESPONSE', '服务器返回了无效数据');
  return value;
};
export const versionField = (value: unknown): number => {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0)
    throw new ApiException(0, 'INVALID_RESPONSE', '服务器返回了无效版本');
  return value;
};
export const rows = (value: unknown): JsonObject[] => {
  if (!Array.isArray(value)) throw new ApiException(0, 'INVALID_RESPONSE', '服务器返回了无效列表');
  return value.map(object);
};
export function parseAccountUser(value: unknown): AccountUser {
  const user = object(value);
  return { id: textField(user.id), email: textField(user.email), displayName: textField(user.displayName) };
}
export function normalizeEndpoint(endpoint: string): string {
  const url = new URL(endpoint);
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if (
    (url.protocol !== 'https:' && !(url.protocol === 'http:' && loopback)) ||
    url.username ||
    url.password ||
    url.search ||
    url.hash
  )
    throw new Error('服务器地址必须使用 HTTPS（本机地址可使用 HTTP）');
  const path = url.pathname.replace(/\/+$/, '');
  url.pathname = path.endsWith('/api/v1') ? path : `${path}/api/v1`;
  return url.toString().replace(/\/$/, '');
}
const transport: ApiTransport = async ({ baseUrl, path, method, token, body, signal }) => {
  if (isTauri()) return invoke<ApiResponse>('http_request', { baseUrl, path, method, token, body });
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    body,
    signal,
    redirect: 'error',
    headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });
  return { status: response.status, body: await response.text() };
};
export class FlowApi {
  readonly baseUrl: string;
  constructor(
    endpoint = DEFAULT_ENDPOINT,
    private readonly send: ApiTransport = transport,
    private readonly timeoutMs = 20000,
  ) {
    this.baseUrl = normalizeEndpoint(endpoint);
  }
  async request(method: string, path: string, token?: string, data?: JsonObject): Promise<JsonObject> {
    if (!path.startsWith('/') || path.startsWith('//') || path.includes('..'))
      throw new Error('无效接口路径');
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    let response: ApiResponse;
    try {
      response = await Promise.race([
        this.send({
          baseUrl: this.baseUrl,
          path,
          method,
          token,
          body: data ? JSON.stringify(data) : undefined,
          signal: controller.signal,
        }),
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => {
            controller.abort();
            reject(new ApiException(0, 'TIMEOUT', '服务器响应超时，请重试'));
          }, path === '/ai/preview' ? Math.max(this.timeoutMs, 45000) : this.timeoutMs);
        }),
      ]);
    } catch (error) {
      if (error instanceof ApiException) throw error;
      throw new ApiException(0, 'NETWORK_ERROR', '无法连接服务器，请检查网络和服务器地址');
    } finally {
      clearTimeout(timer);
    }
    let decoded: JsonObject;
    try {
      decoded = response.body ? object(JSON.parse(response.body)) : {};
    } catch {
      throw new ApiException(response.status, 'INVALID_RESPONSE', '服务器返回了无效数据');
    }
    if (response.status < 200 || response.status >= 300) {
      const error = decoded.error && typeof decoded.error === 'object' ? object(decoded.error) : decoded;
      throw new ApiException(
        response.status,
        typeof error.code === 'string' ? error.code : 'HTTP_ERROR',
        '请求失败，请检查输入或重新尝试',
        typeof decoded.currentVersion === 'number' ? decoded.currentVersion : undefined,
      );
    }
    return decoded;
  }
  feature(token: string, method: string, path: string, data?: JsonObject) {
    return this.request(method, path, token, data);
  }
  async authenticate(mode: 'login' | 'register', data: JsonObject): Promise<AuthSession> {
    const result = await this.request('POST', `/auth/${mode}`, undefined, data);
    return {
      token: textField(result.token),
      user: parseAccountUser(result.user),
    };
  }
  login(email: string, password: string) {
    return this.authenticate('login', { email, password });
  }
  register(email: string, password: string, displayName: string, verificationCode: string) {
    return this.authenticate('register', { email, password, displayName, verificationCode });
  }
  sendRegistrationCode(email: string) {
    return this.request('POST', '/auth/registration-code', undefined, { email });
  }
  async me(token: string): Promise<AccountUser> {
    return parseAccountUser((await this.request('GET', '/auth/me', token)).user);
  }
  async getWorkspace(token: string) {
    const result = await this.request('GET', '/workspace', token);
    return {
      version: versionField(result.version),
      data: result.data == null ? emptyWorkspace() : parseWorkspace(JSON.stringify(result.data)),
    };
  }
  async putWorkspace(token: string, baseVersion: number, data: Workspace) {
    return versionField((await this.request('PUT', '/workspace', token, { baseVersion, data })).version);
  }
  async download(token: string, path: string): Promise<Blob> {
    if (!path.startsWith('/') || path.startsWith('//') || path.includes('..'))
      throw new Error('无效接口路径');
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const operation = async () => {
        if (isTauri()) {
          const bytes = await invoke<number[]>('http_download', { baseUrl: this.baseUrl, path, token });
          return new Blob([new Uint8Array(bytes)]);
        }
        const response = await fetch(`${this.baseUrl}${path}`, {
          signal: controller.signal,
          redirect: 'error',
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!response.ok) throw new ApiException(response.status, 'DOWNLOAD_FAILED', '文件下载失败');
        return response.blob();
      };
      return await Promise.race([
        operation(),
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => {
            controller.abort();
            reject(new ApiException(0, 'TIMEOUT', '服务器响应超时，请重试'));
          }, this.timeoutMs);
        }),
      ]);
    } catch (error) {
      if (error instanceof ApiException) throw error;
      throw new ApiException(0, 'DOWNLOAD_FAILED', '文件下载失败');
    } finally {
      clearTimeout(timer);
    }
  }
}
export type SyncBindings = {
  read: () => Workspace;
  replace: (data: Workspace) => Promise<void>;
  backup: () => Promise<void>;
  baseline?: { version: number; json: string };
  saveBaseline?: (version: number, json: string) => Promise<void>;
};
export class SyncController {
  baseVersion?: number;
  lastSyncedJson?: string;
  lastSync?: Date;
  conflict = false;
  error?: string;
  busy = false;
  unauthorized = false;
  private disposed = false;
  private listeners = new Set<() => void>();
  constructor(
    public readonly api: FlowApi,
    public readonly session: AuthSession,
    private bindings: SyncBindings,
  ) {
    this.baseVersion = bindings.baseline?.version;
    this.lastSyncedJson = bindings.baseline?.json;
  }
  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };
  get localDirty() {
    return JSON.stringify(this.bindings.read()) !== this.lastSyncedJson;
  }
  private notify() {
    this.listeners.forEach((listener) => listener());
  }
  private async run(operation: () => Promise<void>) {
    if (this.busy || this.disposed || this.unauthorized) return;
    this.busy = true;
    this.error = undefined;
    this.notify();
    try {
      await operation();
      if (
        !this.disposed &&
        !this.conflict &&
        this.baseVersion !== undefined &&
        this.lastSyncedJson !== undefined
      )
        await this.bindings.saveBaseline?.(this.baseVersion, this.lastSyncedJson);
    } catch (error) {
      if (error instanceof ApiException && error.status === 409) this.conflict = true;
      if (error instanceof ApiException && error.status === 401) this.unauthorized = true;
      this.error = this.unauthorized
        ? '登录已过期，请重新登录'
        : error instanceof Error
          ? error.message
          : '同步失败，数据已保留';
    } finally {
      this.busy = false;
      this.notify();
    }
  }
  private async replace(remote: { version: number; data: Workspace }, expected: string) {
    if (JSON.stringify(this.bindings.read()) !== expected) {
      this.conflict = true;
      return;
    }
    await this.bindings.backup();
    if (this.disposed) return;
    if (JSON.stringify(this.bindings.read()) !== expected) {
      this.conflict = true;
      return;
    }
    try {
      await this.bindings.replace(remote.data);
    } catch (error) {
      if (JSON.stringify(this.bindings.read()) !== expected) this.conflict = true;
      throw error;
    }
    if (this.disposed) return;
    this.baseVersion = remote.version;
    this.lastSyncedJson = JSON.stringify(remote.data);
    this.lastSync = new Date();
    this.conflict = false;
  }
  private async upload(version: number) {
    const sent = JSON.stringify(this.bindings.read());
    const next = await this.api.putWorkspace(this.session.token, version, JSON.parse(sent));
    if (this.disposed) return;
    this.baseVersion = next;
    this.lastSyncedJson = sent;
    this.lastSync = new Date();
    this.conflict = false;
  }
  sync = () =>
    this.run(async () => {
      if (this.conflict) return;
      const before = JSON.stringify(this.bindings.read());
      const remote = await this.api.getWorkspace(this.session.token);
      if (this.disposed) return;
      const remoteJson = JSON.stringify(remote.data);
      if (JSON.stringify(this.bindings.read()) === remoteJson) {
        this.baseVersion = remote.version;
        this.lastSyncedJson = remoteJson;
        this.lastSync = new Date();
        return;
      }
      if (this.baseVersion === undefined) {
        if (before === JSON.stringify(emptyWorkspace())) await this.replace(remote, before);
        else this.conflict = true;
      } else if (remote.version !== this.baseVersion) {
        if (this.localDirty) this.conflict = true;
        else await this.replace(remote, before);
      } else if (this.localDirty) await this.upload(remote.version);
    });
  resolveUseServer = () =>
    this.run(async () => {
      const before = JSON.stringify(this.bindings.read());
      const remote = await this.api.getWorkspace(this.session.token);
      if (!this.disposed) await this.replace(remote, before);
    });
  resolveUploadLocal = () =>
    this.run(async () => {
      await this.bindings.backup();
      const remote = await this.api.getWorkspace(this.session.token);
      if (!this.disposed) await this.upload(remote.version);
    });
  async remoteMutation(operation: (version: number) => Promise<unknown>) {
    if (this.busy || this.conflict || this.disposed || this.unauthorized)
      throw new Error(this.error ?? '请先完成同步或处理版本冲突');
    await this.sync();
    if (this.error || this.conflict || this.baseVersion === undefined || this.localDirty)
      throw new Error(this.error ?? '请先完成同步或处理版本冲突');
    await this.run(async () => {
      const before = JSON.stringify(this.bindings.read());
      await operation(this.baseVersion!);
      const remote = await this.api.getWorkspace(this.session.token);
      if (!this.disposed) await this.replace(remote, before);
    });
    if (this.error || this.conflict) throw new Error(this.error ?? '操作已提交，请处理同步冲突');
  }
  dispose() {
    this.disposed = true;
    this.listeners.clear();
  }
}
