import { Select } from './Select';
import { useState } from 'react';
import {
  parseCourses,
  parseCSV,
  courseConflicts,
  importCourses,
  type CourseLesson,
  type CourseChoice,
} from './courses';
import type { Workspace } from './workspace';
import { zoneFor } from './timezone';
export function CourseImport({
  data,
  onSave,
  onClose,
}: {
  data: Workspace;
  onSave: (data: Workspace) => boolean;
  onClose: () => void;
}) {
  const [semester, setSemester] = useState('');
  const [lessons, setLessons] = useState<CourseLesson[]>([]);
  const [choice, setChoice] = useState<CourseChoice>('keep');
  const [error, setError] = useState('');
  const [source, setSource] = useState('');
  const [format, setFormat] = useState('');
  const [headers, setHeaders] = useState<string[]>([]);
  const [mapping, setMapping] = useState<Record<string, string>>({});
  const [excluded, setExcluded] = useState<number[]>([]);
  function preview(text = source, kind = format, fields = mapping) {
    try {
      setLessons(parseCourses(text, kind, semester || undefined, fields, zoneFor(data)));
      setExcluded([]);
      setError('');
    } catch (failure) {
      setLessons([]);
      setError(failure instanceof Error ? failure.message : '文件读取失败');
    }
  }
  const [reminder, setReminder] = useState(Number(data.preferences.courseReminderLeadMinutes ?? 15));
  const conflicts = courseConflicts(lessons, data);
  const selectedLessons = lessons.filter((_, index) => !excluded.includes(index));
  return (
    <section className="panel editor-fields">
      <div className="section-heading">
        <h2>课程导入</h2>
        <button className="secondary-button" onClick={onClose}>
          关闭
        </button>
      </div>
      <label className="field">
        <span>学期第一周开始日期</span>
        <input
          type="date"
          value={semester}
          onChange={(event) => {
            setSemester(event.target.value);
            setLessons([]);
          }}
        />
      </label>
      <label className="field">
        <span>课程文件</span>
        <input
          type="file"
          accept=".csv,.json,.ics"
          onChange={async (event) => {
            const file = event.target.files?.[0];
            event.target.value = '';
            if (!file) return;
            try {
              if (file.size > 5 * 1024 * 1024) throw new Error('课程文件超过 5MB');
              const text = await file.text(),
                kind = file.name.split('.').pop()?.toLowerCase() ?? '';
              setSource(text);
              setFormat(kind);
              setMapping({});
              setHeaders(kind === 'csv' ? (parseCSV(text.replace(/^\ufeff/, ''))[0] ?? []) : []);
              preview(text, kind, {});
            } catch (failure) {
              setLessons([]);
              setError(failure instanceof Error ? failure.message : '文件读取失败');
            }
          }}
        />
      </label>
      {!!headers.length && (
        <details>
          <summary>列映射</summary>
          {[
            ['title', '课程名称'],
            ['teacher', '教师'],
            ['location', '地点'],
            ['notes', '备注'],
            ['start', '开始时间'],
            ['end', '结束时间'],
            ['weekday', '星期'],
            ['startTime', '开始时刻'],
            ['endTime', '结束时刻'],
            ['startWeek', '起始周'],
            ['endWeek', '结束周'],
            ['parity', '单双周'],
          ].map(([key, label]) => (
            <label className="field" key={key}>
              <span>{label}</span>
              <Select
                value={mapping[key] ?? ''}
                onChange={(event) => {
                  setMapping({ ...mapping, [key]: event.target.value });
                  setLessons([]);
                }}
              >
                <option value="">自动匹配</option>
                {headers.map((header) => (
                  <option key={header} value={header}>
                    {header}
                  </option>
                ))}
              </Select>
            </label>
          ))}
        </details>
      )}
      {!!source && (
        <button className="secondary-button" onClick={() => preview()}>
          预览
        </button>
      )}
      {!!lessons.length && (
        <>
          <label className="field">
            <span>提前提醒（分钟）</span>
            <input
              type="number"
              min="0"
              max="10080"
              value={reminder}
              onChange={(event) => setReminder(Number(event.target.value))}
            />
          </label>
          {!!conflicts.length && (
            <label className="field">
              <span>冲突处理（{conflicts.length} 项）</span>
              <Select value={choice} onChange={(event) => setChoice(event.target.value as CourseChoice)}>
                <option value="keep">保留全部</option>
                <option value="skip">跳过冲突课程</option>
                <option value="replace">替换现有冲突日程</option>
              </Select>
            </label>
          )}
          <div className="course-preview">
            {lessons.map((lesson, index) => (
              <label className="attachment-row" key={`${lesson.start}-${index}`}>
                <input
                  type="checkbox"
                  checked={!excluded.includes(index)}
                  onChange={(event) =>
                    setExcluded(
                      event.target.checked
                        ? excluded.filter((value) => value !== index)
                        : [...excluded, index],
                    )
                  }
                />
                <span>
                  {lesson.title} ·{' '}
                  {new Date(lesson.start).toLocaleString('zh-CN', { timeZone: zoneFor(data) })} ·{' '}
                  {lesson.location}
                </span>
                {conflicts.some((conflict) => conflict.index === index) && <span>冲突</span>}
              </label>
            ))}
          </div>
          <button
            className="primary-button"
            disabled={!selectedLessons.length}
            onClick={() => {
              try {
                if (onSave(importCourses(data, selectedLessons, choice, reminder))) onClose();
                else setError('保存失败');
              } catch (failure) {
                setError(failure instanceof Error ? failure.message : '导入失败');
              }
            }}
          >
            导入 {selectedLessons.length} 个日程
          </button>
        </>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </section>
  );
}
