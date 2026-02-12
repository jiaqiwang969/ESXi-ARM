# NixOS 轨道（完整系统，不是 host 上装 Nix）

## 目的

这个轨道的目标是：

1. 建立一台独立的 NixOS aarch64 虚拟机（完整操作系统）；
2. 在这台 NixOS 里固化 ESXi-ARM 自动化工具链（QEMU / expect / 脚本）；
3. 与 Ubuntu 轨道形成分工：Ubuntu 快速试错，NixOS 稳态沉淀。

> 关键澄清：ESXi-ARM 仍然是最终目标系统。NixOS 是我们的“可复现控制面”，不是替代 ESXi。

## 当前建议版本（截至 2026-02-12）

- NixOS channel：`nixos-25.11`
- 安装介质：`latest-nixos-minimal-aarch64-linux.iso`
- 启动固件：Ubuntu AAVMF（`work/firmware/ubuntu-aavmf-2022.02`）

## 一次性准备

```bash
work/scripts/fetch_aavmf_ubuntu.sh
work/scripts/fetch_nixos_aarch64_iso.sh
```

## 启动 NixOS 安装器（完整系统安装）

```bash
work/scripts/run_nixos_aarch64_installer.sh
```

默认：
- 系统盘：`work/vm/nixos-aarch64.qcow2`
- UEFI vars：`work/vm/AAVMF_VARS-nixos.fd`
- 串口控制台：`-serial mon:stdio`
- SSH 端口转发：`localhost:10022 -> guest:22`

## 在安装器里完成安装（手动）

登录后执行（典型盘符为 `/dev/vda`）：

```bash
sudo -i

parted /dev/vda -- mklabel gpt
parted /dev/vda -- mkpart ESP fat32 1MiB 512MiB
parted /dev/vda -- set 1 esp on
parted /dev/vda -- mkpart primary ext4 512MiB 100%

mkfs.fat -F32 /dev/vda1
mkfs.ext4 -F /dev/vda2

mount /dev/vda2 /mnt
mkdir -p /mnt/boot
mount /dev/vda1 /mnt/boot

nixos-generate-config --root /mnt
```

可选：使用仓库模板配置（安装器脚本默认共享了只读仓库 9p）

```bash
mkdir -p /mnt/repo
mount -t 9p -o trans=virtio,version=9p2000.L esxiarm_repo /mnt/repo
cp /mnt/repo/work/nixos/configuration.esxi-lab.nix /mnt/etc/nixos/configuration.nix
```

该模板默认包含**测试用弱安全设置**（方便回归/无人值守）：

- `root` / `jqwang` 初始密码：`VMware123!`
- `sshd` 允许密码登录，且允许 root 登录

仅建议用于本地/实验环境，请勿用于生产网络。

然后安装并设置 root 密码：

```bash
nixos-install --root /mnt
reboot
```

## 启动已安装 NixOS

```bash
work/scripts/run_nixos_aarch64_boot_installed.sh
```

说明：
- 保持同一个 `AAVMF_VARS-nixos.fd`，确保 UEFI 启动项持续可用；
- 若需重装并清理 UEFI 变量，可在安装器启动时加 `RESET_VARS=1`。

## 与 ESXi-ARM 项目的关系（避免目标偏移）

- ESXi-ARM 主线：继续验证 `run_esxi8_*` 系列脚本与可交付日志；
- NixOS 轨道：把同样流程沉淀为可复现环境，减少“换机器就漂移”的问题；
- 交付判据不变：仍以 ESXi 安装完成 + 冷启动进入 DCUI 为准。
