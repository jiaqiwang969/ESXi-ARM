# 测试凭据（ESXi-ARM 项目）

为保证自动化安装脚本可重复执行，项目固定使用以下测试凭据：

- 用户：`root`
- 密码：`VMware123!`

说明：

1. 该凭据仅用于本仓库的 QEMU 实验与回归验证。
2. 严禁复用于任何生产系统、真实 ESXi 主机或公网环境。
3. 若后续要更改，请同步更新以下位置：
   - `README.md`
   - `work/scripts/run_esxi8_install_full_auto.sh`
   - `work/scripts/run_esxi8_e2e_install_and_verify.sh`（示例命令）
