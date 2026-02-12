# 项目进展记录（2026-02-12）

## 结论

- 旧路径卡死主因是 UEFI 固件兼容性（BdsDxe 崩溃），不是 `K.B00` CPUID 补丁文件损坏。
- 将固件从 Homebrew QEMU 自带 `edk2-aarch64-code.fd` 换成 Ubuntu `qemu-efi-aarch64` 的 AAVMF（2022.02）后，ESXi 8 可进入安装流程。

## 已完成

1. CPUID 补丁链路可生成、可验证；
2. 固件崩溃点定位（`Data abort: Access flag fault, third level`）；
3. AAVMF 替换后通过早期启动；
4. `vmxnet3` 解决安装器无网卡阻塞；
5. 自动交互到达 `Select a Disk to Install or Upgrade` 页面；
6. 在 `usb` 目标盘模式下识别到第二块 40GiB 安装目标盘（`vmhba33`）；
7. 自动推进到 `Select a Disk to store ESX OSData`、键盘布局、root 密码页面。
8. 安装流程可推进到 `Installation Progress 100%` 与 `Installation Complete` 页面。
9. 已完成一次从 root 密码页继续到 `Confirm Install` / `F11 Install` / `Installation Complete` / `Enter Reboot` 的完整人工闭环（`final3`）。
10. 已验证“仅系统盘（无安装 payload）”可从 `Boot0004 "VMware ESXi"` 启动，并进入 DCUI（可见管理地址）。
11. 新增“仅系统盘自动校验”脚本：`run_esxi8_boot_installed_check.sh` + `check_esxi8_boot_log.py`，可结构化判定 `VMKernel`、`Boot complete`、`DCUI/管理地址`。
12. 新增单命令端到端脚本：`run_esxi8_e2e_install_and_verify.sh`（安装 + cold boot 校验）。
13. 安装自动化脚本新增 `REBOOT_ACTION` 与 `REBOOT_OBSERVE_SEC`：可在安装完成后自动观察 reboot 路径并识别 panic/回跳标志。
14. 通过参数回归确认：`MACHINE_OPTS=virt,virtualization=off,gic-version=2` 下，安装器重启路径可完成 `VMK shutdown(43/43)`、出现 `This system has been halted` 并回到 `BdsDxe`，未再出现 `its.c:2934`。
15. 已完成 `gic-version=2` + `REBOOT_ACTION=enter` 的端到端交付验证（安装、重启路径观测、冷启动校验均通过）。
16. 已固化测试凭据文档（`docs/TEST_CREDENTIALS.md`），确保后续回归时密码可追溯。
17. 已新增 NixOS 完整系统轨道脚本与文档（`fetch_nixos_aarch64_iso.sh`、`run_nixos_aarch64_installer.sh`、`run_nixos_aarch64_boot_installed.sh`、`docs/NIXOS_TRACK.md`），用于构建独立可复现控制面。

## 关键证据（日志）

- 旧固件崩溃：
  - `work/out/qemu-tcg-esxi8-unpatched-nosigbypass2-norts-200s.log`
- 新固件可进入安装器：
  - `work/out/qemu-tcg-esxi8-allowlegacy-aavmf2022-180s.log`
- 新固件 + vmxnet3（网络问题绕过）：
  - `work/out/qemu-tcg-esxi8-allowlegacy-aavmf2022-vmxnet3-180s.log`
- 自动流程到磁盘选择：
  - `work/out/esxi8-install-probe-vmxnet3-nvme.log`
  - `work/out/esxi8-install-probe2-vmxnet3-nvme.log`
- USB 目标盘可见（含 40GiB 第二块盘）：
  - `work/out/probe-usbtarget2-20260212-092207.log`
- 自动推进到 root 密码页：
  - `work/out/esxi8-install-usb-autoflow2-20260212-095529.log`
  - `work/out/esxi8-install-passprobe2-20260212-100145.log`
  - `work/out/esxi8-install-passprobe3-20260212-100858.log`
- 安装进度到 100% 并出现 Installation Complete：
  - `work/out/esxi8-install-usb-final2-20260212-103202.log`
- 安装后仅挂载系统盘启动（无安装 payload）进入 UEFI Shell：
  - `work/out/esxi8-postinstall-bootprobe-20260212-103912.log`
  - `work/out/esxi8-postinstall-shellprobe-20260212-104341.log`
- 完整安装闭环（含 root 密码输入、确认安装、触发重启）：
  - `work/out/esxi8-install-usb-final3.log`
- 安装器触发重启时的 shutdown panic（`its.c:2934`）：
  - `work/out/esxi8-install-usb-final3.log`
- `gic-version=2` 下重启路径无 panic，且回到固件引导：
  - `work/out/esxi8-install-usb-gic2-enter-observe.log`
- 端到端交付（`gic-version=2` + `REBOOT_ACTION=enter`）：
  - `work/out/esxi8-e2e-install-deliverable-gic2-enter.log`
  - `work/out/esxi8-e2e-boot-deliverable-gic2-enter.log`
- 仅系统盘启动，成功进入已安装 ESXi 并出现 DCUI：
  - `work/out/esxi8-final3-postinstall-bootprobe-long-20260212-123341.log`
- 新增自动校验脚本冒烟通过（仅系统盘）：
  - `work/out/esxi8-boot-installed-check-smoke2-20260212.log`

## 未完成（距离终目标）

- 补齐参数矩阵（`usb`/`nvme`、`tcg`/`hvf`）的可复现实验结论；
- 将自动校验输出进一步压缩成更易阅读的摘要（当前仍以原始串口日志为主）。

## 当前主要困难（最新）

1. 安装器 TUI 输出高频 ANSI 重绘，仍会增加 `expect` 匹配复杂度；
2. UEFI 启动项在不同 vars 状态下可能是 `Boot0004 "VMware ESXi"` 或通用设备项（如 `Boot0002`），判据需要兼容两种路径；
3. `gic-version=2` 作为当前稳定默认值已验证，但仍需补齐更大参数矩阵做稳态结论。

## 里程碑评估

- 当前整体进度：约 98%（目标链路与 reboot 路径均打通；剩余参数矩阵与文档收尾）。
