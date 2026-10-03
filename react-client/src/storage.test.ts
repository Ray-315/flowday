import { describe, expect, it } from 'vitest';
import { WorkspaceStorage, persistRemote } from './storage';
import { emptyWorkspace } from './workspace';

function cache() {
  const entries = new Map<string, string>();
  return { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value); }, removeItem: (key: string) => { entries.delete(key); } };
}
describe('durable workspace storage', () => {
  it('allows the first remote sync for an account with no local file to protect',async()=>{
    const store=new WorkspaceStorage(cache(),{read:async()=>null,write:async()=>{},backup:async()=>{throw new Error('missing file');}});
    await store.load('new-account');store.protect('new-account');await expect(store.flush()).resolves.toBeUndefined();
  });
  it('saves native workspaces when the browser cache quota is exhausted',async()=>{
    const limited={...cache(),setItem:()=>{throw new DOMException('quota','QuotaExceededError');}};
    let disk:string|null=null;
    const store=new WorkspaceStorage(limited,{read:async()=>disk,write:async(_scope,source)=>{disk=source;}});
    const data={...emptyWorkspace(),preferences:{themeMode:'dark'}};
    store.save('guest',data);await store.flush();
    expect(JSON.parse(disk!).preferences.themeMode).toBe('dark');
    expect((await new WorkspaceStorage(limited,{read:async()=>disk,write:async()=>{}}).load('guest')).preferences.themeMode).toBe('dark');
    expect(()=>new WorkspaceStorage(limited).save('guest',data)).toThrow();
  });
  it('keeps guest and account caches separate', async () => {
    const store = new WorkspaceStorage(cache());
    const guest = { ...emptyWorkspace(), preferences: { themeMode: 'dark' } };
    store.save('guest', guest);
    expect((await store.load('account:user')).preferences).toEqual({});
    expect((await store.load('guest')).preferences.themeMode).toBe('dark');
  });
  it('migrates trial data without removing its original copy', async () => {
    const memory = cache();
    const source = JSON.stringify({ ...emptyWorkspace(), preferences: { themeMode: 'dark' } });
    memory.setItem('flowday.react-trial.workspace.v1', source);
    let file: string | null = null;
    const store = new WorkspaceStorage(memory, { read: async () => file, write: async (_scope, value) => { file = value; } });
    expect((await store.load('guest')).preferences.themeMode).toBe('dark');
    await store.flush();
    expect(file).toBe(source);
    expect(memory.getItem('flowday.react-trial.workspace.v1')).toBe(source);
  });
  it('serializes writes and retains the recovery journal after a disk error', async () => {
    const memory = cache();
    const store = new WorkspaceStorage(memory, { read: async () => null, write: async () => { throw new Error('disk full'); } });
    store.save('guest', emptyWorkspace());
    await expect(store.flush()).rejects.toThrow('disk full');
    expect(memory.getItem('flowday.workspace.guest.pending')).not.toBeNull();
    expect((await store.load('guest')).schemaVersion).toBe(1);
  });
  it('does not replace a corrupted disk file with an empty workspace', async () => {
    const store = new WorkspaceStorage(cache(), { read: async () => '{bad', write: async () => {} });
    await expect(store.load('guest')).rejects.toThrow();
    expect(store.raw('guest')).toBe('{bad');
  });
  it('preserves edits made while a remote replacement is being flushed',async()=>{
    let release!:()=>void;
    const store=new WorkspaceStorage(cache(),{read:async()=>null,write:async()=>new Promise<void>(resolve=>{release=resolve;})});
    let current=emptyWorkspace();
    const remote={...emptyWorkspace(),preferences:{themeMode:'dark'}};
    const replacing=persistRemote(store,'guest',remote,()=>current,value=>{current=value;},()=>true);
    await Promise.resolve();await Promise.resolve();
    current={...emptyWorkspace(),preferences:{themeMode:'light'}};
    release();
    await expect(replacing).rejects.toThrow('本地数据已修改');
    expect(current.preferences.themeMode).toBe('light');
  });
});
