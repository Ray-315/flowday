import { useEffect, useState } from 'react';
import type { SyncController } from './api';
import type { Workspace } from './workspace';

export function CloudSync({ sync, workspace, onSave, onSignIn }: {
  sync: SyncController; workspace: Workspace; onSave: (next: Workspace) => boolean; onSignIn: () => void;
}) {
  const [, redraw] = useState(0);
  useEffect(() => sync.subscribe(() => redraw(value => value + 1)), [sync]);
  return <section className="service-panel" aria-label="云同步">
          {sync && (
            <>
              <p className="section-description">通过 FlowDay 账号同步工作区。开启自动同步后，应用运行期间每 30 秒同步一次。</p>
              {workspace && onSave && (
                <label className="service-choice">
                  <input
                    type="checkbox"
                    checked={workspace.preferences.autoSync === true}
                    onChange={(event) =>
                      onSave({
                        ...workspace,
                        preferences: { ...workspace.preferences, autoSync: event.target.checked },
                      })
                    }
                  />
                  自动同步
                </label>
              )}
              <div className="service-actions">
                <button disabled={sync.busy} onClick={() => void sync.sync()}>
                  立即同步
                </button>
                {sync.lastSync && <span>{sync.lastSync.toLocaleString()}</span>}
              </div>
              {sync.conflict && (
                <div className="service-actions">
                  <button
                    disabled={sync.busy}
                    onClick={() => {
                      if (window.confirm('先备份本地修改，再使用服务器数据？')) void sync.resolveUseServer();
                    }}
                  >
                    使用服务器数据
                  </button>
                  <button
                    disabled={sync.busy}
                    onClick={() => {
                      if (window.confirm('先备份，再用本地数据替换当前服务器版本？'))
                        void sync.resolveUploadLocal();
                    }}
                  >
                    上传本地数据
                  </button>
                </div>
              )}
              {sync.error && <p role="alert">{sync.error}</p>}
              {sync.unauthorized && (
                <button disabled={sync.busy} onClick={onSignIn}>
                  重新登录
                </button>
              )}
            </>
          )}
      </section>;
}
