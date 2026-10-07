import { SunIcon } from '@phosphor-icons/react/dist/csr/Sun';
import { CalendarBlankIcon } from '@phosphor-icons/react/dist/csr/CalendarBlank';
import { CheckCircleIcon } from '@phosphor-icons/react/dist/csr/CheckCircle';
import { SparkleIcon } from '@phosphor-icons/react/dist/csr/Sparkle';
import { DotsThreeIcon } from '@phosphor-icons/react/dist/csr/DotsThree';

export type MobilePage = 'today' | 'calendar' | 'tasks' | 'services' | 'more';
const tabs = [
  ['today', '今天', SunIcon], ['calendar', '日历', CalendarBlankIcon],
  ['tasks', '任务', CheckCircleIcon], ['services', 'AI 助手', SparkleIcon], ['more', '更多', DotsThreeIcon],
] as const;
export function MobileNavigation({ page, onNavigate }: { page: string; onNavigate: (page: MobilePage) => void }) {
  const selected = page === 'attachments' ? 'tasks' : tabs.some(([key]) => key === page) ? page : 'more';
  return <nav className="mobile-navigation" aria-label="手机主导航">{tabs.map(([key, label, Icon]) =>
    <button key={key} aria-label={label} aria-current={selected === key ? 'page' : undefined} onClick={() => onNavigate(key)}>
      <Icon size={24} weight={selected === key ? 'fill' : 'regular'}/><span>{label}</span>
    </button>
  )}</nav>;
}
