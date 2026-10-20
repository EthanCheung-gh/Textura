import { useEffect, useState } from 'react';
import type { KeyboardEvent as ReactKeyboardEvent } from 'react';

export interface RowKeyboardOptions {
  ids: string[];
  onDone?: (id: string) => void;
  onEnter?: (id: string) => void;
}

export interface RowKeyboardState {
  activeId: string | null;
  setActiveId: (id: string | null) => void;
  onKeyDown: (event: ReactKeyboardEvent<HTMLElement>) => void;
}

/**
 * 列表键盘导航：↑/↓ 选中，x 完成，Enter 打开澄清。
 * 输入框 / 文本域 / 下拉框内的按键不拦截，避免破坏行内编辑。
 */
export function useRowKeyboard({ ids, onDone, onEnter }: RowKeyboardOptions): RowKeyboardState {
  const [activeId, setActiveId] = useState<string | null>(ids[0] ?? null);
  const idKey = ids.join('\u0000');

  useEffect(() => {
    setActiveId((current) => {
      if (current && ids.includes(current)) return current;
      return ids[0] ?? null;
    });
  }, [idKey]); // eslint-disable-line react-hooks/exhaustive-deps

  const move = (delta: number) => {
    if (ids.length === 0) return;
    const currentIndex = activeId ? ids.indexOf(activeId) : -1;
    const nextIndex = currentIndex < 0 ? 0 : (currentIndex + delta + ids.length) % ids.length;
    const nextId = ids[nextIndex];
    setActiveId(nextId);
    // 只有键盘移动时滚动到可视区，避免初次渲染把整页滚走。
    window.requestAnimationFrame(() => {
      document
        .querySelector<HTMLElement>(`[data-row-id="${cssEscape(nextId)}"]`)
        ?.scrollIntoView({ block: 'nearest' });
    });
  };

  const onKeyDown = (event: ReactKeyboardEvent<HTMLElement>) => {
    const target = event.target as HTMLElement;
    const tag = target.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target.isContentEditable) return;

    if (event.key === 'ArrowDown') {
      event.preventDefault();
      move(1);
      return;
    }
    if (event.key === 'ArrowUp') {
      event.preventDefault();
      move(-1);
      return;
    }
    if ((event.key === 'x' || event.key === 'X') && !event.metaKey && !event.ctrlKey && !event.altKey) {
      if (activeId && onDone) {
        event.preventDefault();
        onDone(activeId);
      }
      return;
    }
    if (event.key === 'Enter' && activeId && onEnter && tag !== 'BUTTON') {
      event.preventDefault();
      onEnter(activeId);
    }
  };

  return { activeId, setActiveId, onKeyDown };
}

function cssEscape(value: string): string {
  if (typeof CSS !== 'undefined' && typeof CSS.escape === 'function') return CSS.escape(value);
  return value.replace(/["\\]/g, '\\$&');
}
