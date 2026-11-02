import { Plugin } from "@utils/pluginBase";
import { AliasDB } from "@utils/aliasDB";
import { Api } from "telegram";
import { loadPlugins } from "@utils/pluginManager";
import { getPrefixes, getPluginEntry } from "@utils/pluginManager";

const prefixes = getPrefixes();
const mainPrefix = prefixes[0];

async function setAlias(args: string[], msg: Api.Message) {
  const final = args[1];
  const original = args[2];
  const pluginEntry = getPluginEntry(original);
  if (!pluginEntry) {
    await msg.edit({ text: `没找到${original}该原始命令，不保存该重定向` });
    await msg.deleteWithDelay(5000);
    return;
  }
  if (pluginEntry?.original) {
    await msg.edit({ text: "不应该对重定向的命令再次重定向" });
    await msg.deleteWithDelay(5000);
    return;
  }
  const db = new AliasDB();
  db.set(final, original);
  db.close();
  loadPlugins();
  await msg.edit({
    text: `插件命令重命名成功，${final} -> ${original}`,
  });
}

async function delAlias(args: string[], msg: Api.Message) {
  const db = new AliasDB();
  const success = db.del(args[1]);
  db.close();
  if (success) {
    await msg.edit({
      text: `删除 ${args[1]} 重命名成功`,
    });
    loadPlugins();
  } else {
    await msg.edit({
      text: `删除 ${args[1]} 重命名失败, 请检查命令是否存在`,
    });
  }
}

async function listAlias(args: string[], msg: Api.Message) {
  const db = new AliasDB();
  const result = db.list();
  db.close();
  const text = result
    .map(({ original, final }) => `${original} -> ${final}`)
    .join("\n");
  await msg.edit({ text: "重命名列表：\n" + text });
}

class AliasPlugin extends Plugin {
  description: string = `插件命名重命名
<code>${mainPrefix}alias set a b</code> - 即 使用别名 <code>a</code> 可以执行原始命令 <code>b</code>; 原始命令 <code>b</code> 可以有多个不重复的别名
<code>${mainPrefix}alias del a</code>
<code>${mainPrefix}alias ls</code>`;
  cmdHandlers: Record<string, (msg: Api.Message) => Promise<void>> = {
    alias: async (msg) => {
      const [, ...args] = msg.message.split(" ");
      if (args.length == 0) {
        await msg.edit({
          text: "不知道你要干什么！",
        });
      }
      const cmd = args[0];
      if (cmd == "set") {
        await setAlias(args, msg);
      } else if (cmd == "del") {
        await delAlias(args, msg);
      } else if (cmd == "ls" || cmd == "list") {
        await listAlias(args, msg);
      }
    },
  };
}

export default new AliasPlugin();
