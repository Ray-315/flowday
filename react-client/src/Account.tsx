import { useEffect, useState, type FormEvent } from 'react';
import { ApiException, FlowApi, object, rows, textField, type AuthSession, type SyncController } from './api';
import './services.css';
import type { Workspace } from './workspace';
import { loginPreferences } from './storage';
import { ToolsDialog } from './Tools';
import { EnvelopeIcon } from '@phosphor-icons/react/dist/csr/Envelope';
import { LockSimpleIcon } from '@phosphor-icons/react/dist/csr/LockSimple';
import { UserIcon } from '@phosphor-icons/react/dist/csr/User';
import { EyeIcon } from '@phosphor-icons/react/dist/csr/Eye';
import { EyeSlashIcon } from '@phosphor-icons/react/dist/csr/EyeSlash';

export type AccountProps = {
  api: FlowApi;
  session: AuthSession | null;
  onSession: (session: AuthSession | null, remember?: boolean) => Promise<void>;
  sync: SyncController | null;
  workspace?: Workspace;
  onSave?: (next: Workspace) => boolean;
  onContinueLocal?: () => void;
};
export function Account({ api, session, onSession, sync, onContinueLocal }: AccountProps) {
  const [remember, setRemember] = useState(loginPreferences.read);
  const [register, setRegister] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState(session?.user.displayName ?? '');
  const [code, setCode] = useState('');
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [deletePassword, setDeletePassword] = useState('');
  const [sessions, setSessions] = useState<Record<string, unknown>[]>([]);
  const [retryAt, setRetryAt] = useState(0);
  const [showPassword, setShowPassword] = useState(false);
  const [sending, setSending] = useState(false);
  const [editing, setEditing] = useState<'profile'|'password'|'delete'|null>(null);
  const [, redraw] = useState(0);
  useEffect(() => sync?.subscribe(() => redraw((value) => value + 1)), [sync]);
  useEffect(() => {
    setName(session?.user.displayName ?? '');
    setSessions([]);
    setPassword('');
    setCurrentPassword('');
    setNewPassword('');
    setConfirmPassword('');
    setDeletePassword('');
    setCode('');
  }, [session?.user.id]);
  useEffect(() => {
    if (!retryAt) return;
    const timer = setInterval(() => {if(Date.now()>=retryAt)setRetryAt(0);redraw((value) => value + 1);}, 1000);
    return () => clearInterval(timer);
  }, [retryAt]);
  async function run(operation: () => Promise<unknown>) {
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      await operation();
    } catch (failure) {
      const messages:Record<string,string>={INVALID_CREDENTIALS:'邮箱或密码不正确',UNAUTHORIZED:'登录已过期，请重新登录',RATE_LIMITED:'操作过于频繁，请稍后重试',EMAIL_EXISTS:'此邮箱已注册',INVALID_REGISTRATION_CODE:'验证码无效或已过期，请重新获取',MAIL_NOT_CONFIGURED:'注册邮件服务尚未配置',CODE_COOLDOWN:'请稍后再获取验证码',CODE_SEND_LIMIT:'验证码发送次数过多，请稍后重试',MAIL_DELIVERY_FAILED:'验证码发送失败，请稍后重试'};
      setError(failure instanceof ApiException ? messages[failure.code] ?? failure.message : failure instanceof Error ? failure.message : typeof failure === 'string' ? failure : '操作失败');
    } finally {
      setBusy(false);
    }
  }
  function authenticate(event: FormEvent) {
    event.preventDefault();
    void run(async () => {
      const next = register
        ? await api.register(email.trim(), password, name.trim(), code.trim())
        : await api.login(email.trim(), password);
      setPassword('');
      setCode('');
      try {
        await onSession(next, remember);
      } catch (failure) {
        const detail = failure instanceof Error ? failure.message : typeof failure === 'string' ? failure : '无法初始化本机登录状态';
        throw new Error(`${register ? '账号已创建' : '账号验证成功'}，但未能完成本机登录：${detail}`);
      }
    });
  }
  if (!session) return <div className="auth-layout">
    <aside className="auth-brand">
      <div className="brand"><span className="brand-mark"><span/><span/><span/></span><span>FlowDay<span className="brand-dot">.</span></span></div>
      <div className="auth-message"><h1>让时间更有秩序<br/>让生活更有意义</h1><p>日程、任务、项目、灵感，<br/>在一个地方，清晰掌控每一天。</p></div>
    </aside>
    <section className="auth-form-area" aria-label={register?'注册账号':'登录账号'}>
      <form className="auth-form" onSubmit={authenticate}>
        <button className="auth-switch" type="button" disabled={busy} onClick={()=>{setRegister(!register);setError('');setCode('');}}>{register?'已有账号？立即登录':'没有账号？立即注册'}</button>
        <h1>{register?'创建账号':'欢迎回来'}</h1>
        {register&&<label className="field"><span>昵称</span><div className="auth-input"><UserIcon size={20}/><input required value={name} autoComplete="name" disabled={busy} onChange={event=>setName(event.target.value)}/></div></label>}
        <label className="field"><span>邮箱地址</span><div className="auth-input"><EnvelopeIcon size={20}/><input type="email" required value={email} disabled={busy} autoComplete="username" onChange={event=>setEmail(event.target.value)}/></div></label>
        <label className="field"><span>密码</span><div className="auth-input"><LockSimpleIcon size={20}/><input type={showPassword?'text':'password'} required minLength={register?10:undefined} maxLength={256} value={password} disabled={busy} autoComplete={register?'new-password':'current-password'} onChange={event=>setPassword(event.target.value)}/><button type="button" className="icon-button" disabled={busy} aria-label={showPassword?'隐藏密码':'显示密码'} onClick={()=>setShowPassword(!showPassword)}>{showPassword?<EyeSlashIcon size={20}/>:<EyeIcon size={20}/>}</button></div></label>
        {register&&<div className="auth-verification"><label className="field"><span>邮箱验证码</span><input required inputMode="numeric" pattern="[0-9]{6}" maxLength={6} value={code} disabled={busy} autoComplete="one-time-code" onChange={event=>setCode(event.target.value.replace(/\D/g,''))}/></label><button type="button" className="secondary-button" disabled={busy||retryAt>Date.now()} onClick={()=>{
          if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())){setError('请输入有效的邮箱地址');return;}
          setSending(true);void run(async()=>{try{const response=await api.sendRegistrationCode(email.trim());setRetryAt(Date.now()+Number(response.retryAfterSeconds??60)*1000);setCode('');}finally{setSending(false);}});
        }}>{sending?'发送中':retryAt>Date.now()?`${Math.ceil((retryAt-Date.now())/1000)} 秒后重发`:'发送验证码'}</button></div>}
        <label className="auth-remember"><input type="checkbox" checked={remember} disabled={busy} onChange={event=>setRemember(event.target.checked)}/><span>自动登录</span></label>
        <p className="auth-session-note">{remember?'在本机保存登录令牌，下次启动自动登录。':'仅本次登录，关闭应用后需要重新登录。'}</p>
        {error&&<p className="form-error" role="alert">{error}</p>}
        <button className="primary-button auth-submit" disabled={busy}>{busy&&!sending?'正在提交':register?'注册':'登录'}</button>
        {onContinueLocal&&<button className="auth-local" type="button" disabled={busy} onClick={onContinueLocal}>继续本地使用</button>}
      </form>
    </section>
  </div>;
  return (
    <section className="service-panel account-panel" aria-label="账号设置">
      <h2>账号信息</h2>
      <>
          <div className="account-summary"><span className="account-avatar">{session.user.displayName.slice(0,1)||'F'}</span><div><strong>{session.user.displayName}</strong><p>{session.user.email}</p></div><button disabled={busy} onClick={()=>{setError('');setEditing('profile');}}>编辑资料</button></div>
          <button className="settings-action" disabled={busy} onClick={()=>{setError('');setEditing('password');}}>密码<span aria-hidden="true">›</span></button>
          {editing==='profile'&&<ToolsDialog title="编辑资料" onClose={()=>{if(!busy)setEditing(null);}}><form
            onSubmit={(event) => {
              event.preventDefault();
              void run(async () => {
                const user = object(
                  (await api.feature(session.token, 'PUT', '/auth/profile', { displayName: name.trim() }))
                    .user,
                );
                await onSession({
                  ...session,
                  user: {
                    id: textField(user.id),
                    email: textField(user.email),
                    displayName: textField(user.displayName),
                  },
                });
                setEditing(null);
              });
            }}
          >
            <label>
              昵称
              <input required disabled={busy} value={name} onChange={(event) => setName(event.target.value)} />
            </label>
            <button disabled={busy}>保存资料</button>
            <button type="button" disabled={busy} onClick={()=>setEditing(null)}>取消</button>
            {error&&<p className="form-error" role="alert">{error}</p>}
          </form></ToolsDialog>}
          {editing==='password'&&<ToolsDialog title="修改密码" onClose={()=>{if(!busy){setEditing(null);setCurrentPassword('');setNewPassword('');setConfirmPassword('');}}}><form
            onSubmit={(event) => {
              event.preventDefault();
              void run(async () => {
                if(newPassword!==confirmPassword)throw new Error('两次输入的新密码不一致');
                await api.feature(session.token, 'POST', '/auth/password', { currentPassword, newPassword });
                setCurrentPassword('');
                setNewPassword('');
                setConfirmPassword('');
                setEditing(null);
              });
            }}
          >
            <label>
              当前密码
              <input
                type="password"
                required
                disabled={busy}
                value={currentPassword}
                onChange={(event) => setCurrentPassword(event.target.value)}
                autoComplete="current-password"
              />
            </label>
            <label>
              新密码
              <input
                type="password"
                required
                disabled={busy}
                minLength={10}
                maxLength={256}
                value={newPassword}
                onChange={(event) => setNewPassword(event.target.value)}
                autoComplete="new-password"
              />
            </label>
            <label>确认新密码<input type="password" required value={confirmPassword} autoComplete="new-password" disabled={busy} onChange={event=>setConfirmPassword(event.target.value)}/></label>
            <button className="primary-button" disabled={busy}>修改密码</button>
            <button type="button" disabled={busy} onClick={()=>{setEditing(null);setCurrentPassword('');setNewPassword('');setConfirmPassword('');}}>取消</button>
            {error&&<p className="form-error" role="alert">{error}</p>}
          </form></ToolsDialog>}
          <h3>安全会话</h3>
          <div className="service-actions">
            <button
              disabled={busy}
              onClick={() =>
                void run(async () =>
                  setSessions(rows((await api.feature(session.token, 'GET', '/auth/sessions')).sessions)),
                )
              }
            >
              查看会话
            </button>
            <button
              disabled={busy}
              onClick={() =>
                void run(async () => {
                  await api.feature(session.token, 'POST', '/auth/sessions/revoke-others');
                  setSessions([]);
                })
              }
            >
              退出其他设备
            </button>
          </div>
          {sessions.map((item, index) => (
            <p key={index}>
              {item.current ? '当前设备' : '其他设备'} · {String(item.expiresAt)}
            </p>
          ))}
          <div className="service-actions">
            <button
              disabled={busy}
              onClick={() =>
                void run(async () => {
                  try {
                    await api.feature(session.token, 'POST', '/auth/logout');
                  } finally {
                    await onSession(null);
                  }
                })
              }
            >
              退出登录
            </button>
            <button
              disabled={busy}
              className="danger"
              onClick={() => {setError('');setEditing('delete');}}
            >
              删除账号
            </button>
          </div>
          {editing==='delete'&&<ToolsDialog title="注销账号" onClose={()=>{if(!busy){setEditing(null);setDeletePassword('');}}}><p>账号及服务器上的全部数据将被永久删除，此操作不可恢复。</p><form onSubmit={event=>{event.preventDefault();void run(async()=>{await api.feature(session.token,'POST','/auth/delete',{password:deletePassword,confirmation:'DELETE'});setDeletePassword('');await onSession(null);});}}><label>当前密码<input type="password" required disabled={busy} value={deletePassword} autoComplete="current-password" onChange={event=>setDeletePassword(event.target.value)}/></label><div className="service-actions"><button className="secondary-button" type="button" disabled={busy} onClick={()=>{setEditing(null);setDeletePassword('');}}>取消</button><button className="primary-button" disabled={busy}>永久注销账号</button></div>{error&&<p className="form-error" role="alert">{error}</p>}</form></ToolsDialog>}
      </>
      {error && !editing && <p role="alert">{error}</p>}
    </section>
  );
}
