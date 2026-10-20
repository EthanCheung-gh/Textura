import { useEffect, useRef, useState } from 'react';
import clsx from 'clsx';

interface EditableTitleProps {
  value: string;
  onCommit: (value: string) => void;
  /** 按钮的无障碍名称，例如「编辑目标标题：…」。 */
  ariaLabel: string;
  className?: string;
  inputClassName?: string;
}

/**
 * 点击标题进入行内编辑：Enter / 失焦保存，Esc 取消。
 * Enter 通过 blur 触发一次提交，避免 Enter + blur 重复写入历史。
 */
export function EditableTitle({
  value,
  onCommit,
  ariaLabel,
  className,
  inputClassName,
}: EditableTitleProps) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(value);
  const cancelled = useRef(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!editing) setDraft(value);
  }, [value, editing]);

  useEffect(() => {
    if (editing) {
      cancelled.current = false;
      inputRef.current?.focus();
      inputRef.current?.select();
    }
  }, [editing]);

  const commit = () => {
    if (cancelled.current) {
      cancelled.current = false;
      setEditing(false);
      return;
    }
    const next = draft.trim();
    setEditing(false);
    if (next && next !== value) onCommit(next);
    else setDraft(value);
  };

  if (!editing) {
    return (
      <button
        type="button"
        className={clsx('okr-editable-title', className)}
        aria-label={ariaLabel}
        title="点击编辑"
        onClick={() => setEditing(true)}
      >
        {value}
      </button>
    );
  }

  return (
    <input
      ref={inputRef}
      className={clsx('input', 'okr-editable-input', className, inputClassName)}
      value={draft}
      aria-label={ariaLabel}
      onChange={(event) => setDraft(event.target.value)}
      onBlur={commit}
      onKeyDown={(event) => {
        if (event.nativeEvent.isComposing) return;
        if (event.key === 'Enter') {
          event.preventDefault();
          event.currentTarget.blur();
        } else if (event.key === 'Escape') {
          event.preventDefault();
          cancelled.current = true;
          setDraft(value);
          event.currentTarget.blur();
        }
      }}
    />
  );
}
