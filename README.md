# ESXi-ARM

在 QEMU 中推进 ESXi on Arm（ESXi ARM）安装与启动验证。

## 项目目标（明确）

本项目的唯一目标是：

1. 在 QEMU 中**可重复**启动 ESXi ARM 安装器；
2. 在 QEMU 虚拟磁盘中完成安装；
3. 安装后从虚拟磁盘正常启动进入已安装系统。

> 说明：项目中提到的 Ubuntu/AAVMF 仅用于替换 QEMU 的 UEFI 固件文件，属于“启动链稳定性修复”，不是把目标改成“在 Ubuntu 上安装 ESXi”。

---

## 当前状态（截至 2026-02-12）

- 已定位旧固件崩溃根因：Homebrew 自带 `edk2-aarch64-code.fd` 在 BdsDxe 阶段触发 Data Abort。
- 已验证替换固件有效：使用 Ubuntu `qemu-efi-aarch64` 提供的 AAVMF（2022.02）后，可越过早期崩溃并进入 VMKernel 初始化。
- 已解决安装器无网卡问题：使用 `vmxnet3`。
- 已推进到安装后半段：`Select a Disk to store ESX OSData`、`Please select a keyboard layout`、`Enter a root password`。
- 已确认可见可安装目标盘：在 `usb` 目标盘模式下，安装器可识别第二块 40GiB USB 磁盘（第一块为启动 payload 介质）。
- 已看到安装进度跑到 100% 并出现 `Installation Complete` 页面。
- 已完成一次“输入 root 密码 -> 确认安装 -> 重启”全流程（`final3` 验证镜像）。
- 已验证“仅挂载系统盘”可直启已安装系统（`Boot0004 "VMware ESXi"`），并进入 DCUI（含管理地址显示）。
- 已完成 reboot panic 收敛：将 QEMU 机器参数默认调整为 `gic-version=2` 后，安装器重启路径可走到完整 shutdown + 固件回跳，未再出现 `its.c:2934`。
- 如个别环境仍出现重启不稳定，可使用 `REBOOT_ACTION=poweroff` 作为保底路径（不影响安装结果与冷启动验证）。

详细过程与证据见：`docs/PROJECT_STATUS_2026-02-12.md`。

---

## 快速开始

### 1) 下载并提取 AAVMF 固件（仅一次）

```bash
work/scripts/fetch_aavmf_ubuntu.sh
```

### 2) 启动 ESXi ARM 安装环境

```bash
work/scripts/run_esxi8_aavmf.sh
```

默认参数：
- 固件：`work/firmware/ubuntu-aavmf-2022.02/AAVMF_CODE.fd`
- 启动 payload：`work/out/esxi8-allowlegacy-payload`
- 磁盘：`work/vm/esxi-disk.qcow2`
- 网卡：`vmxnet3`
- 目标盘总线：`usb`（可改 `DISK_BUS=nvme`）
- 机器参数：`virt,virtualization=off,gic-version=2`
- 加速：`tcg`（当前比 `hvf` 稳定）

### 3) 自动推进到 root 密码页（然后手动接管）

```bash
work/scripts/run_esxi8_install_to_password.sh
```

脚本会自动通过欢迎页/EULA/选盘/OSData/键盘布局，并在 `Enter a root password` 页面停下交给你手动输入。

### 4) 一键自动安装（默认包含安装器重启路径观测）

```bash
ROOT_PASSWORD='VMware123!' work/scripts/run_esxi8_install_full_auto.sh
```

说明：
- 会自动完成 root 密码输入、警告确认、`F11 Install`，并等待 `Installation Complete`。
- 默认 `REBOOT_ACTION=enter`：会按 Enter 触发重启并观察 reboot 路径（默认观察 `180s`）。
- 如需保底规避，可使用 `REBOOT_ACTION=poweroff`（到 `Installation Complete` 直接退出 QEMU）。
- 观测窗口可调：`REBOOT_OBSERVE_SEC=240`（示例）。
- 默认会重建安装用变量文件：`work/vm/AAVMF_VARS-esxi-install.fd`。

### 5) 仅挂载系统盘启动已安装 ESXi（手动观察）

```bash
work/scripts/run_esxi8_boot_installed.sh work/vm/esxi-install-usb-auto.qcow2
```

如使用其他镜像，替换第一个参数；默认 vars 文件为 `work/vm/AAVMF_VARS-esxi-install.fd`（需保留安装阶段写入的 Boot 项）。

### 6) 仅挂载系统盘启动并自动校验关键标志（推荐）

```bash
work/scripts/run_esxi8_boot_installed_check.sh work/vm/esxi-install-usb-auto.qcow2
```

脚本会自动等待并验证：
- UEFI 启动路径（`Boot####`，可为 `VMware ESXi` 或通用设备项）；
- `Boot complete (2/2)`；
- `Starting service DCUI` 或 `To manage this host, go to:`

### 7) 单命令端到端（安装 + 冷启动校验）

```bash
ROOT_PASSWORD='VMware123!' work/scripts/run_esxi8_e2e_install_and_verify.sh
```

该脚本会串联安装与 cold-boot 校验，并输出两份日志路径（install / boot）。

### 8) 测试凭据（已写入仓库，便于回归）

- 用户：`root`
- 密码：`VMware123!`
- 用途：仅用于本项目的本地/实验环境自动化验证，请勿复用于生产环境。
- 详情：`docs/TEST_CREDENTIALS.md`

---

## 目录说明（精简）

- `work/scripts/`：核心脚本（启动、补丁、验证、构建）。
- `docs/`：进展文档、关键结论、仓库策略。
- `work/` 其他目录：本地大体积实验产物（ISO、固件、镜像、日志、payload 等），默认不纳入 Git。

---

## 大文件与上传策略

本仓库默认不提交大文件（ISO/ZIP/FD/QCOW2/解包 payload/大量日志），通过脚本重建。

- 策略文档：`docs/LARGE_FILES_POLICY.md`
- 关键可上传内容：
  - 脚本（`work/scripts/*.sh`, `work/scripts/*.py`）
  - 进展文档（`docs/*.md`）
  - 必要时可选上传：少量“关键证据日志片段”（建议提炼到文档，不直接上传超大原始日志）

---

## 下一步

1. 补充更多参数对比（`usb` vs `nvme`、`tcg` vs `hvf`）的结构化结论；
2. 细化“成功判据”文档，减少阅读超长串口日志成本；
3. 将日志摘要进一步结构化（便于 CI/批量回归）。
