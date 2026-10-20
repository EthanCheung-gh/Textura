/**
 * 全局快捷键挂钩：每个组件只声明自己负责的按键，避免重复处理。
 *
 * - ⌘/Ctrl+K        命令面板（可含 Shift 之外的组合）
 * - ⌘/Ctrl+N        快速收集（同时接受 ⌘/Ctrl+Shift+N）
 * - ⌘/Ctrl+Z        撤销（输入框内交给浏览器原生撤销）
 * - ⌘/Ctrl+Shift+Z  重做
 * - ?（Shift+/）    快捷键帮助（输入框聚焦时不触发）
 * - Esc             关闭（Modal 自身也会处理，这里作为兜底）
 */
import { useEffect, useRef } from 'react';

export interface GlobalHotkeyHandlers {
  onTogglePalette?: () => void;
  onOpenCapture?: () => void;
  onOpenShortcuts?: () => void;
  onUndo?: () => void;
  onRedo?: () => void;
  onEscape?: () => void;
}

export function isEditableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  const tag = target.tagName;
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true;
  return target.isContentEditable;
}

export function useGlobalHotkeys(handlers: GlobalHotkeyHandlers): void {
  const handlersRef = useRef(handlers);
  handlersRef.current = handlers;

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const current = handlersRef.current;
      const modifier = event.metaKey || event.ctrlKey;
      const editable = isEditableTarget(event.target);

      if (modifier && !event.altKey) {
        const key = event.key.toLowerCase();
        if (key === 'k' && !event.shiftKey && current.onTogglePalette) {
          event.preventDefault();
          current.onTogglePalette();
          return;
        }
        if (key === 'n' && current.onOpenCapture) {
          event.preventDefault();
          current.onOpenCapture();
          return;
        }
        if (key === 'z' && !editable) {
          if (event.shiftKey && current.onRedo) {
            event.preventDefault();
            current.onRedo();
            return;
          }
          if (!event.shiftKey && current.onUndo) {
            event.preventDefault();
            current.onUndo();
            return;
          }
        }
      }

      if (event.key === 'Escape' && current.onEscape) {
        current.onEscape();
        return;
      }

      const questionMark = event.key === '?' || (event.shiftKey && event.key === '/');
      if (questionMark && !modifier && !event.altKey && !editable && current.onOpenShortcuts) {
        event.preventDefault();
        current.onOpenShortcuts();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);
}
