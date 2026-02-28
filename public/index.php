<?php

use App\Core\Common;
use App\Libraries\Functions;

define('IN_LOGIN', true);
define('XGP_ROOT', realpath(dirname(__DIR__)) . DIRECTORY_SEPARATOR);

// --- HARD INSTALL LOCK (prevents bootUp redirecting to /install) ---
$installLock = XGP_ROOT . 'storage' . DIRECTORY_SEPARATOR . 'install.lock';
if (!file_exists($installLock)) {
    // If you want to force-disable install always:
    // create the lock automatically OR show a message.
    // I'd rather hard-fail to avoid accidental re-installs:
    http_response_code(500);
    exit('Missing install.lock (installer is disabled).');
}

require XGP_ROOT . 'app' . DIRECTORY_SEPARATOR . 'Core' . DIRECTORY_SEPARATOR . 'Common.php';

$system = new Common();
$system->bootUp('home');

$page = filter_input(INPUT_GET, 'page');
if (is_null($page)) {
    $page = 'home';
}

$file_name = XGP_ROOT . HOME_PATH . ucfirst($page) . 'Controller.php';

if (file_exists($file_name)) {
    include $file_name;

    $class_name = 'App\Http\Controllers\Home\\' . ucfirst($page) . 'Controller';
    (new $class_name())->index();
}
