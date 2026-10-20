import { useEffect, useMemo, useState } from 'react';
import { currentQuarter } from '../../core/utils';
import { Button } from '../../ui/Button';
import { Select } from '../../ui/Field';
import { Modal } from '../../ui/Modal';
import { Segmented } from '../../ui/Segmented';
import { quarterLabel } from './okrMath';

type QuarterPart = 'Q1' | 'Q2' | 'Q3' | 'Q4';

const QUARTER_OPTIONS: { value: QuarterPart; label: string }[] = [
  { value: 'Q1', label: 'Q1' },
  { value: 'Q2', label: 'Q2' },
  { value: 'Q3', label: 'Q3' },
  { value: 'Q4', label: 'Q4' },
];

function parsePeriod(period: string): { year: number; quarter: QuarterPart } {
  const match = /^(\d{4})-Q([1-4])$/.exec(period);
  if (!match) {
    const fallback = currentQuarter();
    return {
      year: Number(fallback.slice(0, 4)),
      quarter: (`Q${fallback.slice(-1)}` as QuarterPart),
    };
  }
  return { year: Number(match[1]), quarter: `Q${match[2]}` as QuarterPart };
}

interface QuarterDialogProps {
  open: boolean;
  title: string;
  description?: string;
  confirmLabel: string;
  initialPeriod: string;
  onConfirm: (period: string) => void;
  onClose: () => void;
}

/** 年份 + 季度选择器，用于新建季度 / 移动目标 / 复制目标。 */
export function QuarterDialog({
  open,
  title,
  description,
  confirmLabel,
  initialPeriod,
  onConfirm,
  onClose,
}: QuarterDialogProps) {
  const [year, setYear] = useState(() => parsePeriod(initialPeriod).year);
  const [quarter, setQuarter] = useState<QuarterPart>(() => parsePeriod(initialPeriod).quarter);

  useEffect(() => {
    if (!open) return;
    const parsed = parsePeriod(initialPeriod);
    setYear(parsed.year);
    setQuarter(parsed.quarter);
  }, [open, initialPeriod]);

  const years = useMemo(() => {
    const base = new Date().getFullYear();
    const set = new Set<number>([base - 1, base, base + 1, base + 2, year]);
    return [...set].sort((a, b) => a - b);
  }, [year]);

  const value = `${year}-${quarter}`;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={title}
      description={description}
      width={460}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            取消
          </Button>
          <Button variant="primary" onClick={() => onConfirm(value)}>
            {confirmLabel}
          </Button>
        </>
      }
    >
      <div className="okr-quarter-picker">
        <label className="okr-quarter-field">
          <span>年份</span>
          <Select
            options={years.map((item) => ({ value: String(item), label: `${item}` }))}
            value={String(year)}
            aria-label="选择年份"
            onChange={(event) => setYear(Number(event.target.value))}
          />
        </label>
        <div className="okr-quarter-field">
          <span>季度</span>
          <Segmented<QuarterPart>
            options={QUARTER_OPTIONS}
            value={quarter}
            onChange={setQuarter}
            ariaLabel="选择季度"
          />
        </div>
      </div>
      <p className="okr-dialog-hint">目标周期将设为 {quarterLabel(value)}。</p>
    </Modal>
  );
}
