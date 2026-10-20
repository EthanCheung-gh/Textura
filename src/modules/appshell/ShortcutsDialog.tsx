// TODO(module): 由 appshell Worker 重写为与真实快捷键一致的帮助面板。
import { useWorkspace } from '../../core/store';
import { Modal } from '../../ui/Modal';

const SHORTCUTS: { keys: string; action: string }[] = [
  { keys: 'Ctrl / ⌘ + K', action: '打开命令面板' },
  { keys: 'C', action: '快速收集' },
  { keys: '?', action: '快捷键帮助' },
  { keys: 'Esc', action: '关闭弹层' },
  { keys: 'Ctrl / ⌘ + Z', action: '撤销' },
  { keys: 'Ctrl / ⌘ + Shift + Z', action: '重做' },
];

export function ShortcutsDialog() {
  const open = useWorkspace((state) => state.ui.shortcutsOpen);
  const setUi = useWorkspace((state) => state.setUi);

  return (
    <Modal open={open} onClose={() => setUi({ shortcutsOpen: false })} title="快捷键" width={420}>
      <dl style={{ display: 'grid', gridTemplateColumns: 'auto 1fr', gap: '10px 16px', margin: 0 }}>
        {SHORTCUTS.map((entry) => (
          <div key={entry.keys} style={{ display: 'contents' }}>
            <dt className="mono" style={{ fontSize: 12, color: 'var(--text-muted)' }}>
              {entry.keys}
            </dt>
            <dd style={{ margin: 0, fontSize: 13 }}>{entry.action}</dd>
          </div>
        ))}
      </dl>
      <p className="placeholder-note">TODO(module): src/modules/appshell/ShortcutsDialog.tsx</p>
    </Modal>
  );
}
