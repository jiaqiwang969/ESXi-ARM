# 网络与 SSH（可选）

本项目主线以“安装完成 + 冷启动进入 DCUI + 串口日志判据”为交付标准，不依赖网络。但如果你要从宿主机访问 ESXi 的管理面（HTTPS/SSH），建议按本文档操作。

## 现象：SLIRP（`-netdev user`）下入站不稳定

默认脚本使用 QEMU user-mode networking（SLIRP）：

- ESXi 往往可以拿到 `10.0.2.x` 的 DHCP 地址（DCUI 会显示 `https://10.0.2.15/ (DHCP)` 之类）；
- 但在一些环境里，即使配置 `hostfwd`，宿主机访问 `ssh/https` 也会表现为超时（例如 `banner exchange timeout` / `SSL connection timeout`）。

这属于“QEMU + ESXi + SLIRP”组合的现实限制/兼容性问题，建议不要在主线交付中依赖它。

## 推荐：macOS 使用 `vmnet-shared`（需要 sudo）

在 macOS 上，QEMU 支持 `-netdev vmnet-shared`（基于 `vmnet.framework`）。

优点：
- guest 会通过 DHCP 获取一个“真实可直连”的局域网 IP（通常在 `bridge100` 对应的 `192.168.2.0/24` 网段）；
- 宿主机可直接访问 `https://<ip>/`、`ssh root@<ip>`，无需端口转发。

注意：
- `vmnet-shared` 通常需要 root 权限创建接口：请用 `sudo` 启动 QEMU；
- 如果 `sudo` 环境找不到 `qemu-system-aarch64` / `socat`，可以在执行前显式指定 `QEMU_BIN=/opt/homebrew/bin/qemu-system-aarch64`、`SOCAT_BIN=/opt/homebrew/bin/socat`。

## 快速命令

启动已安装 ESXi（vmnet-shared）：

```bash
sudo work/scripts/run_esxi8_boot_installed_vmnet.sh --bg work/vm/esxi-install-e2e.qcow2
```

一键 bootstrap（启动 + 自动发现 IP + 尝试 sendkey 开 SSH + 写 env）：

```bash
sudo ROOT_PASSWORD='VMware123!' work/scripts/esxi_vmnet_bootstrap.sh
source work/vm/esxi_info.env
ssh root@"$ESXI_IP"
```

手动开启 SSH（稳定做法）：
- DCUI：`F2 -> root 登录 -> Troubleshooting Options -> Enable SSH`

