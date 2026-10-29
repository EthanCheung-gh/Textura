import { Icon } from '../../ui/icons';
import { IconButton } from '../../ui/IconButton';

interface EditPencilProps {
  /** `editTargetKey(...)` 的结果，结束时据此把焦点还给这支铅笔。 */
  target: string;
  /** 无障碍名称，例如「编辑目标标题」「编辑关键结果：NPS 42 → 60」。 */
  label: string;
  onClick: () => void;
}

/**
 * 渐进式编辑的入口：默认态只显示文本 + 这支小铅笔，点开才挂载输入控件。
 * `data-edit-target` 让父组件在结束编辑后把焦点还回来（键盘用户不丢位置）。
 */
export function EditPencil({ target, label, onClick }: EditPencilProps) {
  return (
    <IconButton
      label={label}
      size="sm"
      className="okr-edit-pencil"
      data-edit-target={target}
      onClick={onClick}
    >
      <Icon name="edit" size={13} />
    </IconButton>
  );
}
