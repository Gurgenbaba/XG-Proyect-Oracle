<?php

define('XGP_ROOT', realpath(dirname(__DIR__)) . DIRECTORY_SEPARATOR);

$lock = XGP_ROOT . 'storage' . DIRECTORY_SEPARATOR . 'install.lock';
if (!file_exists($lock)) {
    http_response_code(500);
    exit('Missing storage/install.lock (installer is disabled).');
}

$configFile = XGP_ROOT . 'config' . DIRECTORY_SEPARATOR . 'config.php';
if (file_exists($configFile)) {
    return; // ok
}

function envv(string $k): ?string {
    $v = getenv($k);
    if ($v === false) return null;
    $v = trim($v);
    return $v === '' ? null : $v;
}

// 1) Prefer explicit DB_* vars
$dbHost = envv('DB_HOST');
$dbName = envv('DB_NAME');
$dbUser = envv('DB_USER');
$dbPass = envv('DB_PASS');
$dbPort = envv('DB_PORT') ?: '3306';

// 2) Fallback: parse DATABASE_URL if DB_* missing
if (!$dbHost || !$dbName || !$dbUser) {
    $dsn = envv('DATABASE_URL') ?: envv('MYSQL_URL') ?: envv('MARIADB_URL');

    if ($dsn) {
        $p = parse_url($dsn);
        $scheme = strtolower($p['scheme'] ?? '');

        if ($scheme === 'postgres' || $scheme === 'postgresql') {
            http_response_code(500);
            exit('DATABASE_URL is PostgreSQL. This game expects MySQL/MariaDB. Provide DB_* vars or a mysql:// URL.');
        }

        // Accept mysql/mariadb
        if ($scheme === 'mysql' || $scheme === 'mariadb') {
            $dbHost = $dbHost ?: ($p['host'] ?? null);
            $dbPort = $dbPort ?: (string)($p['port'] ?? '3306');
            $dbUser = $dbUser ?: (urldecode($p['user'] ?? '') ?: null);
            $dbPass = $dbPass ?: urldecode($p['pass'] ?? '');
            $dbName = $dbName ?: (isset($p['path']) ? ltrim($p['path'], '/') : null);
        }
    }
}

if (!$dbHost || !$dbName || !$dbUser) {
    http_response_code(500);
    exit('Missing config/config.php and no DB_* / DATABASE_URL (mysql) provided. Installer is disabled, so config must be provided.');
}

// Generate config/config.php in the format your app expects (DB settings only).
// If your real config.php contains more keys, paste it (mask secrets) and I’ll match it 1:1.
$content = <<<PHP
<?php
// Auto-generated on boot (Railway). Installer is disabled.
// If you need additional config keys, expand this file.

\$dbsettings = [
  'host' => '{$dbHost}',
  'user' => '{$dbUser}',
  'pass' => '{$dbPass}',
  'name' => '{$dbName}',
  'port' => '{$dbPort}',
];
PHP;

@mkdir(dirname($configFile), 0775, true);
if (file_put_contents($configFile, $content) === false) {
    http_response_code(500);
    exit('Failed to write config/config.php. Check filesystem permissions (Railway container) and that /config is writable.');
}
