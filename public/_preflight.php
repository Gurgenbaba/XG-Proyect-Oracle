<?php

define('XGP_ROOT', realpath(dirname(__DIR__)) . DIRECTORY_SEPARATOR);

$lock = XGP_ROOT . 'storage' . DIRECTORY_SEPARATOR . 'install.lock';
if (!file_exists($lock)) {
    http_response_code(500);
    exit('Missing storage/install.lock (installer is disabled).');
}

// If config missing -> generate from ENV (Railway vars)
$configFile = XGP_ROOT . 'config' . DIRECTORY_SEPARATOR . 'config.php';
if (!file_exists($configFile)) {
    $dbHost = getenv('DB_HOST');
    $dbName = getenv('DB_NAME');
    $dbUser = getenv('DB_USER');
    $dbPass = getenv('DB_PASS');
    $dbPort = getenv('DB_PORT') ?: '3306';

    if (!$dbHost || !$dbName || !$dbUser) {
        http_response_code(500);
        exit('Missing config/config.php and DB_* env vars. Installer is disabled, so config must be provided.');
    }

    $content = <<<PHP
<?php
// Auto-generated on boot (Railway). Do not edit in prod.
\$dbsettings = [
  'host' => '{$dbHost}',
  'user' => '{$dbUser}',
  'pass' => '{$dbPass}',
  'name' => '{$dbName}',
  'port' => '{$dbPort}',
];
PHP;

    @mkdir(dirname($configFile), 0775, true);
    file_put_contents($configFile, $content);
}
