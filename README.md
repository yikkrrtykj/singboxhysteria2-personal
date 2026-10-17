# Reality + Hysteria2 二合一 sing-box — Personal

以 2026 年 8 月旧版的安装与菜单流程为基础，供个人自用。保留原来的 `mianyang` 菜单、节点显示、BBR、端口跳跃和中转功能；没有多用户管理、Monitor、Web 后台或 service.api 认证迁移，也不会安装 ACL/runuser 作为监控依赖。

安装代码和管理入口只使用本 Personal 仓库。

## 1. 安装服务端

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yikkrrtykj/singboxhysteria2-personal/main/install.sh)
```

作用：安装 Reality + Hysteria2 服务端、systemd 服务和 `mianyang` 管理命令。全新安装会自动启用并启动 `sing-box.service`，不使用手工进程。

本版新安装和菜单更新的内核目标固定为官方正式版 **1.14.3**。下载后验证 GitHub 发布资源的 SHA256；不使用测试版，不自动跟随未来的大版本。

Hysteria2 新安装默认使用 **BBR 拥塞控制**：服务端启用 `ignore_client_bandwidth: true`，服务端和生成的 sing-box / Mihomo 客户端不再设置固定上下行带宽。

BBR 不保证零丢包，也不是公网带宽限速或流量配额控制。需要硬限速或额度时应使用独立机制，不能把 HY2 带宽声明当作硬限速。GitHub 脚本更新不会自动修改旧服务器配置。兼容性、测试范围和手动备份/迁移/回滚步骤见 [HY2 BBR 说明](docs/hysteria2-bbr.md)。

服务端生成的客户端文件：

```text
/root/sbox/mihomo_client.yaml
/root/sbox/sbconfig_client.json
```

## 2. 打开管理菜单

```bash
mianyang
```

重新执行上方安装命令时，完整的现有部署会进入原菜单，并修复 `mianyang` 下载入口；不会自动重装、更新内核或重启服务。旧服务器在修复入口前，`mianyang` 仍可能下载原仓库的最新脚本。

作用：修改服务端配置、显示客户端配置、重启或更新 sing-box、启用 BBR、管理端口跳跃和中转规则。

选择 `3. 显示客户端配置和 Linux 安装命令` 后会显示：

- Reality 和 Hysteria2 链接；
- Windows Mihomo/Clash Meta 配置；
- sing-box JSON 配置；
- 可直接复制到 Linux 客户端执行的 3 条安装命令。

把菜单 3 最后显示的命令 1～3依次复制到 Linux 客户端执行即可。

## 3. 服务端检查和重启

```bash
/root/sbox/sing-box check -c /root/sbox/sbconfig_server.json
```

作用：检查服务端配置，成功后才能重启。

```bash
mianyang
```

作用：进入 `4. sing-box基础操作`。子菜单功能：

1. 检查现有配置，成功后重启 systemd 服务；
2. 更新内核至官方正式版 1.14.3：验证下载摘要、检查现有配置、备份旧内核，重启后检查 Reality/HY2 监听，失败恢复旧内核；
3. 查看 `sing-box.service` 是否正在运行；
4. 持续查看实时日志，按 `Ctrl+C` 退出；
5. 查看完整服务端配置，输出包含 UUID、密码和私钥，不要公开。

```bash
systemctl status sing-box --no-pager
```

作用：查看服务状态和启动方式。

```bash
journalctl -u sing-box -n 100 --no-pager
```

作用：查看最近 100 行服务日志。

```bash
jq '.inbounds[] | {tag, listen_port}' /root/sbox/sbconfig_server.json
```

作用：查看 Reality 和 Hysteria2 监听端口。

```bash
jq '.inbounds[] | select(.tag == "hy2-in") | {ignore_client_bandwidth, has_up_mbps:has("up_mbps"), has_down_mbps:has("down_mbps")}' /root/sbox/sbconfig_server.json
```

作用：检查 HY2 协商设置及带宽字段是否存在；旧部署可能仍保留旧带宽声明。

确认状态显示“启动方式: systemd”后，也可以直接执行：

```bash
systemctl restart sing-box
```

作用：直接重启 systemd 管理的 sing-box。

**仅更新内核不需要重新生成 YAML。** 更新不会修改 UUID、Reality 密钥、HY2 密码、SNI、端口或配置，也不新增 API；服务重启会断开现有连接，停播后再操作。已经配置的 API 或其他旧设置保持原样，不会自动移除。

新安装和生成的 sing-box 客户端配置不带目标 UDP 443 拒绝规则。已有配置不自动改写；我们之前已移除的规则不会因菜单内核更新被加回。

菜单修改端口、TLS、中转或 SS 时，原有配置检查在覆盖文件前执行；加载失败会恢复原配置。备份保存在 `/root/sbox/` 下，文件名含 `.bak.`。这些只是修改操作的错误处理，没有增加认证、监控或后台服务。

菜单 8 的旧任意门落地方案不能正确恢复目标域名，已停止新建，只保留清理旧配置；落地机请使用菜单 9 的 SS 方式。

## 4. 网络优化

新安装会自动检测系统内核是否支持 BBR：支持时启用 BBR、设置默认 `fq` 队列，并优化 UDP 缓冲；不支持时保留当前 TCP 算法，继续完成安装，不会下载第三方脚本或更换内核。已开启 BBR 的系统会保留 BBR。

已有部署只打开菜单或更新 sing-box 内核时，不会自动调整网络设置。需要手动启用时执行：

```bash
mianyang
```

作用：选择菜单 5，启用内核支持的 BBR 和 `fq`，并把 Hysteria2/QUIC UDP 收发缓冲上限提高到至少 16 MiB。配置保存在 `/etc/sysctl.d/99-sing-box-network.conf`，不依赖第三方优化脚本，也不需要更新客户端配置。

## 5. Windows 客户端

```bash
mianyang
```

作用：选择菜单 3，把显示的 Mihomo/Clash Meta YAML 导入 Windows 客户端。默认选择 Reality，也可以切换到 Hysteria2。

## 6. 从零安装 Linux Mihomo 网关

先在服务端执行：

```bash
mianyang
```

作用：选择菜单 3，在输出末尾取得当前节点专用的 Linux 客户端命令。

然后把输出的命令 1～3依次复制到全新 Linux 客户端。它们的作用分别是：

1. 写入 `/tmp/mihomo_client.yaml`；
2. 下载 `install-linux-gateway.sh`；
3. 安装 Mihomo、启用 TUN 网关并开放局域网 9090 UI。

支持：Ubuntu 22.04/24.04、Debian 12、amd64/arm64、systemd、`/dev/net/tun`。

安装器会检查 `53/7897/9090` 端口，安装 Mihomo 和 MetaCubeXD，生成随机 UI 密钥，并在失败时自动恢复。

## 7. Linux 网关常用命令

```bash
cat /etc/mihomo/ui-secret
```

作用：查看 9090 Web UI 密钥。

```text
http://<Linux网关IP>:9090/ui/
```

作用：从可信局域网打开 MetaCubeXD。

```bash
/usr/local/bin/mihomo -t -d /etc/mihomo
```

作用：检查 Mihomo 配置。

```bash
systemctl restart mihomo
```

作用：重启 Linux 网关代理。

```bash
systemctl status mihomo --no-pager
```

作用：查看 Mihomo 状态。

```bash
journalctl -u mihomo -n 100 --no-pager
```

作用：查看 Mihomo 最近 100 行日志。

```bash
ss -lntup | grep mihomo
```

作用：查看 Mihomo 监听端口。

局域网设备需要设置：

- 默认网关：Linux 网关 IP；
- DNS：Linux 网关 IP。

不要把 `53/7897/9090` 直接开放到公网。

## 8. Linux 网关恢复

```bash
ls -1 /var/backups/mihomo-gateway/
```

作用：查看安装器创建的备份。

```bash
mihomo-gateway-installer --restore /var/backups/mihomo-gateway/<备份目录名>
```

作用：恢复安装前的 Mihomo、systemd、DNS 和网络配置。

## 9. VPS IP 质量检测

在 VPS 的 root SSH 窗口执行；这是检测命令，不是安装步骤，不会由本脚本自动运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xykt/IPQuality/main/ip.sh) -4 -p
```

使用 [xykt/IPQuality](https://github.com/xykt/IPQuality)，只检测 IPv4并关闭在线报告。检测 IP 类型、风险评分、黑名单和 TikTok 等流媒体解锁。解锁结果不能证明 LIVE Studio 推流稳定。

旧 README 中的原命令也保留，它打开 IP 质量检测菜单：

```bash
bash <(curl -fsSL https://Check.Place) -I
```

如果要测线路延迟、回程路由和速度，使用 [网络质量检测](https://github.com/xykt/NetQuality)：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xykt/NetQuality/main/net.sh) -4 -p
```

测速会占用带宽，请停播后运行。
