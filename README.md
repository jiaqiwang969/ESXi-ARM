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

## 稳定经验（重点，建议完整阅读）

这一节总结的是“已经被反复验证可稳定复现”的做法，目标是让你下次直接按这个执行，不再重复踩坑。

### A. 当前最稳定参数组合（推荐默认）

- 固件：Ubuntu `AAVMF_CODE.fd`（路径：`work/firmware/ubuntu-aavmf-2022.02/AAVMF_CODE.fd`）
- 机器参数：`virt,virtualization=off,gic-version=2`
- 加速器：`tcg`
- 网卡：`vmxnet3`
- 安装目标盘总线：`usb`
- 安装脚本默认行为：`REBOOT_ACTION=enter`（会观测重启路径）

结论上，这套组合相对 `gic-version=3` 的主要改进是：安装完成后重启阶段不再触发 `its.c:2934` panic，而是能走完整 shutdown 并回跳到固件启动。

### B. 安装与启动分成“两阶段”理解（非常关键）

1) 安装阶段  
- 挂载安装 payload（FAT 目录）+ 目标系统盘 + AAVMF vars  
- 安装器会把 UEFI 启动项写入 vars（例如 `Boot0004`，也可能继续用通用 `Boot0002`）

2) 已安装系统启动阶段（disk-only）  
- 只挂载系统盘（不要再挂安装 payload）  
- 继续使用安装阶段同一个 vars 文件  
- 这样才会走“已安装系统”而不是回到安装器

如果你在这一步换了 vars 或又把 payload 挂上，最常见现象就是“看起来又进安装器了”。

### C. 一次性可交付执行模板（推荐你后续都照这个跑）

```bash
RUN_TAG=deliverable-$(date +%Y%m%d-%H%M%S) \
ROOT_PASSWORD='VMware123!' \
work/scripts/run_esxi8_e2e_install_and_verify.sh
```

这条命令会自动完成：
- 自动安装（含 root 密码输入、确认安装）
- 安装完成后触发重启并观测重启路径
- 冷启动已安装系统并自动校验关键标志

### D. 判定“成功”的硬指标（按日志看，不靠感觉）

安装日志至少应满足：
- 出现 `Installation Complete`
- 出现 `Starting VMKernel shutdown`
- 不出现 `its.c:2934` / `Module(s) involved in panic`
- 最好出现 `This system has been halted` 且随后再次出现 `BdsDxe: loading Boot0002`（表示重启路径连通）

启动校验日志至少应满足：
- 出现 `Starting VMKernel`（或 `Starting VMKernel initialization`）
- 出现 `Boot complete (2/2)`
- 出现 `Starting service DCUI` 或 `To manage this host, go to:`

项目里的 `work/scripts/check_esxi8_boot_log.py` 已把这些判据做成自动检查。

### E. 常见不稳定点与对应处理

1) **重启阶段 panic（历史问题）**  
- 表现：`its.c:2934`  
- 处理：确认机器参数是 `gic-version=2`；若仍不稳，临时使用 `REBOOT_ACTION=poweroff` 保底不阻塞交付

2) **安装后又回安装器**  
- 常见原因：仍挂着 payload，或 vars 被重建/替换  
- 处理：disk-only 启动 + 复用安装时的 vars

3) **安装器里选错盘**  
- 常见现象：选到 504MiB 的 payload 盘，导致最小容量错误  
- 处理：在 USB 模式下通常需要选第二块 40GiB 盘

4) **HVF 偶发不稳定**  
- 建议：交付跑批优先 `tcg`，先追求确定性

5) **Boot 项名字和编号变化**  
- `Boot0004 "VMware ESXi"` 与 `Boot0002` 都可能出现  
- 这是可接受的，关键看是否进入已安装系统并满足 `Boot complete`/`DCUI` 判据

### F. 建议保留的“最小证据集”

每次交付建议保留两份日志：
- 安装日志：`esxi8-e2e-install-<tag>.log`
- 启动日志：`esxi8-e2e-boot-<tag>.log`

并在文档里记录：
- 当次参数（特别是 `MACHINE_OPTS`、`DISK_BUS`、`ACCEL`）
- 是否出现 panic 关键词
- `Boot complete (2/2)` 行号

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
