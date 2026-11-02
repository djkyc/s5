import { CronJob, validateCronExpression } from "cron";

type CronHandler = () => void | Promise<void>;

interface CronTask {
  cron: string;
  description?: string;
  job: CronJob;
}

class CronManager {
  private tasks: Map<string, CronTask> = new Map();

  /**
   * 设置/添加一个 cron 任务
   * @param name 任务唯一标识
   * @param cron cron 表达式
   * @param handler 执行函数
   */
  set(name: string, cron: string, handler: CronHandler): void {
    if (this.tasks.has(name)) {
      throw new Error(`Cron task "${name}" already exists.`);
    }

    const validate = validateCronExpression(cron)
    if (!validate.valid) {
      console.log(`CronManager set new cronJob ${name} error while invalid cron`, validate.error);
      return;
    }

    const job = new CronJob(cron, () => {
      Promise.resolve(handler()).catch(console.error);
    });

    job.start();
    this.tasks.set(name, { cron, job });
  }

  /**
   * 删除一个任务
   */
  del(name: string): boolean {
    const task = this.tasks.get(name);
    if (!task) return false;
    task.job.stop();
    this.tasks.delete(name);
    return true;
  }

  /**
   * 列出所有任务
   */
  ls(raw?: boolean): string[] | Map<string, CronTask> {
    if (raw) {
      return this.tasks;
    }
    return Array.from(this.tasks.keys());
  }

  /**
   * 清空所有任务
   */
  clear(): void {
    for (const task of this.tasks.values()) {
      task.job.stop();
    }
    this.tasks.clear();
  }

  /**
   * 检查任务是否存在
   */
  has(name: string): boolean {
    return this.tasks.has(name);
  }
}

const cronManager = new CronManager();

export { cronManager };
