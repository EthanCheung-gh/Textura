// TODO(module): 由 appshell Worker 重写为快速收集（全局快捷键 / 上下文 / 能量）。
import { useState } from 'react';
import { useWorkspace } from '../../core/store';
import { Button } from '../../ui/Button';
import { Field, TextInput } from '../../ui/Field';
import { Modal } from '../../ui/Modal';
import { Icon } from '../../ui/icons';

export function QuickCapture() {
  const open = useWorkspace((state) => state.ui.quickCaptureOpen);
  const setUi = useWorkspace((state) => state.setUi);
  const createItem = useWorkspace((state) => state.createItem);
  const notify = useWorkspace((state) => state.notify);
  const [title, setTitle] = useState('');

  const close = () => {
    setUi({ quickCaptureOpen: false });
    setTitle('');
  };

  const submit = () => {
    const trimmed = title.trim();
    if (!trimmed) return;
    createItem({ kind: 'action', title: trimmed, status: 'inbox', gtd: { clarified: false } });
    notify('已收集到收件箱', 'success');
    close();
  };

  return (
    <Modal
      open={open}
      onClose={close}
      title="快速收集"
      description="先记录，稍后再澄清。"
      footer={
        <>
          <Button variant="ghost" size="sm" onClick={close}>
            取消
          </Button>
          <Button variant="primary" size="sm" onClick={submit} disabled={!title.trim()}>
            收集
          </Button>
        </>
      }
    >
      <Field label="要记住什么？" htmlFor="quick-capture-title">
        <TextInput
          id="quick-capture-title"
          autoFocus
          value={title}
          placeholder="例如：给财务回电确认发票抬头"
          onChange={(event) => setTitle(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter') {
              event.preventDefault();
              submit();
            }
          }}
        />
      </Field>
      <p className="faint" style={{ marginTop: 'var(--space-3)', fontSize: 12 }}>
        <Icon name="inbox" size={13} /> 将创建为 action · status=inbox，并写入 gtd.capturedAt。
      </p>
    </Modal>
  );
}
