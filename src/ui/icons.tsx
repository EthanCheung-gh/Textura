/**
 * 内联 SVG 图标集（stroke 风格，24x24 网格）。
 * 用法：<Icon name="target" size={16} />；装饰性图标自动 aria-hidden。
 */
import type { ReactNode, SVGProps } from 'react';

export type IconName =
  | 'folder'
  | 'home'
  | 'target'
  | 'inbox'
  | 'timeline'
  | 'workflow'
  | 'search'
  | 'plus'
  | 'chevron-left'
  | 'chevron-right'
  | 'chevron-down'
  | 'close'
  | 'settings'
  | 'sun'
  | 'moon'
  | 'check'
  | 'x'
  | 'play'
  | 'grip'
  | 'zoom-in'
  | 'zoom-out'
  | 'link'
  | 'calendar'
  | 'calendar-grid'
  | 'tag'
  | 'flag'
  | 'clock'
  | 'trash'
  | 'edit'
  | 'more';

const PATHS: Record<IconName, ReactNode> = {
  folder: <path d="M3 7.5A2.5 2.5 0 0 1 5.5 5h3.2l2 2.2h7.8A2.5 2.5 0 0 1 21 9.7v7.8A2.5 2.5 0 0 1 18.5 20h-13A2.5 2.5 0 0 1 3 17.5z" />,
  home: (
    <>
      <path d="M3.5 10.5 12 3.5l8.5 7" />
      <path d="M5.5 9.5V20h13V9.5" />
      <path d="M9.5 20v-5.5h5V20" />
    </>
  ),
  target: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <circle cx="12" cy="12" r="4.5" />
      <circle cx="12" cy="12" r="1" fill="currentColor" stroke="none" />
    </>
  ),
  inbox: (
    <>
      <path d="M3.5 13.5 6 6.5A2 2 0 0 1 7.9 5h8.2a2 2 0 0 1 1.9 1.5l2.5 7" />
      <path d="M3.5 13.5h4l1.6 2.6h5.8l1.6-2.6h4v4A2.5 2.5 0 0 1 18 20H6a2.5 2.5 0 0 1-2.5-2.5z" />
    </>
  ),
  timeline: (
    <>
      <path d="M3 4v16" />
      <path d="M6 7h9" />
      <path d="M9 12h10" />
      <path d="M6 17h7" />
    </>
  ),
  workflow: (
    <>
      <rect x="3" y="4" width="6" height="5" rx="1.5" />
      <rect x="15" y="15" width="6" height="5" rx="1.5" />
      <rect x="15" y="4" width="6" height="5" rx="1.5" />
      <path d="M9 6.5h6M6 9v6a2 2 0 0 0 2 2h7" />
    </>
  ),
  search: (
    <>
      <circle cx="11" cy="11" r="7" />
      <path d="m16.5 16.5 4 4" />
    </>
  ),
  plus: <path d="M12 5v14M5 12h14" />,
  'chevron-left': <path d="m14 6-6 6 6 6" />,
  'chevron-right': <path d="m10 6 6 6-6 6" />,
  'chevron-down': <path d="m6 10 6 6 6-6" />,
  close: <path d="m6 6 12 12M18 6 6 18" />,
  settings: (
    <>
      <path d="M4 7h9M17 7h3M4 17h3M11 17h9" />
      <circle cx="15" cy="7" r="2" />
      <circle cx="9" cy="17" r="2" />
    </>
  ),
  sun: (
    <>
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4" />
    </>
  ),
  moon: <path d="M20.5 13.2A8.5 8.5 0 1 1 10.8 3.5a6.8 6.8 0 0 0 9.7 9.7z" />,
  check: <path d="m5 12.5 4.5 4.5L19 7" />,
  x: <path d="m6 6 12 12M18 6 6 18" />,
  play: <path d="M8 5.5 19 12 8 18.5z" />,
  grip: (
    <g fill="currentColor" stroke="none">
      <circle cx="9" cy="6" r="1.2" />
      <circle cx="15" cy="6" r="1.2" />
      <circle cx="9" cy="12" r="1.2" />
      <circle cx="15" cy="12" r="1.2" />
      <circle cx="9" cy="18" r="1.2" />
      <circle cx="15" cy="18" r="1.2" />
    </g>
  ),
  'zoom-in': (
    <>
      <circle cx="11" cy="11" r="7" />
      <path d="m16.5 16.5 4 4M8 11h6M11 8v6" />
    </>
  ),
  'zoom-out': (
    <>
      <circle cx="11" cy="11" r="7" />
      <path d="m16.5 16.5 4 4M8 11h6" />
    </>
  ),
  link: (
    <>
      <path d="M10 13a4 4 0 0 0 5.7 0l2.6-2.6a4 4 0 0 0-5.7-5.7L11 6.3" />
      <path d="M14 11a4 4 0 0 0-5.7 0l-2.6 2.6a4 4 0 0 0 5.7 5.7l1.6-1.6" />
    </>
  ),
  calendar: (
    <>
      <rect x="3.5" y="5" width="17" height="15.5" rx="2" />
      <path d="M3.5 10h17M8 3.5V7M16 3.5V7" />
    </>
  ),
  'calendar-grid': (
    <>
      <rect x="3.5" y="4.5" width="17" height="16" rx="2" />
      <path d="M3.5 9.5h17M8 2.5V6M16 2.5V6" />
      <g fill="currentColor" stroke="none">
        <circle cx="8" cy="13.2" r="1" />
        <circle cx="12" cy="13.2" r="1" />
        <circle cx="16" cy="13.2" r="1" />
        <circle cx="8" cy="17" r="1" />
        <circle cx="12" cy="17" r="1" />
        <circle cx="16" cy="17" r="1" />
      </g>
    </>
  ),
  tag: (
    <>
      <path d="M20.3 13.3 13.3 20.3a2 2 0 0 1-2.8 0L3.5 13.3V3.5h9.8l7 7a2 2 0 0 1 0 2.8z" />
      <circle cx="7.8" cy="7.8" r="1.3" />
    </>
  ),
  flag: <path d="M6 21V4h11l-2.2 4L17 12H6" />,
  clock: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <path d="M12 7.5V12l3 2" />
    </>
  ),
  trash: (
    <>
      <path d="M4 7h16M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13" />
      <path d="M10 11v5M14 11v5" />
    </>
  ),
  edit: (
    <>
      <path d="M4 20h4L20 8l-4-4L4 16z" />
      <path d="m14.5 5.5 4 4" />
    </>
  ),
  more: (
    <g fill="currentColor" stroke="none">
      <circle cx="6" cy="12" r="1.4" />
      <circle cx="12" cy="12" r="1.4" />
      <circle cx="18" cy="12" r="1.4" />
    </g>
  ),
};

export interface IconProps extends Omit<SVGProps<SVGSVGElement>, 'name'> {
  name: IconName;
  size?: number;
}

export function Icon({ name, size = 18, ...rest }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      {...rest}
    >
      {PATHS[name]}
    </svg>
  );
}

export const ICON_NAMES = Object.keys(PATHS) as IconName[];
