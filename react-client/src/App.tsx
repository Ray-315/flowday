import { AppleCalendarSync } from './AppleCalendarSync';
import { LiveActivity } from './LiveActivity';
import { endActivityForOtherScope } from './liveActivityBridge';
import { lazy, Suspense, useEffect, useRef, useState, type CSSProperties } from 'react';
import { AnimatePresence, MotionConfig, motion } from 'motion/react';
import { SunIcon } from '@phosphor-icons/react/dist/csr/Sun';
import { CalendarBlankIcon } from '@phosphor-icons/react/dist/csr/CalendarBlank';
import { CheckCircleIcon } from '@phosphor-icons/react/dist/csr/CheckCircle';
import { FlowArrowIcon } from '@phosphor-icons/react/dist/csr/FlowArrow';
import { ChartBarIcon } from '@phosphor-icons/react/dist/csr/ChartBar';
import { BellIcon } from '@phosphor-icons/react/dist/csr/Bell';
import { SparkleIcon } from '@phosphor-icons/react/dist/csr/Sparkle';
import { UserCircleIcon } from '@phosphor-icons/react/dist/csr/UserCircle';
import { GearSixIcon } from '@phosphor-icons/react/dist/csr/GearSix';
import { DatabaseIcon } from '@phosphor-icons/react/dist/csr/Database';
import { SlidersHorizontalIcon } from '@phosphor-icons/react/dist/csr/SlidersHorizontal';
import { GraduationCapIcon } from '@phosphor-icons/react/dist/csr/GraduationCap';
import { FoldersIcon } from '@phosphor-icons/react/dist/csr/Folders';
import {
  CheckCheck,
  ChevronRight,
  Plus,
  Search,
  X,
} from './icons';
import { Calendar, MiniCalendar } from './Calendar';
import { Tasks } from './Tasks';
import { Editor } from './Editors';
import { MobileNavigation } from './MobileNavigation';
import { CloudSync } from './CloudSync';
import type { ServiceSection } from './Services';
import { SettingsPage, type SettingsSection } from './SettingsPage';
import { initialWorkspace, initialStorageError, workspaceStorage, trialStorageKey, credentialVault, loginPreferences, persistRemote, readSyncBaseline, saveSyncBaseline } from './storage';
import { FlowApi, SyncController, ApiException, type AuthSession } from './api';
import { GlobalSearch } from './GlobalSearch';
import { Account } from './Account';
import { exportFile } from './Tools';
import { Projects } from './Management';
import { materializeRecurring, setTaskStatus, activeTasks as visibleTasks, isProjectHidden, workflowNodes } from './domain';
import { dueReminders, showNotification, recordReminderDelivery, type Receipt } from './reminders';
import { Notices } from './Notices';
import { dayInZone, zoneFor } from './timezone';
import { QuickCapture, TodayCustomization, TodayExtraModule, todayModuleOrder, todayHiddenModules, isDefaultTodayLayout } from './TodayExtras';
import {
  emptyWorkspace,
  hexColor,
  localDay,
  parseWorkspace,
  previewWorkspace,
  type CalendarEvent,
  type Project,
  type Task,
  type Workspace,
} from './workspace';

const storageKey = trialStorageKey;
const Services=lazy(()=>import('./Services').then(module=>({default:module.Services})));
const Workflow=lazy(()=>import('./Workflow').then(module=>({default:module.Workflow})));
const Reports=lazy(()=>import('./Reports').then(module=>({default:module.Reports})));
const CourseImport=lazy(()=>import('./CourseImport').then(module=>({default:module.CourseImport})));
const preview = import.meta.env.DEV && new URLSearchParams(location.search).get('preview') === '1';
type Page = 'today' | 'calendar' | 'tasks' | 'workflow' | 'reports' | 'notices' | 'services' | 'attachments' | 'more' | 'projects' | 'settings';
const pageNames:Record<Page,string>={today:'今天',calendar:'日历',tasks:'任务',workflow:'工作流',reports:'报告',notices:'通知',services:'AI 助手',attachments:'附件管理',more:'更多',projects:'项目管理',settings:'设置'};

function NavigationIcon({ page }: { page: Page }) {
  const Icon = page === 'today' ? SunIcon : page === 'calendar' ? CalendarBlankIcon : page === 'workflow' ? FlowArrowIcon : page==='reports'?ChartBarIcon:page==='notices'?BellIcon:page==='services'?SparkleIcon:page==='projects'?FoldersIcon:CheckCircleIcon;
  return (
    <Icon className="navigation-icon" size={20} weight="regular" aria-hidden="true" />
  );
}
export type Editing =
  | { kind: 'task'; item?: Task }
  | { kind: 'event'; item?: CalendarEvent; start?: string }
  | { kind: 'project'; item?: Project };

function load() {
  if (preview) return { data: previewWorkspace(), error: '' };
  if (initialStorageError) return { data: emptyWorkspace(), error: initialStorageError };
  if (initialWorkspace) return { data: initialWorkspace, error: '' };
  try {
    const raw = localStorage.getItem(storageKey);
    return { data: raw ? parseWorkspace(raw) : emptyWorkspace(), error: '' };
  } catch {
    return { data: emptyWorkspace(), error: '无法读取本地数据，请先在设置中导出原始数据再重试。' };
  }
}

export default function App() {
  const [initial] = useState(load);
  const [data, setData] = useState(initial.data);
  const [error, setError] = useState(initial.error);
  const [sessionError, setSessionError] = useState('');
  const authIntent = useRef(0);
  const rememberSession = useRef(loginPreferences.read());
  const [storageBlocked, setStorageBlocked] = useState(Boolean(initial.error));
  const [page, setPage] = useState<Page>('today');
  const [day, setDay] = useState(localDay);
  const [project, setProject] = useState<string | null>(null);
  const [workflowFocus, setWorkflowFocus] = useState<{ projectId: string|null; nodeId: string|null }>({projectId:null,nodeId:null});
  const [query, setQuery] = useState('');
  const [editing, setEditing] = useState<Editing | null>(null);
  const [noticeTab, setNoticeTab] = useState('通知记录');
  const [settingsSection, setSettingsSection] = useState<SettingsSection>('general');
  const [authOpen, setAuthOpen] = useState(false);
  const [tool, setTool] = useState<'courses'|'today'|null>(null);
  const [session, setSession] = useState<AuthSession|null>(null);
  const [captureText,setCaptureText]=useState('');
  const [api] = useState(()=>new FlowApi());
  const [sync, setSync] = useState<SyncController|null>(null);
  const dataRef=useRef(data);
  dataRef.current=data;
  const scopeRef=useRef('guest');
  const scopeGeneration=useRef(0);
  const switchingRef=useRef(false);
  const syncRef=useRef<SyncController|null>(null);
  const renderedScope=scopeRef.current;
  const renderedGeneration=scopeGeneration.current;
  const [clock, setClock] = useState(new Date());
  const [systemDark,setSystemDark]=useState(()=>matchMedia('(prefers-color-scheme: dark)').matches);
  const dark = data.preferences.themeMode === 'dark'||data.preferences.themeMode==='system'&&systemDark;
  const reduced = data.preferences.reduceMotion === true;
  const projects = data.projects.filter((item) => !isProjectHidden(data,item.id));
  const selectedProject = projects.find((item) => item.id === project);
  const navigate = (next: Page) => {
    setPage(next);
    setTool(null);
    setProject(null);
    setQuery('');
  };
  function commit(next: Workspace) {
    try {
      if(renderedScope!==scopeRef.current||renderedGeneration!==scopeGeneration.current)throw new Error('账号已切换，请重新打开操作');
      if(switchingRef.current)throw new Error('账号正在切换，请稍后保存');
      if (storageBlocked) throw new Error('请先导出无法读取的原始数据，然后重新导入有效备份。');
      if (!preview) {
        workspaceStorage.save(scopeRef.current, next);
        void workspaceStorage.flush().catch(() => setError('本地文件保存失败，恢复副本已保留。请导出备份并检查磁盘空间。'));
      }
      dataRef.current=next;
      setData(next);
      setError('');
      return true;
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : '保存失败，请检查可用存储空间。');
      return false;
    }
  }
  function restore(next: Workspace) {
    try {
      if(renderedScope!==scopeRef.current||renderedGeneration!==scopeGeneration.current)throw new Error('账号已切换，请重新打开操作');
      if(switchingRef.current)throw new Error('账号正在切换，请稍后恢复');
      if (!preview) {
        workspaceStorage.protect(scopeRef.current);
        workspaceStorage.save(scopeRef.current, next);
        void workspaceStorage.flush().catch(()=>setError('本地文件恢复失败，原始备份已保留。'));
      }
      setStorageBlocked(false);
      dataRef.current=next;
      setData(next);
      setError('');
      setProject(null);
      return true;
    } catch {
      setError('导入失败，原始数据已保留。请检查可用存储空间。');
      return false;
    }
  }
  async function createSync(next:AuthSession|null,target:string,generation:number) {
    let controller:SyncController|null=null;
    if(next) {
      let baseline: {version:number;json:string}|undefined;
      baseline=await readSyncBaseline(target);
      controller=new SyncController(api,next,{
        read:()=>dataRef.current,
        replace:value=>persistRemote(workspaceStorage,target,value,()=>dataRef.current,value=>{dataRef.current=value;setData(value);},()=>scopeRef.current===target&&scopeGeneration.current===generation&&!switchingRef.current),
        backup:async()=>{if(scopeRef.current!==target||scopeGeneration.current!==generation)throw new Error('账号已切换');workspaceStorage.protect(target);await workspaceStorage.flush();},
        baseline,
        saveBaseline:(version,json)=>saveSyncBaseline(target,version,json),
      });
    }
    return controller;
  }
  async function switchSession(next:AuthSession|null, persist=true, remember=rememberSession.current) {
    if(persist)authIntent.current++;
    const target=next ? `${api.baseUrl}:${next.user.id}` : 'guest';
    if(target===scopeRef.current&&(!next||next.token===syncRef.current?.session.token)) {if(persist&&next){if(remember)await credentialVault.write('session',JSON.stringify(next));else await credentialVault.delete('session');loginPreferences.write(remember);rememberSession.current=remember;}setSession(next);setSessionError('');return;}
    const generation=++scopeGeneration.current;
    const previousScope=scopeRef.current;
    switchingRef.current=true;
    syncRef.current?.dispose();setSync(null);
    try {
      await workspaceStorage.flush();
      const workspace=await workspaceStorage.load(target);
      if(generation!==scopeGeneration.current)return;
      const controller=await createSync(next,target,generation);
      if(generation!==scopeGeneration.current){controller?.dispose();return;}
      await endActivityForOtherScope(target);
      if(generation!==scopeGeneration.current){controller?.dispose();return;}
      if(persist) {
        if(next&&remember)await credentialVault.write('session',JSON.stringify(next));
        else if(next||rememberSession.current)await credentialVault.delete('session');
        loginPreferences.write(next?remember:false);
        rememberSession.current=next?remember:false;
      }
      if(generation!==scopeGeneration.current)return;
      scopeRef.current=target;dataRef.current=workspace;
      setData(workspace);setStorageBlocked(false);setProject(null);setQuery('');setEditing(null);setAuthOpen(false);setTool(null);setWorkflowFocus({projectId:null,nodeId:null});setCaptureText('');setSession(next);
      syncRef.current=controller;setSync(controller);
      setSessionError('');
      switchingRef.current=false;
      if(controller)void controller.sync();
    } catch(failure) {
      if(generation===scopeGeneration.current) {const controller=await createSync(session,previousScope,generation);syncRef.current=controller;setSync(controller);}
      throw failure;
    } finally {if(generation===scopeGeneration.current)switchingRef.current=false;}
  }
  useEffect(()=>{
    let disposed=false;
    const intent=authIntent.current;
    const current=()=>!disposed&&intent===authIntent.current;
    if(!preview&&rememberSession.current)void credentialVault.read('session').then(async source=>{
      if(!source||!current())return;
      const value=JSON.parse(source) as AuthSession;
      if(typeof value.token!=='string'||!value.user?.id)throw new Error('会话数据无效');
      try {value.user=await api.me(value.token);}
      catch(failure){
        if(!current())return;
        if(failure instanceof ApiException&&failure.status===401){
          await credentialVault.delete('session');
          throw new Error('登录已过期，请重新登录。');
        }
      }
      if(!current())return;
      await switchSession(value,false);
    }).catch(failure=>{
      if(!current())return;
      const detail=failure instanceof Error?failure.message:typeof failure==='string'?failure:'请重新登录。';
      setSessionError(`无法恢复登录会话：${detail}`);
    });
    return()=>{disposed=true;syncRef.current?.dispose();};
  },[]);
  useEffect(()=>{
    if(!sync||data.preferences.autoSync!==true)return;
    const timer=setInterval(()=>void sync.sync(),30000);return()=>clearInterval(timer);
  },[sync,data.preferences.autoSync]);
  useEffect(()=>{
    if(storageBlocked||switchingRef.current)return;
    try {const until=new Date();until.setMonth(until.getMonth()+3);const next=materializeRecurring(data,until.toISOString());if(JSON.stringify(next)!==JSON.stringify(data))commit(next);}catch(failure){setError(failure instanceof Error?failure.message:'重复日程展开失败');}
  },[data.tasks,data.events,storageBlocked]);
  useEffect(()=>{
    if(preview||storageBlocked)return;
    const run=()=>{
      const scope=scopeRef.current;
      const key=`${workspaceStorage.key(scope)}.reminder-receipts`;
      try {
        const receipts:Record<string,Receipt>=JSON.parse(localStorage.getItem(key)??'{}');
        const current=dataRef.current;
        const pending=dueReminders(current,receipts);
        if(!pending.length)return;
        const now=new Date().toISOString();
        const notices=Array.isArray(current.notices)?[...current.notices]:[];
        for(const item of pending){
          const noticeId=crypto.randomUUID();
          receipts[item.key]=recordReminderDelivery(receipts[item.key],noticeId,new Date(now));
          notices.push({id:noticeId,title:item.title,body:'提醒',createdAt:now,read:false,acknowledged:false,type:'reminder',taskId:item.taskId??null,eventId:item.eventId??null,projectId:null,nodeId:null});
          if(current.preferences.nativeNotifications===true)void showNotification('FlowDay',item.title).catch(()=>setError('系统通知发送失败'));
        }
        if(commit({...current,notices}))localStorage.setItem(key,JSON.stringify(receipts));
      }catch{setError('无法保存本地提醒记录');}
    };
    run();const timer=setInterval(run,15000);return()=>clearInterval(timer);
  },[session,storageBlocked]);
  useEffect(() => {
    const timer = setInterval(() => setClock(new Date()), 60_000);
    return () => clearInterval(timer);
  }, []);
  useEffect(() => {
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    document.documentElement.dataset.reduceMotion = String(reduced);
  }, [dark, reduced]);
  useEffect(()=>{const media=matchMedia('(prefers-color-scheme: dark)');const update=()=>setSystemDark(media.matches);media.addEventListener('change',update);return()=>media.removeEventListener('change',update);},[]);
  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if (event.key.toLowerCase() === 'k' && (event.ctrlKey || event.metaKey)) {
        event.preventDefault();
        if (!editing && !authOpen) document.getElementById('search')?.focus();
      }
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [editing, authOpen]);
  const activeTasks = visibleTasks(data).filter(
    (item) =>
      !item.deletedAt &&
      !item.archived &&
      item.status !== 'cancelled' &&
      (!project || item.projectId === project),
  );
  const dayTasks = activeTasks.filter((item) => item.deadline && dayInZone(new Date(item.deadline),zoneFor(data)) === day);
  const completed = dayTasks.filter((item) => item.status === 'done').length;
  const percentage = dayTasks.length ? Math.round((completed / dayTasks.length) * 100) : 0;
  const defaultToday=isDefaultTodayLayout(data);
  const openWorkflow=(projectId:string,nodeId?:string)=>{setWorkflowFocus({projectId,nodeId:nodeId??null});setPage('workflow');setQuery('');};
  const quickCapture=<QuickCapture data={data} onSave={commit} onParse={text=>{setCaptureText(text);navigate('services');}}/>;
  const todayTaskPanel=<Tasks data={data} day={day} query={query} project={null} onEdit={setEditing} onSave={commit} onToggle={id=>commit(setTaskStatus(data,id,data.tasks.find(task=>task.id===id)?.status==='done'?'todo':'done'))}/>;
  function todayModule(key:string){
    if(key==='capture')return quickCapture;
    if(key==='timeline')return <Calendar data={data} day={day} onDay={setDay} onEdit={setEditing} query={query} clock={clock} full={false} onSave={commit}/>;
    if(key==='todo')return todayTaskPanel;
    if(key==='calendar')return <MiniCalendar day={day} onDay={setDay} events={data.events} weekStartsMonday={data.preferences.weekStartsMonday!==false} timezone={zoneFor(data)}/>;
    if(key==='overview')return <section className="panel overview"><div className="section-heading"><h2>本日概览</h2><CheckCheck size={18}/></div><div className="progress-ring" style={{'--progress':`${percentage}%`} as CSSProperties}><div><strong>{percentage}<small>%</small></strong><span>今日完成</span></div></div><div className="overview-stats"><div><span>待办</span><strong>{dayTasks.length-completed}</strong></div><div><span>完成</span><strong>{completed}</strong></div></div></section>;
    if(key==='workflow'||key==='overdue'||key==='pressure'||key==='notices')return <TodayExtraModule module={key} data={data} day={day} onSave={commit} onEdit={setEditing} onNavigate={value=>{if(value==='notices'||value==='workflow'||value==='tasks'||value==='calendar')navigate(value);}} onWorkflow={openWorkflow} clock={clock}/>;
    return null;
  }
  const hour = clock.getHours();
  const greeting = hour < 6 ? '夜深了' : hour < 12 ? '早上好' : hour < 18 ? '下午好' : '晚上好';
  const title =
    selectedProject?.title ?? (page === 'today' ? greeting : pageNames[page]);
  const openSettings = (section: SettingsSection) => {setSettingsSection(section);navigate('settings');};
  const account = <Account api={api} session={session} onSession={async (next,remember)=>{await switchSession(next,true,remember);setAuthOpen(false);openSettings('account');}} sync={sync} workspace={data} onSave={commit} onContinueLocal={()=>setAuthOpen(false)}/>;
  const signIn = <button className="settings-action" onClick={()=>setAuthOpen(true)}>登录账号以使用此功能<ChevronRight size={18}/></button>;
  const service = (section: ServiceSection) => session && sync ? <Services key={section} section={section} api={api} session={session} sync={sync} workspace={data} onExport={exportFile} initialText={captureText}/> : signIn;
  const enter = {
    initial: { opacity: 0, y: reduced ? 0 : 12 },
    animate: { opacity: 1, y: 0 },
    exit: { opacity: 0, y: reduced ? 0 : -6 },
    transition: {
      duration: reduced ? 0 : 0.24,
      ease: [0.22, 1, 0.36, 1] as [number, number, number, number],
    },
  };

  return (
    <MotionConfig
      reducedMotion={reduced ? 'always' : 'user'}
      transition={{ duration: 0.22, ease: [0.22, 1, 0.36, 1] }}
    >
      <Suspense fallback={null}>
      {authOpen && !session ? <div className="auth-screen">{account}</div> : <>
      <div className="app-shell">
        <aside className="sidebar">
          <button className="brand" onClick={() => navigate('today')} aria-label="FlowDay 首页">
            <span className="brand-mark">
              <span />
              <span />
              <span />
            </span>
            <span>
              FlowDay<span className="brand-dot">.</span>
            </span>
          </button>
          <nav className="navigation" aria-label="主导航">
            {(
              [
                ['today', '今天'],
                ['calendar', '日历'],
                ['tasks', '任务'],
                ['workflow', '工作流'],
                ['reports', '报告'],
                ['notices', '通知'],
                ['services', 'AI 助手'],
              ] as const
            ).map(([key, label]) => (
              <button
                key={key}
                aria-label={label}
                className={`nav-item ${(page === key || (key === 'tasks' && page === 'attachments')) && !project ? 'active' : ''}`}
                aria-current={(page === key || (key === 'tasks' && page === 'attachments')) && !project ? 'page' : undefined}
                onClick={() => navigate(key)}
              >
                {(page === key || (key === 'tasks' && page === 'attachments')) && !project && (
                  <motion.span
                    className="nav-selection"
                    layoutId="nav-selection"
                    transition={{ type: 'spring', stiffness: 460, damping: 38 }}
                  />
                )}
                <NavigationIcon page={key} />
                <span>{label}</span>
                {key === 'tasks' && activeTasks.filter((item) => item.status !== 'done').length > 0 && (
                  <span className="nav-count">
                    {activeTasks.filter((item) => item.status !== 'done').length}
                  </span>
                )}
              </button>
            ))}
          </nav>
          <div className="project-navigation">
            <div className="sidebar-label">
              <button className="project-section-link" aria-label="项目管理" aria-current={page==='projects'?'page':undefined} onClick={()=>navigate('projects')}>项目<ChevronRight size={12}/></button>
              <button
                className="icon-button"
                aria-label="新建项目"
                onClick={() => setEditing({ kind: 'project' })}
              >
                <Plus size={15} />
              </button>
            </div>
            {projects.map((item) => (
              <button
                key={item.id}
                className={`project-link ${project === item.id ? 'active' : ''}`}
                onClick={() => {
                  setProject(item.id);
                  setPage('tasks');
                  setQuery('');
                }}
              >
                <span className="project-dot" style={{ background: hexColor(item.color) }} />
                <span>{item.title}</span>
                <ChevronRight size={14} />
              </button>
            ))}
          </div>
          <div className="sidebar-footer">
            <button className={`sidebar-account ${page==='settings'&&settingsSection==='account'?'active':''}`} aria-label="账号与安全" onClick={()=>session?openSettings('account'):setAuthOpen(true)}><UserCircleIcon size={28} weight="regular"/><span>{session?.user.displayName||'账号与安全'}</span><ChevronRight size={14}/></button>
            <div className="sidebar-utilities">
              <button className="mobile-projects" aria-label="项目管理" aria-current={page==='projects'?'page':undefined} onClick={()=>navigate('projects')}><NavigationIcon page="projects"/><span>项目</span></button>
              <button aria-label="同步与备份" onClick={()=>openSettings('cloud')}><DatabaseIcon size={18}/><span>同步与备份</span></button>
              <button className="settings-button" aria-label="设置" aria-current={page==='settings'?'page':undefined} onClick={() => openSettings('general')}><GearSixIcon size={18}/><span>设置</span></button>
            </div>
          </div>
        </aside>

        <main className="main">
          <header className="page-header">
            <div>
              <div className="header-date">
                {new Date(`${day}T12:00:00`).toLocaleDateString('zh-CN', {
                  year: 'numeric',
                  month: 'long',
                  day: 'numeric',
                  weekday: 'long',
                })}
              </div>
              <h1>
                {title}
                <span className="heading-period">.</span>
              </h1>
            </div>
            <div className="header-actions">
              {page==='tasks'&&<button className="context-action" onClick={()=>navigate('attachments')}>附件管理</button>}
              {page==='attachments'&&<button className="context-action" onClick={()=>navigate('tasks')}>返回任务</button>}
              {page==='today'&&<button className="context-action" onClick={()=>setTool('today')}><SlidersHorizontalIcon size={18}/><span>定制今天</span></button>}
              {page==='calendar'&&<AppleCalendarSync data={data} onSave={commit} scope={renderedScope}/>}
              {page==='calendar'&&<button className="context-action" onClick={()=>setTool('courses')}><GraduationCapIcon size={19}/><span>课程导入</span></button>}
              <label className="search">
                <Search size={17} />
                <input
                  id="search"
                  value={query}
                  onChange={(event) => setQuery(event.target.value)}
                  placeholder="搜索任务、日程"
                  aria-label="搜索任务、日程"
                />
                <kbd>Ctrl K</kbd>
              </label>
            </div>
          </header>
          {(error || sessionError) && (
            <div className="error-message" role="alert">
              {error || sessionError}
              <button className="icon-button" aria-label="关闭错误" onClick={() => error ? setError('') : setSessionError('')}>
                <X size={16} />
              </button>
            </div>
          )}
          {query && <GlobalSearch data={data} query={query} onEdit={setEditing} onProject={id=>{setProject(id);setPage('tasks');setQuery('');}} onNode={id=>{setWorkflowFocus({projectId:workflowNodes(data).find(node=>node.id===id)?.projectId??null,nodeId:id});setPage('workflow');setQuery('');}}/>}
          <LiveActivity workspace={data} scope={renderedScope} visible={page==='today'}/>
          <AnimatePresence mode="wait" initial={false}>
            <motion.div
              key={`${page}-${project ?? ''}`}
              {...enter}
              className={`page-content ${page === 'today' ? defaultToday?'today-grid':'today-custom-grid' : ''}`}
            >
              {page==='today'&&defaultToday&&quickCapture}
              {((page === 'today'&&defaultToday) || page === 'calendar') && (
                <Calendar
                  data={data}
                  day={day}
                  onDay={setDay}
                  onEdit={setEditing}
                  query={query}
                  clock={clock}
                  full={page === 'calendar'}
                  onSave={commit}
                />
              )}
              {page === 'today' && defaultToday && (
                <div className="right-column">
                  <Tasks
                    data={data}
                    day={day}
                    query={query}
                    project={null}
                    onEdit={setEditing}
                    onToggle={(id) => commit(setTaskStatus(data,id,data.tasks.find(task=>task.id===id)?.status==='done'?'todo':'done'))}
                    onSave={commit}
                  />
                  <div className="bottom-grid">
                    <MiniCalendar day={day} onDay={setDay} events={data.events} weekStartsMonday={data.preferences.weekStartsMonday!==false} timezone={zoneFor(data)} />
                    <section className="panel overview">
                      <div className="section-heading">
                        <h2>本日概览</h2>
                        <CheckCheck size={18} />
                      </div>
                      <div
                        className="progress-ring"
                        style={{ '--progress': `${percentage}%` } as CSSProperties}
                      >
                        <div>
                          <motion.strong
                            key={percentage}
                            initial={{ opacity: 0, y: 5 }}
                            animate={{ opacity: 1, y: 0 }}
                          >
                            {percentage}
                            <small>%</small>
                          </motion.strong>
                          <span>今日完成</span>
                        </div>
                      </div>
                      <div className="overview-stats">
                        <div>
                          <span>日程</span>
                          <strong>
                            {
                              data.events.filter(
                                (item) => !item.deletedAt && dayInZone(new Date(item.start),zoneFor(data)) === day,
                              ).length
                            }
                          </strong>
                        </div>
                        <div>
                          <span>待办</span>
                          <strong>{dayTasks.length - completed}</strong>
                        </div>
                        <div>
                          <span>完成</span>
                          <strong>{completed}</strong>
                        </div>
                      </div>
                    </section>
                  </div>
                </div>
              )}
              {page==='today'&&!defaultToday&&todayModuleOrder(data).filter(key=>!todayHiddenModules(data).has(key)).map(key=><div className="today-module" key={key}>{todayModule(key)}</div>)}
              {page === 'tasks' && (
                <Tasks
                  data={data}
                  day={day}
                  query={query}
                  project={project}
                  onEdit={setEditing}
                  onToggle={(id) => commit(setTaskStatus(data,id,data.tasks.find(task=>task.id===id)?.status==='done'?'todo':'done'))}
                  onSave={commit}
                  full
                />
              )}
              {page==='workflow'&&<Workflow data={data} onSave={commit} onEdit={setEditing} onProject={id=>setWorkflowFocus({projectId:id,nodeId:null})} {...workflowFocus}/>}
              {page==='reports'&&<Reports data={data} day={day} onEdit={setEditing}/>}
              {page==='notices'&&<section className="workspace-page"><nav className="service-tabs" aria-label="通知选项">{['通知记录','提醒管理'].map(label=><button key={label} aria-current={noticeTab===label?'page':undefined} onClick={()=>setNoticeTab(label)}>{label}</button>)}</nav>{noticeTab==='提醒管理'?service('提醒'):<Notices data={data} onSave={commit} onEdit={setEditing} receiptKey={workspaceStorage.key(scopeRef.current)+'.reminder-receipts'}/>}</section>}
              {page==='more'&&<div className="mobile-more">
                <p className="section-description">规划、回顾和管理，都在这里。</p>
                <div className="mobile-more-links">{([['projects','项目管理'],['workflow','工作流'],['reports','报告'],['notices','通知与提醒']] as const).map(([key,label])=><button key={key} onClick={()=>navigate(key)}><NavigationIcon page={key}/><span>{label}</span><ChevronRight size={18}/></button>)}</div>
                <div className="mobile-more-links"><button onClick={()=>session?openSettings('account'):setAuthOpen(true)}><UserCircleIcon size={24}/><span>{session?.user.displayName||'登录账号'}</span><ChevronRight size={18}/></button><button onClick={()=>openSettings('cloud')}><DatabaseIcon size={24}/><span>同步与备份</span><ChevronRight size={18}/></button><button onClick={()=>openSettings('integrations')}><CalendarBlankIcon size={24}/><span>iCloud 日历与集成</span><ChevronRight size={18}/></button><button onClick={()=>openSettings('general')}><GearSixIcon size={24}/><span>设置</span><ChevronRight size={18}/></button></div>
              </div>}
              {page==='projects'&&<section className="workspace-page"><Projects data={data} onSave={commit} onEdit={setEditing}/></section>}
              {page==='settings'&&<SettingsPage data={data} onSave={commit} onImport={restore} rawBackup={()=>workspaceStorage.raw(scopeRef.current)} scope={scopeRef.current} section={settingsSection} onSection={setSettingsSection} cloudSync={sync?<CloudSync sync={sync} workspace={data} onSave={commit} onSignIn={()=>{void switchSession(null).then(()=>setAuthOpen(true));}}/>:signIn} cloudBackups={service('备份')} apple={service('Apple 日历')} feishu={service('飞书')} account={session?account:<button className="settings-action" onClick={()=>setAuthOpen(true)}>登录账号<ChevronRight size={18}/></button>} onToday={()=>setTool('today')} onCourses={()=>setTool('courses')} onDone={()=>navigate('today')}/>}
              {page==='services'&&(session && sync ? <section className="workspace-page">{service('AI')}</section> : <section className="ai-signin" aria-label="登录以使用 AI 助手">
                <div className="ai-signin-heading"><SparkleIcon size={23} weight="duotone" aria-hidden="true"/><h2>把想法变成计划</h2></div>
                <p>描述你的安排，让 AI 帮你整理任务、规划日程。</p>
                <div className="ai-signin-action"><button className="primary-button" onClick={()=>setAuthOpen(true)}>登录账号</button><span>登录后即可使用 AI 助手</span></div>
              </section>)}
              {page==='attachments'&&<section className="workspace-page">{service('附件')}</section>}
            </motion.div>
          </AnimatePresence>
        </main>
        <MobileNavigation page={page} onNavigate={navigate}/>
      </div>
      <AnimatePresence>
        {editing && (
          <Editor
            key={`${editing.kind}-${editing.item?.id ?? 'new'}`}
            editing={editing}
            data={data}
            day={day}
            defaultProject={project}
            onSave={commit}
            onClose={() => setEditing(null)}
          />
        )}
      </AnimatePresence>
      {tool==='courses'&&<CourseImport data={data} onSave={commit} onClose={()=>setTool(null)}/>}
      {tool==='today'&&<TodayCustomization data={data} onSave={commit} onClose={()=>setTool(null)}/>}
      </>}
      </Suspense>
    </MotionConfig>
  );
}
