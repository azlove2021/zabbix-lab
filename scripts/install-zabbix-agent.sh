#!/usr/bin/env bash
# =============================================================================
#  install-zabbix-agent.sh
#  在「被监控机」上安装并配置 Zabbix Agent 2（Ubuntu 22.04 / 24.04）
#
#  用法：
#    sudo bash install-zabbix-agent.sh <Server_IP或者逗号分隔的多个IP> [Hostname]
#
#  示例：
#    方案一（内网 VM）：  sudo bash install-zabbix-agent.sh 192.168.174.10 zbx-node1
#    方案二（云主机）：    sudo bash install-zabbix-agent.sh 223.73.55.49 zbx-cloud-01
#
#  说明：
#    <Server_IP> 是 Zabbix Server 侧发起连接时，Agent 看到的「源 IP」。
#    - 同网段：填 Server 的内网 IP
#    - Server 在 NAT 后：填 NAT 后的公网出口 IP（不是你 VM 的 192.168.x.x！）
# =============================================================================
# 不开 pipefail：`cmd | grep -q` 会因 grep 提前退出触发 SIGPIPE，导致误判为不匹配。
set -eu

SERVER_IP="${1:-}"
HOSTNAME_WANT="${2:-$(hostname -s)}"
ZBX_MAJOR="${ZBX_MAJOR:-7.0}"

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'
ok()   { printf '%s  [ OK ]%s %s\n' "$GRN" "$RST" "$*"; }
info() { printf '%s  [ .. ]%s %s\n' "$CYA" "$RST" "$*"; }
warn() { printf '%s  [WARN]%s %s\n' "$YEL" "$RST" "$*"; }
die()  { printf '%s  [FAIL]%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }
step() { printf '\n%s%s==> %s%s\n' "$BLD" "$CYA" "$*" "$RST"; }

die_usage() {
  cat >&2 <<EOF
用法: sudo bash $0 <Server_IP[,Server_IP2...]> [Hostname]

  Server_IP  Agent 看到的「源 IP」：
             · 同网段          → Server 的内网 IP
             · Server 在 NAT 后 → 家宽/公司出口公网 IP
  Hostname   必须与 Web 上创建的 Host name 完全一致（默认取本机主机名）
EOF
  exit 1
}

[[ ${EUID} -eq 0 ]] || die "请用 root 执行：sudo bash $0 $*"
[[ -n "${SERVER_IP}" ]] || die_usage
[[ "${SERVER_IP}" =~ ^[0-9a-fA-F:.,[:space:]]+$ ]] || die "Server_IP 看起来不是合法 IP：${SERVER_IP}"

CONF=/etc/zabbix/zabbix_agent2.conf

step "1/5 环境检查"
. /etc/os-release
case "${VERSION_CODENAME:-}" in
  jammy|noble) : ;;
  *) die "只支持 Ubuntu 22.04/24.04，当前：${PRETTY_NAME:-unknown}" ;;
esac
ok "系统 ${PRETTY_NAME}"

step "2/5 安装 Zabbix Agent 2"
if dpkg -l zabbix-agent2 >/dev/null 2>&1; then
  ok "zabbix-agent2 已安装：$(zabbix_agent2 -V 2>/dev/null | awk '/^zabbix_agent2/{print $3; exit}')"
else
  if ! apt-cache policy zabbix-agent2 2>/dev/null | grep "Candidate: 1:${ZBX_MAJOR}" >/dev/null; then
    DEB="zabbix-release_latest_${ZBX_MAJOR}+ubuntu${VERSION_ID}_all.deb"
    info "添加官方源 ${DEB}"
    wget -q -O "/tmp/${DEB}" \
      "https://repo.zabbix.com/zabbix/${ZBX_MAJOR}/ubuntu/pool/main/z/zabbix-release/${DEB}" \
      || die "下载 zabbix-release 失败，检查能否访问 repo.zabbix.com"
    dpkg -i "/tmp/${DEB}" >/dev/null
    apt-get update -qq
  fi
  apt-get -y -qq install zabbix-agent2 zabbix-get >/dev/null
  ok "已安装 $(zabbix_agent2 -V 2>/dev/null | awk '/^zabbix_agent2/{print $3; exit}')"
fi

step "3/5 配置 ACL 与主机名"
[[ -f "${CONF}.bak" ]] || cp -a "${CONF}" "${CONF}.bak"
sed -i "s|^Server=.*|Server=127.0.0.1,${SERVER_IP}|" "${CONF}"
sed -i "s|^Hostname=.*|Hostname=${HOSTNAME_WANT}|" "${CONF}"
# 主动模式先指向同一台 Server，用不到也不影响
sed -i "s|^ServerActive=.*|ServerActive=${SERVER_IP}|" "${CONF}"
grep -E '^(Server|ServerActive|Hostname)=' "${CONF}" | sed 's/^/        /'
ok "写入完成（Server 里保留了 127.0.0.1 便于本机自测）"

step "4/5 防火墙与启动"
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep "Status: active" >/dev/null; then
  for ip in ${SERVER_IP//,/ }; do
    ufw allow from "${ip}" to any port 10050 proto tcp >/dev/null 2>&1 || true
  done
  ok "ufw 已放行 ${SERVER_IP} → 10050"
else
  ok "ufw 未启用，跳过"
fi
systemctl enable --now zabbix-agent2 >/dev/null 2>&1
systemctl restart zabbix-agent2
systemctl is-active --quiet zabbix-agent2 || die "zabbix-agent2 启动失败：journalctl -u zabbix-agent2 -n 50"
ok "zabbix-agent2 active"
ss -tlnp 2>/dev/null | grep ':10050' >/dev/null || die "10050 没有监听"
ok "10050 正在监听"

step "5/5 本地自测"
PING="$(zabbix_get -s 127.0.0.1 -k agent.ping 2>/dev/null || true)"
[[ "${PING}" == "1" ]] || die "本机 zabbix_get 失败（返回 '${PING}'）"
ok "zabbix_get agent.ping = 1"

VER="$(zabbix_get -s 127.0.0.1 -k agent.version 2>/dev/null || echo '?')"

cat <<EOF

${BLD}${GRN}============ Agent 就绪 ============${RST}
  主机名       : ${BLD}${HOSTNAME_WANT}${RST}   ${YEL}（Web 上的 Host name 必须一字不差）${RST}
  Agent 版本   : ${VER}
  允许的 Server: ${SERVER_IP}   （含 127.0.0.1）
  监听         : 0.0.0.0:10050
  配置文件     : ${CONF}

  下一步（在 Zabbix Server 上验证）：
      zabbix_get -s $(hostname -I | awk '{print $1}') -k agent.ping
  返回 1 再去 Web 上创建主机。

  如果需要排查拒绝问题：
      grep rejected /var/log/zabbix/zabbix_agent2.log | tail -5
      → 日志里 "connection from X" 的 X 就是应该填进 Server= 的值
${BLD}${GRN}==================================${RST}
EOF
