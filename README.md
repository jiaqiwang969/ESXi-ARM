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
- 已推进到安装关键界面：`Select a Disk to Install or Upgrade`（可见磁盘安装流程入口）。

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
- 磁盘控制器：`nvme`
- 加速：`tcg`（当前比 `hvf` 稳定）

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

1. 自动化安装交互（EULA/选盘/确认安装）；
2. 验证安装完成后从系统盘启动；
3. 固化“可一键复现”的 end-to-end 流程。
