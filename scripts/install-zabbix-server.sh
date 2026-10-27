#!/usr/bin/env bash
# =============================================================================
#  install-zabbix-server.sh
#  Zabbix 7.0 LTS 单机一键部署（Ubuntu 22.04 / 24.04）
#
#  用法：
#    sudo bash install-zabbix-server.sh                 # 默认 8080 端口
#    sudo DB_PASS='MyPass123' WEB_PORT=80 bash install-zabbix-server.sh
#    sudo bash install-zabbix-server.sh --check         # 只做体检，不改任何东西
#
#  说明：
#    - 全程幂等：重复执行不会重复建库/覆盖已导入的数据
#    - 每一步都有验证点，失败立刻停并打印日志位置
#    - 对应文档：Zabbix-7.0-LTS-安装部署实战.md 第 4 章
# =============================================================================
# 注意：这里故意不开 pipefail。开启后 `cmd | grep -q PAT` 会因 grep 提前退出、
# cmd 收到 SIGPIPE 而使整条管道返回非 0，导致"明明匹配上了却判断为不匹配"。
set -eu

ZBX_MAJOR="${ZBX_MAJOR:-7.0}"
DB_NAME="${DB_NAME:-zabbix}"
DB_USER="${DB_USER:-zabbix}"
DB_PASS="${DB_PASS:-Zbx_2026_Lab}"
WEB_PORT="${WEB_PORT:-8080}"
MODE="${1:-install}"

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYA=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'
ok()   { printf '%s  [ OK ]%s %s\n' "$GRN" "$RST" "$*"; }
info() { printf '%s  [ .. ]%s %s\n' "$CYA" "$RST" "$*"; }
warn() { printf '%s  [WARN]%s %s\n' "$YEL" "$RST" "$*"; }
die()  { printf '%s  [FAIL]%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }
step() { printf '\n%s%s==> %s%s\n' "$BLD" "$CYA" "$*" "$RST"; }

need_root() { [[ ${EUID} -eq 0 ]] || die "请用 root 执行：sudo bash $0"; }

detect_os() {
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID}" == "ubuntu" ]] || die "本脚本只支持 Ubuntu，当前：${ID}"
  OS_CODENAME="${VERSION_CODENAME}"
  case "${OS_CODENAME}" in
    jammy|noble) : ;;
    *) die "只支持 Ubuntu 22.04(jammy) / 24.04(noble)，当前：${PRETTY_NAME}" ;;
  esac
  PHP_VER="$(php_ver)"
  ok "系统 ${PRETTY_NAME}（${OS_CODENAME}），PHP-FPM ${PHP_VER}"
}

# 从 /etc/php/<ver>/fpm 目录反推已安装的 PHP 版本；没装则看 apt 候选
php_ver() {
  local v
  v="$(ls -d /etc/php/*/fpm 2>/dev/null | head -1 | cut -d/ -f4)"
  if [[ -z "${v}" ]]; then
    v="$(apt-cache policy php-fpm 2>/dev/null \
         | awk '/Candidate:/{print $2}' | sed -E 's/^[0-9]+://; s/\+.*$//')"
  fi
  printf '%s' "${v:-8.3}"
}

# ---------------------------------------------------------------- 0. 体检模式
if [[ "${MODE}" == "--check" ]]; then
  need_root; detect_os
  step "服务与端口"
  for s in zabbix-server zabbix-agent2 nginx "php${PHP_VER}-fpm" mysql; do
    st=$(systemctl is-active "$s" 2>/dev/null || true)
    [[ "$st" == "active" ]] && ok "$s = active" || warn "$s = ${st:-unknown}"
  done
  ss -tlnp 2>/dev/null | grep -E ":(${WEB_PORT}|10050|10051)\b" || warn "关键端口 ${WEB_PORT}/10050/10051 未全部监听"
  step "数据库"
  if mysql -u"${DB_USER}" -p"${DB_PASS}" -D "${DB_NAME}" -Nse \
      "select concat('tables=', count(*)) from information_schema.tables where table_schema='${DB_NAME}';" 2>/dev/null; then
    ok "数据库 ${DB_NAME} 可连接"
  else
    warn "数据库 ${DB_NAME} 连接失败（用户名/密码可能不同）"
  fi
  step "Web"
  curl -sI "http://127.0.0.1:${WEB_PORT}" 2>/dev/null | head -1 || warn "Web 端口 ${WEB_PORT} 无响应"
  step "Server 日志尾部"
  tail -5 /var/log/zabbix/zabbix_server.log 2>/dev/null || warn "日志文件不存在"
  exit 0
fi

need_root

# DB_PASS 要写进 SQL 和 sed，含这些字符会出错
case "${DB_PASS}" in
  *"'"*|*'"'*|*'\'*|*'|'*|*'&'*|*' '*)
    die "DB_PASS 不能包含引号、反斜杠、竖线、& 或空格，换一个（例：Zbx_2026_Lab）" ;;
esac

detect_os

LOG="/var/log/zabbix-install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG}") 2>&1
trap 'die "失败在：${BASH_COMMAND}   —— 完整日志：${LOG}"' ERR
info "日志：${LOG}"

# ---------------------------------------------------------------- 1. 系统基线
step "1/9 系统基线"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get -y -qq install curl wget vim gnupg ca-certificates lsb-release >/dev/null
timedatectl set-timezone Asia/Shanghai 2>/dev/null || true
systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
ok "时区 $(timedatectl show -p Timezone --value 2>/dev/null || echo '?')，包索引已更新"

# ---------------------------------------------------------------- 2. Zabbix 源
step "2/9 添加 Zabbix ${ZBX_MAJOR} 官方源"
DEB="zabbix-release_latest_${ZBX_MAJOR}+ubuntu${VERSION_ID}_all.deb"
URL="https://repo.zabbix.com/zabbix/${ZBX_MAJOR}/ubuntu/pool/main/z/zabbix-release/${DEB}"
if [[ -f /etc/apt/sources.list.d/zabbix.sources ]] && apt-cache policy zabbix-server-mysql 2>/dev/null | grep "Candidate: 1:${ZBX_MAJOR}" >/dev/null; then
  ok "官方源已存在，跳过"
else
  info "下载 ${URL}"
  wget -q -O "/tmp/${DEB}" "${URL}" || die "下载失败，检查网络能否访问 repo.zabbix.com"
  dpkg -i "/tmp/${DEB}" >/dev/null
  apt-get update -qq
  ok "源已添加"
fi
apt-cache policy zabbix-server-mysql | grep 'Candidate: 1:' >/dev/null || die "源里找不到 zabbix-server-mysql"

# ---------------------------------------------------------------- 3. 装包
step "3/9 安装 Zabbix Server / 前端 / Agent"
apt-get -y -qq install \
  zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf \
  zabbix-sql-scripts zabbix-agent2 zabbix-get >/dev/null
PHP_VER="$(php_ver)"
SRV_VER="$(zabbix_server -V 2>/dev/null | awk '/^zabbix_server/{print $3; exit}')"
ok "zabbix_server ${SRV_VER}，nginx $(nginx -v 2>&1 | awk -F/ '{print $2}')，php-fpm ${PHP_VER}"

# ---------------------------------------------------------------- 4. 数据库
step "4/9 安装 MySQL 并建库"
apt-get -y -qq install mysql-server >/dev/null
systemctl enable --now mysql >/dev/null 2>&1
for _ in $(seq 1 30); do mysqladmin ping >/dev/null 2>&1 && break; sleep 1; done
mysqladmin ping >/dev/null 2>&1 || die "MySQL 启动超时"

mysql <<SQL
create database if not exists ${DB_NAME} character set utf8mb4 collate utf8mb4_bin;
create user if not exists '${DB_USER}'@'localhost' identified by '${DB_PASS}';
alter user '${DB_USER}'@'localhost' identified by '${DB_PASS}';
grant all privileges on ${DB_NAME}.* to '${DB_USER}'@'localhost';
flush privileges;
SQL
mysql -u"${DB_USER}" -p"${DB_PASS}" -D "${DB_NAME}" -e "select 1;" >/dev/null \
  || die "新建的 zabbix 用户无法登录数据库"
ok "库 ${DB_NAME} 与用户 ${DB_USER}@localhost 就绪"

# ---------------------------------------------------------------- 5. 导 schema
step "5/9 导入表结构"
TBL_CNT="$(mysql -u"${DB_USER}" -p"${DB_PASS}" -Nse \
  "select count(*) from information_schema.tables where table_schema='${DB_NAME}';" 2>/dev/null || echo 0)"
if [[ "${TBL_CNT}" -gt 50 ]]; then
  ok "已存在 ${TBL_CNT} 张表，跳过导入（避免覆盖数据）"
else
  SQLGZ=/usr/share/zabbix-sql-scripts/mysql/server.sql.gz
  [[ -f "${SQLGZ}" ]] || die "找不到 ${SQLGZ}"
  info "导入中，约 30-90 秒，期间无输出是正常的…"
  mysql -e "set global log_bin_trust_function_creators = 1;"
  zcat "${SQLGZ}" | mysql --default-character-set=utf8mb4 -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}"
  mysql -e "set global log_bin_trust_function_creators = 0;"
  TBL_CNT="$(mysql -u"${DB_USER}" -p"${DB_PASS}" -Nse \
    "select count(*) from information_schema.tables where table_schema='${DB_NAME}';")"
  [[ "${TBL_CNT}" -gt 150 ]] || die "导入后只有 ${TBL_CNT} 张表，导入异常"
  ok "导入完成，${TBL_CNT} 张表"
fi

# ---------------------------------------------------------------- 6. Server 配置
step "6/9 配置 zabbix_server.conf"
CONF=/etc/zabbix/zabbix_server.conf
cp -a "${CONF}" "${CONF}.bak.$(date +%s)" 2>/dev/null || true
if grep -q '^DBPassword=' "${CONF}"; then
  sed -i "s|^DBPassword=.*|DBPassword=${DB_PASS}|" "${CONF}"
else
  sed -i "s|^#[[:space:]]*DBPassword=.*|DBPassword=${DB_PASS}|" "${CONF}"
fi
grep -q "^DBPassword=${DB_PASS}$" "${CONF}" || die "DBPassword 写入失败"
grep -q '^DBName=zabbix' "${CONF}" || sed -i 's|^#\?[[:space:]]*DBName=.*|DBName=zabbix|' "${CONF}"
grep -q '^DBUser=zabbix' "${CONF}" || sed -i 's|^#\?[[:space:]]*DBUser=.*|DBUser=zabbix|' "${CONF}"
ok "DBName/DBUser/DBPassword 已写入"

# ---------------------------------------------------------------- 7. Nginx
step "7/9 配置 Nginx 监听 ${WEB_PORT}"
NGX=/etc/zabbix/nginx.conf
cp -a "${NGX}" "${NGX}.bak.$(date +%s)" 2>/dev/null || true
sed -i "s|^#[[:space:]]*listen[[:space:]]*[0-9]*;|        listen          ${WEB_PORT};|" "${NGX}"
sed -i "s|^[[:space:]]*listen[[:space:]]*[0-9]*;|        listen          ${WEB_PORT};|" "${NGX}"
sed -i "s|^#[[:space:]]*server_name[[:space:]]*.*;|        server_name     _;|" "${NGX}"
grep -qE "^[[:space:]]*listen[[:space:]]+${WEB_PORT};" "${NGX}" || die "nginx listen 写入失败"

# 80 端口会让出 default site，避免被抢占
if [[ "${WEB_PORT}" == "80" && -e /etc/nginx/sites-enabled/default ]]; then
  rm -f /etc/nginx/sites-enabled/default
  warn "已删除 /etc/nginx/sites-enabled/default（80 端口让给 Zabbix）"
fi
[[ -e /etc/nginx/conf.d/zabbix.conf ]] || ln -s "${NGX}" /etc/nginx/conf.d/zabbix.conf
ok "nginx.conf 已启用，软链 /etc/nginx/conf.d/zabbix.conf"

# ---------------------------------------------------------------- 8. 起服务
step "8/9 启动服务"
nginx -t >/dev/null 2>&1 || die "nginx -t 语法检查失败"
systemctl enable  zabbix-server zabbix-agent2 nginx "php${PHP_VER}-fpm" >/dev/null 2>&1
systemctl restart "php${PHP_VER}-fpm" nginx zabbix-server zabbix-agent2
for s in zabbix-server zabbix-agent2 nginx "php${PHP_VER}-fpm"; do
  st=$(systemctl is-active "$s" 2>/dev/null || true)
  [[ "$st" == "active" ]] && ok "$s active" || die "$s 未启动：journalctl -u $s -n 50"
done

# ---------------------------------------------------------------- 9. 验证
step "9/9 端到端验证"
for _ in $(seq 1 20); do
  ss -tln 2>/dev/null | grep ':10051' >/dev/null && break; sleep 1
done
ss -tlnp 2>/dev/null | grep -E ":(${WEB_PORT}|10050|10051)\b" || die "端口未全部监听"

PING="$(zabbix_get -s 127.0.0.1 -k agent.ping 2>/dev/null || true)"
[[ "${PING}" == "1" ]] || die "agent.ping 返回 '${PING}'（应为 1），检查 agent 的 Server= 配置"
ok "zabbix_get agent.ping = 1"

CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${WEB_PORT}/" || echo 000)"
[[ "${CODE}" == "200" ]] || warn "Web 返回 ${CODE}（可能前端还没初始化向导）"

grep -q 'Zabbix server started' /var/log/zabbix/zabbix_server.log 2>/dev/null \
  && ok "Server 日志出现 'Zabbix server started'"

IP="$(hostname -I | awk '{print $1}')"
cat <<EOF

${BLD}${GRN}============ 部署完成 ============${RST}
  前端地址 : ${BLD}http://${IP}:${WEB_PORT}${RST}
  默认账号 : Admin / zabbix   ${YEL}（登录后第一件事：改密码）${RST}
  数据库   : ${DB_NAME} / ${DB_USER} / ${DB_PASS}
  配置文件 : /etc/zabbix/zabbix_server.conf
  日志     : /var/log/zabbix/zabbix_server.log
  本次日志 : ${LOG}

  下一步：
    1. 浏览器打开上面的地址，走完 6 步向导（DB host 填 localhost）
    2. Data collection → Hosts → Create host
       Host name = $(hostname)   Interfaces = Agent 127.0.0.1:10050
       Templates = Linux by Zabbix agent
    3. 等 ZBX 变绿（最多 1-2 分钟）

  体检命令：sudo bash $0 --check
${BLD}${GRN}==================================${RST}
EOF
