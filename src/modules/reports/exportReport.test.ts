import { afterEach, describe, expect, it, vi } from 'vitest';
import type { Report } from '../../core/model';
import {
  copyReportMarkdown,
  downloadReportMarkdown,
  reportFileName,
  reportMarkdown,
} from './exportReport';

function makeReport(overrides: Partial<Report> = {}): Report {
  return {
    id: 'r1',
    kind: 'week',
    period: '2026-W44',
    title: '2026 年第 44 周报',
    author: '张三',
    status: 'draft',
    templateId: 'weekly-external',
    sections: [
      {
        key: 'overview',
        title: '本周概览',
        // draft.ts 产出的正文自带 `### 小标题`
        body: '### 本周概览\n- 完成：3 项\n- 风险：1 项',
        origin: 'auto',
        updatedAt: '2026-11-01T09:00:00.000Z',
      },
      {
        key: 'support',
        title: '需要的支持',
        body: '- （待补充：需要哪些支持、决策或资源）',
        origin: 'manual',
        updatedAt: '2026-11-01T09:30:00.000Z',
      },
      { key: 'next', title: '下周计划', body: '', origin: 'auto', updatedAt: '2026-11-01T09:00:00.000Z' },
    ],
    generatedAt: '2026-11-01T09:00:00.000Z',
    finalizedAt: null,
    createdAt: '2026-11-01T09:00:00.000Z',
    updatedAt: '2026-11-01T09:30:00.000Z',
    ...overrides,
  };
}

/** 固定「生成时间」，避免用例依赖跑测时刻。 */
const NOW = new Date(2026, 10, 1, 20, 14);

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('reportMarkdown', () => {
  const markdown = reportMarkdown(makeReport(), NOW);
  const lines = markdown.split('\n');

  it('首行是标题，接着是期次 / 报告人 / 状态', () => {
    expect(lines[0]).toBe('# 2026 年第 44 周报');
    expect(markdown).toContain('- 期次：2026 年第 44 周（2026-10-26 ～ 2026-11-01）');
    expect(markdown).toContain('- 报告人：张三');
    expect(markdown).toContain('- 状态：草稿');
  });

  it('已有 `### 小标题` 的正文不重复加标题', () => {
    expect(markdown.match(/### 本周概览/g)).toHaveLength(1);
    expect(markdown).toContain('### 本周概览\n- 完成：3 项\n- 风险：1 项');
  });

  it('没有小标题的正文补 `### 模板标题`', () => {
    expect(markdown).toContain('### 需要的支持\n- （待补充：需要哪些支持、决策或资源）');
  });

  it('空正文的节整节跳过，不留孤立标题', () => {
    // makeReport 的 `next` 节 body 为空串
    expect(markdown).not.toContain('### 下周计划');
    // 段落之间不因为跳过而多出空行
    expect(markdown).not.toMatch(/\n{3,}/);
  });

  it('某节被「清空」后，导出既无该节标题也无该节正文', () => {
    const report = makeReport();
    const cleared = {
      ...report,
      sections: report.sections.map((section) =>
        section.key === 'overview' ? { ...section, body: '  \n ', origin: 'manual' as const } : section,
      ),
    };
    const text = reportMarkdown(cleared, NOW);

    expect(text).not.toContain('### 本周概览');
    expect(text).not.toContain('完成：3 项');
    expect(text).not.toContain('风险：1 项');
    // 其余有正文的节照旧输出
    expect(text).toContain('### 需要的支持');
    expect(text).not.toMatch(/\n{3,}/);
  });

  it('末尾带生成时间（本地时区 yyyy-MM-dd HH:mm）', () => {
    const tail = lines.slice(-4);
    expect(tail[0]).toBe('---');
    expect(tail[1]).toBe('');
    expect(tail[2]).toBe('生成时间：2026-11-01 20:14');
    expect(tail[3]).toBe('');
  });

  it('报告人未填写时给明确文案，定稿的报告额外写定稿时间', () => {
    const draftNoAuthor = reportMarkdown(makeReport({ author: '  ' }), NOW);
    expect(draftNoAuthor).toContain('- 报告人：未填写');

    // 用本地时间构造，避免断言依赖跑测机器的时区。
    const final = reportMarkdown(
      makeReport({
        status: 'final',
        finalizedAt: new Date(2026, 10, 2, 10, 5).toISOString(),
      }),
      NOW,
    );
    expect(final).toContain('- 状态：已定稿');
    expect(final).toContain('- 定稿时间：2026-11-02 10:05');
  });

  it('月 / 季报告的期次文案走 periodLabel，标题为空时用期次兜底', () => {
    const month = reportMarkdown(
      makeReport({ kind: 'month', period: '2026-11', title: '', templateId: 'monthly-external' }),
      NOW,
    );
    expect(month.split('\n')[0]).toBe('# 2026 年 11 月');
    expect(month).toContain('- 期次：2026 年 11 月（2026-11-01 ～ 2026-11-30）');

    const quarter = reportMarkdown(
      makeReport({ kind: 'quarter', period: '2026-Q4', title: 'Q4 对外汇报' }),
      NOW,
    );
    expect(quarter).toContain('# Q4 对外汇报');
    expect(quarter).toContain('- 期次：2026 年第四季度（2026-10-01 ～ 2026-12-31）');
  });
});

describe('reportFileName', () => {
  it('期次 + 粒度，标题不进文件名', () => {
    expect(reportFileName(makeReport())).toBe('2026-W44-周报.md');
    expect(reportFileName(makeReport({ kind: 'month', period: '2026-11' }))).toBe('2026-11-月报.md');
    expect(reportFileName(makeReport({ kind: 'quarter', period: '2026-Q4' }))).toBe('2026-Q4-季报.md');
  });
});

describe('copyReportMarkdown', () => {
  it('写剪贴板成功后 notify success 并返回 true', async () => {
    const written: string[] = [];
    vi.stubGlobal('navigator', {
      clipboard: { writeText: async (value: string) => void written.push(value) },
    });
    const notices: string[] = [];
    const ok = await copyReportMarkdown(
      makeReport(),
      (message, tone) => {
        notices.push(`${tone}:${message}`);
      },
      NOW,
    );

    expect(ok).toBe(true);
    expect(written[0]).toBe(reportMarkdown(makeReport(), NOW));
    expect(notices[0]).toBe('success:已复制 Markdown 到剪贴板');
  });

  it('剪贴板不可用时 notify error 并返回 false（不把异常抛给页面）', async () => {
    vi.stubGlobal('navigator', {});
    const notices: string[] = [];
    const ok = await copyReportMarkdown(
      makeReport(),
      (message, tone) => {
        notices.push(`${tone}:${message}`);
      },
      NOW,
    );

    expect(ok).toBe(false);
    expect(notices[0]).toContain('error:复制失败：当前环境不支持剪贴板');
    expect(notices[0]).toContain('下载 .md');
  });

  it('writeText 被拒绝（非安全上下文 / 无权限）时也走 error 分支', async () => {
    vi.stubGlobal('navigator', {
      clipboard: {
        writeText: async () => {
          throw new Error('NotAllowedError');
        },
      },
    });
    const notices: string[] = [];
    const ok = await copyReportMarkdown(
      makeReport(),
      (message, tone) => {
        notices.push(`${tone}:${message}`);
      },
      NOW,
    );
    expect(ok).toBe(false);
    expect(notices[0]).toBe('error:复制失败：NotAllowedError（可改用「下载 .md」）');
  });
});

describe('downloadReportMarkdown', () => {
  it('无 document 的环境（如 node）notify error 并提示改用复制', () => {
    const notices: string[] = [];
    const ok = downloadReportMarkdown(
      makeReport(),
      (message, tone) => {
        notices.push(`${tone}:${message}`);
      },
      NOW,
    );

    expect(ok).toBe(false);
    expect(notices[0]).toBe('error:下载失败：当前环境不支持文件下载，请改用「复制 Markdown」');
  });

  it('有 document 时用 Blob + <a download> 发起下载，并回收 objectURL', () => {
    const anchors: { href: string; download: string; rel: string; clicked: number }[] = [];
    const revoked: string[] = [];
    const scheduled: number[] = [];

    vi.stubGlobal('URL', {
      createObjectURL: () => 'blob:mock-url',
      revokeObjectURL: (url: string) => void revoked.push(url),
    });
    vi.stubGlobal('window', {
      setTimeout: (fn: () => void) => {
        scheduled.push(1);
        fn();
        return 1;
      },
    });
    vi.stubGlobal('document', {
      body: { appendChild: () => undefined },
      createElement: () => {
        const anchor = {
          href: '',
          download: '',
          rel: '',
          clicked: 0,
          click() {
            anchor.clicked += 1;
          },
          remove: () => undefined,
        };
        anchors.push(anchor);
        return anchor;
      },
    });

    const notices: string[] = [];
    const ok = downloadReportMarkdown(
      makeReport(),
      (message, tone) => {
        notices.push(`${tone}:${message}`);
      },
      NOW,
    );

    expect(ok).toBe(true);
    expect(anchors[0].href).toBe('blob:mock-url');
    expect(anchors[0].download).toBe('2026-W44-周报.md');
    expect(anchors[0].rel).toBe('noopener');
    expect(anchors[0].clicked).toBe(1);
    expect(scheduled).toHaveLength(1);
    expect(revoked).toEqual(['blob:mock-url']);
    expect(notices[0]).toContain('info:已发起 Markdown 下载');
    expect(notices[0]).toContain('复制');
  });
});
