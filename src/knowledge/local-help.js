const templates = {
  git: {
    title: "git 常用说明",
    summary: "git 用于版本控制，最常见动作是查看状态、暂存、提交、拉取和推送。",
    usage: [
      "`git status` 查看工作区状态。",
      "`git add <文件路径>` 暂存文件。",
      "`git commit -m \"<说明>\"` 创建提交。",
      "`git pull` 拉取远端更新；`git push` 推送本地提交。"
    ],
    related_commands: [
      { command: "git diff", purpose: "查看未暂存改动。", when: "提交前确认改动内容。" },
      { command: "git log --oneline -5", purpose: "查看最近 5 条提交。", when: "确认当前分支历史。" }
    ],
    examples: [
      { command: "git status -sb", purpose: "用简洁格式查看当前分支和文件状态。" },
      { command: "git add <文件路径> && git commit -m \"<说明>\"", purpose: "暂存指定文件并提交。" }
    ],
    risks: ["`git reset --hard`、`git clean -fd` 会丢弃本地内容，执行前要确认。"],
    next_steps: ["如果要看具体改动，运行 `git diff`。"]
  },
  ssh: {
    title: "ssh 常用说明",
    summary: "ssh 用于登录远程服务器，也可建立端口转发连接。",
    usage: [
      "`ssh <用户名>@<主机>` 登录远程主机。",
      "`ssh -p <端口> <用户名>@<主机>` 指定端口登录。",
      "`ssh -i <私钥路径> <用户名>@<主机>` 指定私钥登录。"
    ],
    related_commands: [
      { command: "ssh -v <用户名>@<主机>", purpose: "输出连接调试日志。", when: "连接失败或认证失败时。" },
      { command: "ssh -L <本地端口>:127.0.0.1:<远端端口> <用户名>@<主机>", purpose: "把远端服务转发到本机访问。", when: "需要访问服务器内网服务时。" },
      { command: "scp <文件路径> <用户名>@<主机>:<远端路径>", purpose: "复制文件到服务器。", when: "需要上传脚本或配置时。" }
    ],
    examples: [
      { command: "ssh <用户名>@<主机> -p <端口>", purpose: "使用指定端口连接服务器。" },
      { command: "ssh -R 17888:127.0.0.1:17888 <用户名>@<主机>", purpose: "把服务器上的 17888 反向连接到本机 helper server。" }
    ],
    risks: ["不要把私钥、密码或 token 粘贴到公共输出里。"],
    next_steps: ["连接失败时先检查用户名、主机、端口、防火墙和密钥权限。"]
  },
  kube: {
    title: "Kubernetes 命令说明",
    summary: "`kube` 通常不是官方 kubectl 命令，可能是你本机/服务器上的别名；官方常用命令是 `kubectl`。",
    usage: [
      "`kubectl get <资源类型>` 查看资源列表。",
      "`kubectl get <资源类型> -n <命名空间>` 查看指定命名空间资源。",
      "`kubectl describe <资源类型>/<资源名> -n <命名空间>` 查看详细事件和状态。"
    ],
    related_commands: [
      { command: "kubectl get pods -A", purpose: "查看所有命名空间 Pod。", when: "先判断集群整体工作负载状态。" },
      { command: "kubectl get svc -A", purpose: "查看所有命名空间 Service。", when: "排查服务暴露、ClusterIP、NodePort、LoadBalancer。" },
      { command: "kubectl get endpoints -A", purpose: "查看 Service 是否有后端地址。", when: "Service 存在但访问不通时。" }
    ],
    examples: [
      { command: "kubectl get svc -A", purpose: "查看所有命名空间的 Service 列表。" },
      { command: "kubectl get svc -n <命名空间> -o wide", purpose: "查看指定命名空间 Service，并显示更多细节。" }
    ],
    risks: ["`delete`、`scale`、`apply` 等命令会改变集群状态，执行前要确认命名空间和资源名。"],
    next_steps: ["如果 `kube` 无法识别，先运行 `alias kube`、`which kube` 或改用 `kubectl`。"]
  },
  kubectl: {
    title: "kubectl 常用说明",
    summary: "kubectl 用于查看和管理 Kubernetes 集群资源。",
    usage: [
      "`kubectl get pods -A` 查看所有命名空间 Pod。",
      "`kubectl get svc -n <命名空间>` 查看指定命名空间 Service。",
      "`kubectl describe pod <Pod名> -n <命名空间>` 查看 Pod 事件。",
      "`kubectl logs <Pod名> -n <命名空间>` 查看 Pod 日志。"
    ],
    related_commands: [
      { command: "kubectl get svc -A", purpose: "查看全局 Service。", when: "排查服务访问入口。" },
      { command: "kubectl get svc -n <命名空间> -o wide", purpose: "显示 Service 详细信息。", when: "需要看 selector、IP、端口时。" },
      { command: "kubectl get svc <服务名> -n <命名空间> -o yaml", purpose: "查看 Service 完整配置。", when: "确认 selector、端口映射和 annotations。" },
      { command: "kubectl get endpoints <服务名> -n <命名空间>", purpose: "查看 Service 后端 endpoints。", when: "Service 访问不通时。" },
      { command: "kubectl describe svc <服务名> -n <命名空间>", purpose: "查看 Service 事件和端口映射。", when: "定位配置和事件问题。" }
    ],
    examples: [
      { command: "kubectl get svc -A", purpose: "查看所有命名空间的 Service。" },
      { command: "kubectl get svc -n <命名空间>", purpose: "查看指定命名空间 Service。" },
      { command: "kubectl get svc -n <命名空间> -o wide", purpose: "显示 Service 的更多字段。" },
      { command: "kubectl get svc <服务名> -n <命名空间> -o yaml", purpose: "查看单个 Service 的完整 YAML。" }
    ],
    risks: ["只读 get/describe/logs 通常安全；apply/delete/scale 会改变集群。"],
    next_steps: ["若命令超时，先检查 kubeconfig、集群网络和当前上下文：`kubectl config current-context`。"]
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
    related_commands: [
      { command: "docker inspect <容器名或ID>", purpose: "查看容器完整元数据。", when: "需要确认网络、挂载、环境变量时。" },
      { command: "docker compose ps", purpose: "查看 compose 项目容器状态。", when: "项目用 compose 管理时。" }
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
    related_commands: [
      { command: "npm run", purpose: "列出可用脚本。", when: "不知道项目有哪些命令时。" },
      { command: "npm test", purpose: "运行测试。", when: "改代码后验证。" }
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
    related_commands: [
      { command: "python --version", purpose: "查看 Python 版本。", when: "确认解释器是否正确。" },
      { command: "python -m pip list", purpose: "查看已安装包。", when: "排查依赖问题。" }
    ],
    examples: [
      { command: "python -m pytest", purpose: "运行 pytest 测试。" },
      { command: "python -m pip install <包名>", purpose: "用当前解释器安装依赖。" }
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
    related_commands: [
      { command: "where java", purpose: "查看 Windows 中 java 路径。", when: "版本不符合预期时。" },
      { command: "echo %JAVA_HOME%", purpose: "查看 CMD 下 JAVA_HOME。", when: "确认 JDK 配置。" }
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
    related_commands: [
      { command: "adb kill-server && adb start-server", purpose: "重启 adb 服务。", when: "设备识别异常时。" },
      { command: "adb reverse tcp:<端口> tcp:<端口>", purpose: "把设备端口反向映射到电脑。", when: "移动端调试本机服务时。" }
    ],
    examples: [
      { command: "adb devices", purpose: "确认设备是否被电脑识别。" },
      { command: "adb logcat | findstr <关键词>", purpose: "在 Windows 下过滤日志。" }
    ],
    risks: ["安装、卸载和 shell 操作会影响设备状态，操作前确认目标设备。"],
    next_steps: ["设备不显示时检查 USB 调试、数据线、驱动和授权弹窗。"]
  }
};

function firstCommand(text) {
  return String(text || "").trim().split(/\s+/)[0]?.toLowerCase();
}

export function getLocalHelp({ mode, text, outputStyle }) {
  if (mode !== "explain" && mode !== "tools") return null;
  if (String(outputStyle || "").toLowerCase() !== "brief") return null;
  const command = mode === "tools" ? "" : firstCommand(text);
  const value = templates[command];
  if (!value) return null;
  return {
    confidence: "high",
    completion: "",
    completions: [],
    ...value
  };
}
