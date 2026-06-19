const templates = {
  git: {
    title: "git 常用说明",
    summary: "git 用于版本控制；最常见动作是查看状态、暂存、提交、拉取和推送。",
    usage: [
      "`git status` 查看工作区状态。",
      "`git add <文件路径>` 暂存文件。",
      "`git commit -m \"<说明>\"` 创建提交。",
      "`git pull` 拉取远端更新，`git push` 推送本地提交。"
    ],
    examples: [
      { command: "git status -sb", purpose: "用简洁格式查看当前分支和文件状态。" },
      { command: "git log --oneline -5", purpose: "查看最近 5 条提交。" }
    ],
    risks: ["`git reset --hard`、`git clean -fd` 会丢弃本地内容，执行前要确认。"],
    next_steps: ["如果要看具体改动，运行 `git diff`。"]
  },
  ssh: {
    title: "ssh 常用说明",
    summary: "ssh 用于登录远程服务器或建立端口转发连接。",
    usage: [
      "`ssh <用户名>@<主机>` 登录远程主机。",
      "`ssh -p <端口> <用户名>@<主机>` 指定端口登录。",
      "`ssh -i <私钥路径> <用户名>@<主机>` 指定私钥登录。"
    ],
    examples: [
      { command: "ssh <用户名>@<主机> -p <端口>", purpose: "使用指定端口连接服务器。" },
      { command: "ssh -L <本地端口>:127.0.0.1:<远端端口> <用户名>@<主机>", purpose: "把远端服务转发到本机访问。" }
    ],
    risks: ["不要把私钥、密码或 token 粘贴到公共输出里。"],
    next_steps: ["连接失败时先检查用户名、主机、端口、防火墙和密钥权限。"]
  },
  docker: {
    title: "docker 常用说明",
    summary: "docker 用于运行和管理容器、镜像、网络和数据卷。",
    usage: [
      "`docker ps` 查看运行中的容器。",
      "`docker ps -a` 查看所有容器。",
      "`docker logs <容器名或ID>` 查看日志。",
      "`docker exec -it <容器名或ID> sh` 进入容器 shell。"
    ],
    examples: [
      { command: "docker ps --format \"table {{.Names}}\\t{{.Status}}\\t{{.Ports}}\"", purpose: "以表格方式查看容器名称、状态和端口。" },
      { command: "docker compose up -d", purpose: "后台启动 compose 项目。" }
    ],
    risks: ["`docker rm`、`docker rmi`、`docker volume rm` 会删除资源，注意数据卷。"],
    next_steps: ["排查服务异常时通常先看 `docker ps` 和 `docker logs <容器名或ID>`。"]
  }
};

export function getLocalHelp({ mode, text, outputStyle }) {
  if (mode !== "explain") return null;
  if (String(outputStyle || "").toLowerCase() !== "brief") return null;
  const command = String(text || "").trim().split(/\s+/)[0]?.toLowerCase();
  const value = templates[command];
  if (!value) return null;
  return {
    confidence: "high",
    completion: "",
    ...value
  };
}
