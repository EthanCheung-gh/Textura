import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import type { Energy } from '../../core/model';
import { useWorkspace } from '../../core/store';
import { formatDateKey } from '../../core/utils';
import { Button } from '../../ui/Button';
import { Icon } from '../../ui/icons';
import { IconButton } from '../../ui/IconButton';
import { Modal } from '../../ui/Modal';
import { parseCapture } from './captureParser';
import { useGlobalHotkeys } from './useGlobalHotkeys';
import './appshell.css';

const ENERGY_LABELS: Record<Energy, string> = {
  high: '高能',
  medium: '中能',
  low: '低能',
};

interface CapturedEntry {
  id: string;
  title: string;
  tags: string[];
  context: string | null;
  energy: Energy | null;
  date: string | null;
}

export function QuickCapture() {
  const open = useWorkspace((state) => state.ui.quickCaptureOpen);
  const deleteItems = useWorkspace((state) => state.deleteItems);
  const notify = useWorkspace((state) => state.notify);

  const [value, setValue] = useState('');
  const [session, setSession] = useState<CapturedEntry[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);

  const parsed = useMemo(() => parseCapture(value), [value]);

  const openCapture = useCallback(() => {
    const state = useWorkspace.getState();
    state.setUi({ quickCaptureOpen: true, paletteOpen: false, shortcutsOpen: false });
  }, []);

  const close = useCallback(() => {
    useWorkspace.getState().setUi({ quickCaptureOpen: false });
  }, []);

  useGlobalHotkeys({
    onOpenCapture: openCapture,
    onEscape: () => {
      const state = useWorkspace.getState();
      if (state.ui.quickCaptureOpen) state.setUi({ quickCaptureOpen: false });
    },
  });

  useEffect(() => {
    if (!open) setValue('');
  }, [open]);

  const submit = (closeAfter: boolean) => {
    const parsedValue = parseCapture(value);
    if (!parsedValue.hasContent) return;
    const item = useWorkspace.getState().createItem({
      kind: 'action',
      title: parsedValue.title,
      status: 'inbox',
      tags: parsedValue.tags,
      gtd: {
        clarified: false,
        context: parsedValue.context ?? undefined,
        energy: parsedValue.energy ?? undefined,
      },
      gantt: { end: parsedValue.date },
    });
    setSession((previous) => [
      {
        id: item.id,
        title: parsedValue.title,
        tags: parsedValue.tags,
        context: parsedValue.context,
        energy: parsedValue.energy,
        date: parsedValue.date,
      },
      ...previous,
    ]);
    setValue('');
    notify(`已收集「${parsedValue.title}」`, 'success');
    if (closeAfter) {
      close();
    } else {
      inputRef.current?.focus();
    }
  };

  const undoLast = () => {
    const last = session[0];
    if (!last) return;
    deleteItems([last.id]);
    setSession((previous) => previous.slice(1));
    notify(`已撤销「${last.title}」`, 'info');
    inputRef.current?.focus();
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.nativeEvent.isComposing) return;
    if (event.key !== 'Enter') return;
    event.preventDefault();
    submit(event.metaKey || event.ctrlKey);
  };

  const hasPreview =
    parsed.tags.length > 0 || parsed.context !== null || parsed.energy !== null || parsed.date !== null;

  return (
    <Modal
      open={open}
      onClose={close}
      title="收集到 GTD 收件箱"
      description="先记录，稍后再澄清。Enter 连续收集，⌘/Ctrl + Enter 收集并关闭。"
      width={560}
      initialFocusRef={inputRef}
      footer={
        <>
          <span className="capture-footer-hint">
            <kbd className="capture-kbd">Enter</kbd> 继续收集
          </span>
          <Button variant="ghost" size="sm" onClick={close}>
            关闭
          </Button>
          <Button
            variant="secondary"
            size="sm"
            onClick={() => submit(true)}
            disabled={!parsed.hasContent}
          >
            收集并关闭
          </Button>
          <Button
            variant="primary"
            size="sm"
            iconLeft={<Icon name="plus" size={14} />}
            onClick={() => submit(false)}
            disabled={!parsed.hasContent}
          >
            收集
          </Button>
        </>
      }
    >
      <div className="capture">
        <label className="capture-label" htmlFor="quick-capture-input">
          收集什么？
        </label>
        <input
          ref={inputRef}
          id="quick-capture-input"
          className="input capture-input"
          type="text"
          value={value}
          placeholder="例如：给财务回电确认发票抬头 #财务 @电话 !低能 /明天"
          aria-describedby="capture-syntax"
          autoComplete="off"
          onChange={(event) => setValue(event.target.value)}
          onKeyDown={handleKeyDown}
        />

        <div className="capture-chips" aria-live="polite">
          {hasPreview ? <span className="capture-chips-label">解析预览</span> : null}
          {parsed.tags.map((tag) => (
            <span className="capture-chip" data-tone="accent" key={`tag-${tag}`}>
              <Icon name="tag" size={11} />#{tag}
            </span>
          ))}
          {parsed.context ? (
            <span className="capture-chip" data-tone="info">
              @{parsed.context}
            </span>
          ) : null}
          {parsed.energy ? (
            <span className="capture-chip" data-tone="warn">
              {ENERGY_LABELS[parsed.energy]}
            </span>
          ) : null}
          {parsed.date ? (
            <span className="capture-chip" data-tone="ok">
              <Icon name="calendar" size={11} />
              {formatDateKey(parsed.date, 'MM/dd')} 到期
            </span>
          ) : null}
        </div>

        <p className="capture-hints" id="capture-syntax">
          <code>#标签</code> 打标签 · <code>@场景</code> 采上下文 · <code>!高能</code> /{' '}
          <code>!低能</code> 标能量 · <code>/今天</code> <code>/明天</code> <code>/本周</code>{' '}
          设截止日期。多个标签用空格分隔。
        </p>

        <section className="capture-session" aria-label="本次会话已收集">
          <div className="capture-session-head">
            <span>
              本次会话已收集 {session.length} 条
              {session.length > 0 ? '（保存在收件箱）' : ''}
            </span>
            {session.length > 0 ? (
              <IconButton
                label="撤销最后一条收集"
                size="sm"
                variant="ghost"
                onClick={undoLast}
              >
                <Icon name="trash" size={14} />
              </IconButton>
            ) : null}
          </div>
          {session.length === 0 ? (
            <p className="capture-session-empty">
              还没有收集内容。每按一次 Enter，就会在下方留下一条记录。
            </p>
          ) : (
            <ul className="capture-session-list">
              {session.map((entry) => (
                <li className="capture-session-row" key={entry.id}>
                  <span className="capture-session-title">{entry.title}</span>
                  {entry.tags.length > 0 ? (
                    <span className="capture-session-meta">
                      {entry.tags.map((tag) => `#${tag}`).join(' ')}
                    </span>
                  ) : null}
                  {entry.context ? (
                    <span className="capture-session-meta">@{entry.context}</span>
                  ) : null}
                  {entry.energy ? (
                    <span className="capture-session-meta">{ENERGY_LABELS[entry.energy]}</span>
                  ) : null}
                  {entry.date ? (
                    <span className="capture-session-meta">
                      {formatDateKey(entry.date, 'MM/dd')}
                    </span>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </Modal>
  );
}
