<?php

use App\Core\Common;

define('IN_ADMIN', true);
define('XGP_ROOT', realpath(dirname(__DIR__)) . DIRECTORY_SEPARATOR);

// --- HARD INSTALL LOCK ---
$installLock = XGP_ROOT . 'storage' . DIRECTORY_SEPARATOR . 'install.lock';
if (!file_exists($installLock)) {
    http_response_code(500);
    exit('Missing storage/install.lock (installer is disabled).');
}

// Core bootstrap
require XGP_ROOT . 'app' . DIRECTORY_SEPARATOR . 'Core' . DIRECTORY_SEPARATOR . 'Common.php';

$system = new Common();
// je nach Core: manche Projekte nutzen bootUp('admin'), manche 'home' reicht.
// Ich setze bewusst 'admin', weil es semantisch korrekt ist:
$system->bootUp('admin');

// Resolve controller
$page = filter_input(INPUT_GET, 'page', FILTER_SANITIZE_SPECIAL_CHARS);
if (!$page) {
    $page = 'overview'; // falls dein Admin Default anders heißt: hier ändern
}

$file_name = XGP_ROOT . ADMIN_PATH . ucfirst($page) . 'Controller.php';

if (file_exists($file_name)) {
    require $file_name;

    $class_name = 'App\\Http\\Controllers\\Adm\\' . ucfirst($page) . 'Controller';
    (new $class_name())->index();
} else {
    http_response_code(404);
    echo 'Admin controller not found: ' . htmlspecialchars($page, ENT_QUOTES, 'UTF-8');
}
