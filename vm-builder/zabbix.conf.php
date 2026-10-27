<?php
// Zabbix GUI configuration file.
global $DB;

$DB['TYPE']                     = 'MYSQL';
$DB['SERVER']                   = 'localhost';
$DB['PORT']                     = '0';
$DB['DATABASE']                 = 'zabbix';
$DB['USER']                     = 'zabbix';
$DB['PASSWORD']                 = 'Zbx_2026_Lab';

// Schema name. Used for PostgreSQL.
$DB['SCHEMA']                   = '';

$ZBX_SERVER                     = 'localhost';
$ZBX_SERVER_PORT                = '10051';
$ZBX_SERVER_NAME                = 'Zabbix Lab';

$IMAGE_FORMAT_DEFAULT           = IMAGE_FORMAT_PNG;
