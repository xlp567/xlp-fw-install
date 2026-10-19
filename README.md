# XLP-FW 一键安装 / 升级

公开仓库只提供通用安装引导。防火墙源码、默认策略和名单继续放在私有仓库 `xlp567/xlp-fw`；这里不包含令牌、服务器地址或防火墙策略。

在 Linux 服务器 **root SSH 终端**执行（需要 curl 和 Python 3.9+）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xlp567/xlp-fw-install/main/install.sh)
```

首次运行隐藏输入 GitHub 只读令牌，仅授权 `xlp-fw` 仓库 `Contents: Read-only`。然后核对版本，输入 `y` 确认安装。已有 v2.0 可以直接升级，无需上传文件。安装成功会自动保存 GitHub 更新配置和令牌。

以后可再次运行同一条命令，或在 v2.1.1+ 中执行：

```bash
xlp-fw update
```

升级只替换管理脚本，保留现有配置和规则，不重新应用策略、不重启代理服务。请先退出正在运行的防火墙菜单，避免管理锁被占用。

令牌过期时，在一键命令末尾加 `--new-token`，重新隐藏输入：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xlp567/xlp-fw-install/main/install.sh) --new-token
```

只检查下载可加 `--check`。令牌不填写在 URL、命令参数或聊天中。

引导程序拒绝转发令牌的重定向，下载固定 Git 提交的安装器并校验内置 SHA-256 后才执行；安装器再从私有仓库 `main` 固定提交下载新版脚本及校验文件。首次使用该入口时，GitHub 上的本公开仓库是引导程序的信任来源。

本仓库的 `install.sh` 由私有项目的 `bootstrap/loader.py` 构建。维护发布时同步引导构建产物，不需要把防火墙源码公开。
