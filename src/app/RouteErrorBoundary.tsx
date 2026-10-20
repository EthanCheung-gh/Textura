import { Component } from 'react';
import type { ErrorInfo, ReactNode } from 'react';
import { Button } from '../ui/Button';
import './RouteErrorBoundary.css';

interface RouteErrorBoundaryProps {
  children: ReactNode;
  resetKey: string;
  onBackToday: () => void;
  onReload: () => void;
  reloading?: boolean;
  onShowDataDir: () => void;
}

interface RouteErrorBoundaryState {
  error: Error | null;
}

/**
 * 路由视图错误边界：即使模块渲染崩溃，外壳（侧栏 / 顶栏）仍可用。
 * 关键词：getDerivedStateFromError + 可恢复动作，而不是整窗白屏。
 */
export class RouteErrorBoundary extends Component<RouteErrorBoundaryProps, RouteErrorBoundaryState> {
  state: RouteErrorBoundaryState = { error: null };

  static getDerivedStateFromError(error: unknown): RouteErrorBoundaryState {
    return { error: error instanceof Error ? error : new Error(String(error)) };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error('[textura] 视图渲染失败', error, info.componentStack);
  }

  componentDidUpdate(previous: RouteErrorBoundaryProps): void {
    if (previous.resetKey !== this.props.resetKey && this.state.error) {
      this.setState({ error: null });
    }
  }

  private handleBackToday = (): void => {
    this.setState({ error: null });
    this.props.onBackToday();
  };

  render(): ReactNode {
    const { error } = this.state;
    if (!error) return this.props.children;

    return (
      <div className="route-error" role="alert">
        <div className="route-error-eyebrow">视图渲染失败</div>
        <h2 className="route-error-title">这个视图暂时无法显示</h2>
        <p className="route-error-description">
          工作区数据仍在。可以返回今日、重新加载工作区，或查看数据目录后手动备份。
        </p>
        <pre className="route-error-detail">{error.message}</pre>
        <div className="route-error-actions">
          <Button variant="primary" size="sm" onClick={this.handleBackToday}>
            返回今日
          </Button>
          <Button
            variant="secondary"
            size="sm"
            onClick={this.props.onReload}
            disabled={this.props.reloading}
          >
            {this.props.reloading ? '正在保存并重新加载…' : '重新加载工作区'}
          </Button>
          <Button variant="ghost" size="sm" onClick={this.props.onShowDataDir}>
            查看数据目录
          </Button>
        </div>
      </div>
    );
  }
}
