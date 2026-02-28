<?php
require __DIR__ . '/_preflight.php';
use App\Core\Common;

define('IN_LOGIN', true);
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
$system->bootUp('home');

// Resolve controller
$page = filter_input(INPUT_GET, 'page', FILTER_SANITIZE_SPECIAL_CHARS);
if (!$page) {
    $page = 'home';
}

$file_name = XGP_ROOT . HOME_PATH . ucfirst($page) . 'Controller.php';

if (file_exists($file_name)) {
    require $file_name;

    $class_name = 'App\\Http\\Controllers\\Home\\' . ucfirst($page) . 'Controller';
    (new $class_name())->index();
} else {
    http_response_code(404);
    echo 'Controller not found.';
}
