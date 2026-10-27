#!/usr/bin/env bash
# =============================================================================
#  vm-ctl.sh —— 管理 D:\VMs 下的 Zabbix 实验虚拟机
#
#  用法：
#    bash vm-ctl.sh status              # 看运行状态 + IP + Zabbix 服务
#    bash vm-ctl.sh start               # 后台启动两台（无窗口，省资源）
#    bash vm-ctl.sh start gui           # 带窗口启动（要看控制台时用）
#    bash vm-ctl.sh stop                # 正常关机（发 ACPI 信号，推荐）
#    bash vm-ctl.sh poweroff            # 断电（卡死时用）
#    bash vm-ctl.sh restart
#    bash vm-ctl.sh ssh server          # SSH 登录 zbx-server（默认 root）
#    bash vm-ctl.sh ssh node1 zbx       # 指定用 zbx 账号登录
#    bash vm-ctl.sh web                 # 打开 Zabbix Web 页面
# =============================================================================
set -eu

VR="/c/Program Files (x86)/VMware/VMware Workstation/vmrun.exe"
VMROOT="D:\\VMs"
WEB="http://192.168.174.10:8080"

SRV_VMX="${VMROOT}\\zbx-server\\zbx-server.vmx"
NODE_VMX="${VMROOT}\\zbx-node1\\zbx-node1.vmx"
SRV_IP=192.168.174.10
NODE_IP=192.168.174.11

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'
ok()   { printf '%s  [ OK ]%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s  [WARN]%s %s\n' "$YEL" "$RST" "$*"; }
err()  { printf '%s  [FAIL]%s %s\n' "$RED" "$RST" "$*"; }
info() { printf '%s  [ .. ]%s %s\n' "$CYA" "$RST" "$*"; }

[[ -x "$VR" ]] || { err "找不到 vmrun：$VR"; exit 1; }

port_open() {  # $1=host $2=port
  timeout 3 bash -c "cat < /dev/null > /dev/tcp/$1/$2" 2>/dev/null
}

running() {  # $1=vmx 路径 -> 0 表示在运行
  "$VR" -T ws list 2>/dev/null | grep -F "$1" >/dev/null
}

do_status() {
  echo "${BLD}=== 虚拟机运行状态 ===${RST}"
  if "$VR" -T ws list 2>/dev/null | grep -q 'Total running VMs'; then
    "$VR" -T ws list 2>/dev/null | sed 's/^/    /'
  fi
  echo
  echo "${BLD}=== 服务可达性 ===${RST}"
  for pair in "zbx-server:$SRV_IP" "zbx-node1:$NODE_IP"; do
    name="${pair%%:*}"; ip="${pair##*:}"
    printf '    %-12s %-16s ' "$name" "$ip"
    if port_open "$ip" 22; then printf '%sSSH%s ' "$GRN" "$RST"; else printf '%sSSH-%s ' "$RED" "$RST"; fi
    if port_open "$ip" 10050; then printf '%s10050%s ' "$GRN" "$RST"; else printf '%s10050-%s ' "$RED" "$RST"; fi
    if port_open "$ip" 8080; then printf '%s8080%s\n' "$GRN" "$RST"; else printf '%s8080-%s\n' "$RED" "$RST"; fi
  done
  echo
  printf '    Web 入口: %s%s%s\n' "$BLD" "$WEB" "$RST"
}

do_start() {
  local mode="${1:-nogui}"
  for v in "$SRV_VMX" "$NODE_VMX"; do
    if running "$v"; then
      ok "$(basename "$v" .vmx) 已在运行"
    else
      info "启动 $(basename "$v" .vmx) ($mode)"
      "$VR" -T ws start "$v" "$mode" >/dev/null 2>&1 || warn "启动失败，查看 $(dirname "$v") 下的 vmware.log"
    fi
  done
  info "等待网络就绪…"
  for i in $(seq 1 40); do
    if port_open "$SRV_IP" 22 && port_open "$NODE_IP" 22; then
      ok "两台都可达（约 $((i*3))s）"
      break
    fi
    sleep 3
  done
  do_status
}

do_stop() {
  local hard="${1:-soft}"
  for v in "$NODE_VMX" "$SRV_VMX"; do
    if running "$v"; then
      info "停止 $(basename "$v" .vmx) ($hard)"
      if [[ "$hard" == "hard" ]]; then
        "$VR" -T ws stop "$v" hard >/dev/null 2>&1 || true
      else
        "$VR" -T ws stop "$v" soft >/dev/null 2>&1 || true
      fi
    else
      ok "$(basename "$v" .vmx) 未运行"
    fi
  done
  "$VR" -T ws list
}

case "${1:-status}" in
  status)   do_status ;;
  start)    do_start "${2:-nogui}" ;;
  stop)     do_stop soft ;;
  poweroff) do_stop hard ;;
  restart)  do_stop soft; sleep 3; do_start "${2:-nogui}" ;;
  ssh)
    user="${3:-root}"
    case "${2:-server}" in
      server) exec ssh -o StrictHostKeyChecking=no "${user}"@"$SRV_IP" ;;
      node1)  exec ssh -o StrictHostKeyChecking=no "${user}"@"$NODE_IP" ;;
      *) err "用法: bash $0 ssh [server|node1] [root|zbx]"; exit 1 ;;
    esac ;;
  web)
    info "打开 $WEB"
    start "" "$WEB" 2>/dev/null || cmd.exe /c start "" "$WEB" 2>/dev/null || echo "$WEB" ;;
  *)
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 1 ;;
esac
