import { exec } from "child_process";
import { promisify } from "util";
import { Plugin } from "@utils/pluginBase";
import { Api } from "telegram";

const execAsync = promisify(exec);

async function handleExec(params: { msg: Api.Message; shellCommand: string }) {
  const { msg, shellCommand } = params;
  try {
    const { stdout, stderr } = await execAsync(shellCommand);
    let text = `shell 输出：\n${stdout}`;
    if (stderr) {
      text += `\n\nshell 错误：\n${stderr}`;
    }
    await msg.edit({ text });
  } catch (error: any) {
    await msg.edit({
      text: `运行 shell 错误：${error}`,
    });
  }
}

class ExecPlugin extends Plugin {
  description: string = `运行 shell 命令`;
  cmdHandlers: Record<string, (msg: Api.Message) => Promise<void>> = {
    exec: async (msg) => {
      const shellCommand = msg.message.slice(1).replace(/^\S+\s+/, ""); // 因为用户可能会更改重定向命令 用正则可能更稳妥
      await handleExec({ msg, shellCommand });
    },
  };
}

export default new ExecPlugin();
