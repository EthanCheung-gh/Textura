import type { Workspace } from '../../core/model';
import { Badge } from '../../ui/Badge';
import { Button } from '../../ui/Button';
import { EmptyState } from '../../ui/EmptyState';
import { Icon } from '../../ui/icons';
import { Progress } from '../../ui/Progress';
import { projectHealth } from './gtdLogic';
import { createNextActionForProject } from './gtdMutations';

export interface ProjectPanelProps {
  workspace: Workspace;
  onFocusNext: () => void;
}

/** 项目健康度：进度、未完成动作数、停滞判定与一键补下一步。 */
export function ProjectPanel({ workspace, onFocusNext }: ProjectPanelProps) {
  const projects = projectHealth(workspace);

  if (projects.length === 0) {
    return (
      <div className="gtd-section-body gtd-empty-body">
        <EmptyState
          icon={<Icon name="folder" size={20} />}
          title="还没有项目"
          description="把需要多个动作完成的结果升级为项目。"
          compact
        />
      </div>
    );
  }

  return (
    <div className="gtd-projects">
      {projects.map((entry) => {
        const { project, total, done, open, progress, stuck } = entry;
        return (
          <div key={project.id} className="gtd-project">
            <div className="gtd-project-head">
              <span className="gtd-project-name">{project.title}</span>
              {stuck ? (
                <Badge tone="danger" dot>
                  停滞
                </Badge>
              ) : (
                <Badge tone="ok" dot>
                  健康
                </Badge>
              )}
            </div>
            <div className="gtd-project-stats">
              <span>
                {done} / {total} 动作完成
              </span>
              <span className="gtd-project-open">{open} 未完成</span>
              <span className="gtd-project-percent">{progress}%</span>
            </div>
            <Progress
              value={progress}
              size="sm"
              tone={stuck ? 'danger' : progress >= 100 ? 'ok' : 'accent'}
              ariaLabel={`${project.title} 完成度`}
            />
            <div className="gtd-project-actions">
              {stuck ? (
                <Button
                  variant="secondary"
                  size="sm"
                  iconLeft={<Icon name="plus" size={13} />}
                  onClick={() => createNextActionForProject(project)}
                >
                  新建下一步
                </Button>
              ) : null}
              <Button variant="ghost" size="sm" onClick={onFocusNext}>
                查看下一步
              </Button>
            </div>
          </div>
        );
      })}
    </div>
  );
}
