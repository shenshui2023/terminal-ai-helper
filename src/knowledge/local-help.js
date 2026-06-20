const templates = {
  git: {
    title: "git 常用说明",
    summary: "git 用于版本控制，最常见动作是查看状态、暂存、提交、拉取和推送。",
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
      { command: "docker ps --format \"table {{.Names}}\\t{{.Status}}\\t{{.Ports}}\"", purpose: "以表格方式查看容器名、状态和端口。" },
      { command: "docker compose up -d", purpose: "后台启动 compose 项目。" }
    ],
    risks: ["`docker rm`、`docker rmi`、`docker volume rm` 会删除资源，注意数据卷。"],
    next_steps: ["排查服务异常时通常先看 `docker ps` 和 `docker logs <容器名或ID>`。"]
  },
  npm: {
    title: "npm 常用说明",
    summary: "npm 用于管理 Node.js 项目依赖和脚本。",
    usage: [
      "`npm install` 安装项目依赖。",
      "`npm run <脚本名>` 执行 package.json 中的脚本。",
      "`npm outdated` 查看过期依赖。"
    ],
    examples: [
      { command: "npm run dev", purpose: "启动开发脚本。" },
      { command: "npm test", purpose: "运行项目测试。" }
    ],
    risks: ["安装陌生包前注意来源，避免执行不可信 postinstall 脚本。"],
    next_steps: ["不确定有哪些脚本时查看 `package.json` 的 scripts 字段。"]
  },
  python: {
    title: "python 常用说明",
    summary: "python 用于运行脚本、创建虚拟环境和管理 Python 工具链。",
    usage: [
      "`python <脚本.py>` 运行脚本。",
      "`python -m venv .venv` 创建虚拟环境。",
      "`python -m pip install <包名>` 安装包。"
    ],
    examples: [
      { command: "python -m pytest", purpose: "运行 pytest 测试。" },
      { command: "python -m pip list", purpose: "查看当前环境已安装的包。" }
    ],
    risks: ["确认当前解释器和虚拟环境，避免把包装到错误环境。"],
    next_steps: ["先运行 `python --version` 和 `python -m pip --version` 确认环境。"]
  },
  java: {
    title: "java 常用说明",
    summary: "java 用于运行 JVM 程序，javac 用于编译 Java 源码。",
    usage: [
      "`java -version` 查看运行时版本。",
      "`javac <文件.java>` 编译源码。",
      "`java -jar <文件.jar>` 运行 jar 包。"
    ],
    examples: [
      { command: "java -version", purpose: "确认当前 Java 版本。" },
      { command: "java -jar <文件.jar>", purpose: "运行可执行 jar。" }
    ],
    risks: ["不同项目可能要求不同 JDK 版本，注意 JAVA_HOME 和 PATH。"],
    next_steps: ["版本不对时先检查 `where java` 和 `echo %JAVA_HOME%`。"]
  },
  adb: {
    title: "adb 常用说明",
    summary: "adb 用于连接和调试 Android 设备。",
    usage: [
      "`adb devices` 查看已连接设备。",
      "`adb shell` 进入设备 shell。",
      "`adb logcat` 查看设备日志。",
      "`adb install <应用.apk>` 安装 APK。"
    ],
    examples: [
      { command: "adb devices", purpose: "确认设备是否被电脑识别。" },
      { command: "adb reverse tcp:<端口> tcp:<端口>", purpose: "把设备端口反向映射到电脑，常用于调试。" }
    ],
    risks: ["安装、卸载和 shell 操作会影响设备状态，操作前确认目标设备。"],
    next_steps: ["设备不显示时检查 USB 调试、数据线、驱动和授权弹窗。"]
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
