import { useCallback } from 'react';
import { useWorkspace } from '../../core/store';
import { Modal } from '../../ui/Modal';
import { useGlobalHotkeys } from './useGlobalHotkeys';
import './appshell.css';

interface ShortcutEntry {
  keys: string[];
  action: string;
}

interface ShortcutGroup {
  id: string;
  title: string;
  description: string;
  items: ShortcutEntry[];
}

/** 只列出已实现的快捷键；由其它视图提供的会注明生效范围。 */
const GROUPS: ShortcutGroup[] = [
  {
    id: 'global',
    title: '全局',
    description: '任何视图下都可用',
    items: [
      { keys: ['⌘/Ctrl', 'K'], action: '打开 / 关闭命令面板' },
      { keys: ['⌘/Ctrl', 'N'], action: '打开快速收集（同时支持 ⌘/Ctrl + ⇧ + N）' },
      { keys: ['⌘/Ctrl', 'Z'], action: '撤销上一次工作区修改' },
      { keys: ['⌘/Ctrl', '⇧', 'Z'], action: '重做' },
      { keys: ['?'], action: '打开快捷键帮助（Shift + /）' },
      { keys: ['Esc'], action: '关闭当前弹层' },
    ],
  },
  {
    id: 'palette',
    title: '命令面板',
    description: '⌘/Ctrl + K 唤出',
    items: [
      { keys: ['↑', '↓'], action: '移动高亮项' },
      { keys: ['Enter'], action: '执行选中命令 / 打开条目' },
      { keys: ['Tab'], action: '跳到下一个分组（⇧ + Tab 反向）' },
      { keys: ['Esc'], action: '关闭面板' },
    ],
  },
  {
    id: 'capture',
    title: '快速收集',
    description: '⌘/Ctrl + N 唤出，收集后保持打开以便连续录入',
    items: [
      { keys: ['Enter'], action: '收集并继续下一条' },
      { keys: ['⌘/Ctrl', 'Enter'], action: '收集并关闭' },
      { keys: ['Esc'], action: '关闭收集窗口' },
      { keys: ['#标签', '@场景'], action: '写入 tags 与 gtd.context' },
      { keys: ['!高能', '!低能'], action: '写入 gtd.energy' },
      { keys: ['/今天', '/明天', '/本周'], action: '写入 gantt.end 截止日期' },
    ],
  },
  {
    id: 'gtd',
    title: 'GTD',
    description: '在收集 / 澄清 / 下一步视图中生效',
    items: [
      { keys: ['↑', '↓'], action: '移动行高亮' },
      { keys: ['x'], action: '完成当前行动' },
      { keys: ['Enter'], action: '打开澄清流程' },
      { keys: ['⌘/Ctrl', 'Z'], action: '撤销（输入框内交给原生编辑）' },
    ],
  },
  {
    id: 'sop',
    title: 'SOP',
    description: '在 SOP 画布中生效',
    items: [
      { keys: ['Delete', 'Backspace'], action: '删除选中的节点或连线' },
      { keys: ['Esc'], action: '取消选中 / 退出运行 / 关闭分支选择' },
      { keys: ['⌘/Ctrl', 'Z'], action: '撤销画布操作' },
    ],
  },
  {
    id: 'gantt',
    title: '甘特',
    description: '在甘特视图中生效',
    items: [
      { keys: ['拖拽'], action: '调整任务条形，修改起止日期' },
      { keys: ['Esc'], action: '取消拖拽' },
      { keys: ['Enter', 'Space'], action: '选中当前任务（详情面板打开时同步）' },
    ],
  },
];

export function ShortcutsDialog() {
  const open = useWorkspace((state) => state.ui.shortcutsOpen);

  const toggleShortcuts = useCallback(() => {
    const state = useWorkspace.getState();
    const next = !state.ui.shortcutsOpen;
    state.setUi({
      shortcutsOpen: next,
      ...(next ? { paletteOpen: false, quickCaptureOpen: false } : {}),
    });
  }, []);

  useGlobalHotkeys({
    onOpenShortcuts: toggleShortcuts,
    onEscape: () => {
      const state = useWorkspace.getState();
      if (state.ui.shortcutsOpen) state.setUi({ shortcutsOpen: false });
    },
  });

  return (
    <Modal
      open={open}
      onClose={() => useWorkspace.getState().setUi({ shortcutsOpen: false })}
      title="快捷键"
      description="当前版本已生效的键盘操作，按视图分组。"
      width={600}
    >
      <div className="shortcuts">
        {GROUPS.map((group) => (
          <section
            className="shortcut-group"
            key={group.id}
            aria-labelledby={`shortcut-${group.id}`}
          >
            <h3 className="shortcut-group-title" id={`shortcut-${group.id}`}>
              {group.title}
            </h3>
            <p className="shortcut-group-desc">{group.description}</p>
            <table className="shortcut-table">
              <tbody>
                {group.items.map((item) => (
                  <tr key={`${group.id}-${item.action}`}>
                    <th scope="row">
                      <span className="shortcut-keys">
                        {item.keys.map((key) => (
                          <kbd className="shortcut-key" key={key}>
                            {key}
                          </kbd>
                        ))}
                      </span>
                    </th>
                    <td className="shortcut-action">{item.action}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>
        ))}
        <p className="shortcut-note">
          快捷键会避开输入框：在文本框中输入时，字母类快捷键不会触发；撤销 / 重做在输入框内交给浏览器原生行为。
        </p>
      </div>
    </Modal>
  );
}
