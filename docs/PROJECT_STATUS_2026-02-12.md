# 项目进展记录（2026-02-12）

## 结论

- 旧路径卡死主因是 UEFI 固件兼容性（BdsDxe 崩溃），不是 `K.B00` CPUID 补丁文件损坏。
- 将固件从 Homebrew QEMU 自带 `edk2-aarch64-code.fd` 换成 Ubuntu `qemu-efi-aarch64` 的 AAVMF（2022.02）后，ESXi 8 可进入安装流程。

## 已完成

1. CPUID 补丁链路可生成、可验证；
2. 固件崩溃点定位（`Data abort: Access flag fault, third level`）；
3. AAVMF 替换后通过早期启动；
4. `vmxnet3` 解决安装器无网卡阻塞；
5. 自动交互到达 `Select a Disk to Install or Upgrade` 页面。

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

## 未完成（距离终目标）

- 完成安装向导后半段（选盘、确认、写盘）；
- 安装完成后从虚拟磁盘启动验证；
- 脚本化 end-to-end 流程。

## 里程碑评估

- 当前整体进度：约 70%~80%。
