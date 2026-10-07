import { invoke, isTauri } from '@tauri-apps/api/core';
import { emptyWorkspace, parseWorkspace, type Workspace } from './workspace';

type Cache = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;
type Disk = { read: (scope: string) => Promise<string | null>; write: (scope: string, source: string) => Promise<void>; backup?: (scope:string)=>Promise<void> };
export const trialStorageKey = 'flowday.react-trial.workspace.v1';

export class WorkspaceStorage {
  private queue: Promise<void> = Promise.resolve();
  private memory = new Map<string,string>();
  constructor(private cache: Cache, private disk?: Disk) {}
  key(scope: string) { return scope === 'guest' ? trialStorageKey : `flowday.workspace.${scope}`; }
  private get(key:string) { return this.memory.get(key)??this.cache.getItem(key); }
  private put(key:string,source:string) {
    try {this.cache.setItem(key,source);this.memory.delete(key);}
    catch(failure) {if(!this.disk)throw failure;this.memory.set(key,source);this.cache.removeItem(key);}
  }
  raw(scope: string) { return this.get(this.key(scope)); }
  async load(scope: string): Promise<Workspace> {
    const pending = this.get(`flowday.workspace.${scope}.pending`);
    const saved = this.disk ? await this.disk.read(scope) : null;
    const source = pending ?? saved ?? this.raw(scope);
    if(source)this.memory.set(this.key(scope),source);
    const data = source ? parseWorkspace(source) : emptyWorkspace();
    if (source && this.disk && (pending || !saved)) this.save(scope, data);
    else if (saved) this.put(this.key(scope), saved);
    return data;
  }
  save(scope: string, data: Workspace) {
    const source = JSON.stringify(data);
    parseWorkspace(source);
    this.put(this.key(scope), source);
    if (!this.disk) return;
    const journal = `flowday.workspace.${scope}.pending`;
    this.put(journal, source);
    this.queue = this.queue.catch(() => {}).then(async () => {
      await this.disk!.write(scope, source);
      if (this.get(journal) === source) { this.cache.removeItem(journal);this.memory.delete(journal); }
    });
    // The journal remains until the native write has completed; callers surface flush errors.
    void this.queue.catch(() => {});
  }
  flush() { return this.queue; }
  protect(scope: string) {
    const source = this.raw(scope);
    if (source) this.put(`${this.key(scope)}.before-import`, source);
    if(source&&this.disk?.backup) {this.queue=this.queue.catch(()=>{}).then(()=>this.disk!.backup!(scope));void this.queue.catch(()=>{});}
  }
}

export async function persistRemote(store:WorkspaceStorage,scope:string,next:Workspace,read:()=>Workspace,replace:(value:Workspace)=>void,active:()=>boolean){
  if(!active())throw new Error('账号已切换');
  const expected=JSON.stringify(read());
  store.save(scope,next);
  await store.flush();
  if(!active())throw new Error('账号已切换');
  if(JSON.stringify(read())!==expected)throw new Error('本地数据已修改，请处理同步冲突');
  replace(next);
}

export const workspaceStorage = new WorkspaceStorage({
  getItem: key => window.localStorage.getItem(key),
  setItem: (key, value) => window.localStorage.setItem(key, value),
  removeItem: key => window.localStorage.removeItem(key),
}, isTauri() ? {
  read: scope => invoke<string | null>('workspace_read', { scope }),
  write: (scope, source) => invoke<void>('workspace_write', { scope, source }),
  backup: scope => invoke<void>('workspace_backup', {scope}),
} : undefined);
export let initialWorkspace: Workspace | null = null;
export let initialStorageError = '';
export async function initializeStorage() {
  try { initialWorkspace = await workspaceStorage.load('guest'); }
  catch { initialStorageError = '无法读取本地数据，请先导出原始数据或从备份恢复。'; }
}
// Only this preference is stored in WebView storage, never the session token.
export const loginPreferences = {
  read: () => {
    try { return localStorage.getItem('flowday.remember-login.v1') !== 'false'; }
    catch { return false; }
  },
  write: (remember: boolean) => localStorage.setItem('flowday.remember-login.v1', String(remember)),
};
export const credentialVault = {
  read: (key: string) => isTauri() ? invoke<string | null>('credential_read', { key }) : Promise.resolve(null),
  write: (key: string, value: string) => isTauri() ? invoke<void>('credential_write', { key, value }) : Promise.resolve(),
  delete: (key: string) => isTauri() ? invoke<void>('credential_delete', { key }) : Promise.resolve(),
};
export async function readSyncBaseline(scope:string):Promise<{version:number;json:string}|undefined>{
  const source=isTauri()?await invoke<string|null>('sync_baseline_read',{scope}):localStorage.getItem(`${workspaceStorage.key(scope)}.baseline`);
  if(!source)return;
  try{const value=JSON.parse(source);if(!Number.isSafeInteger(value.version)||value.version<0||typeof value.json!=='string')return;parseWorkspace(value.json);return value;}catch{return;}
}
export async function saveSyncBaseline(scope:string,version:number,json:string){
  const source=JSON.stringify({version,json});
  if(isTauri())await invoke('sync_baseline_write',{scope,source});
  else localStorage.setItem(`${workspaceStorage.key(scope)}.baseline`,source);
}
