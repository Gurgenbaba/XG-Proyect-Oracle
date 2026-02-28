<?php

use App\Core\Common;
use App\Libraries\Adm\AdministrationLib;
use App\Libraries\Functions;

define('IN_ADMIN', true);
define('XGP_ROOT', realpath(dirname(__DIR__)) . DIRECTORY_SEPARATOR);

// --- TEMP DEBUG (nur zum Finden des 500 Grundes) ---
ini_set('display_errors', '1');
ini_set('display_startup_errors', '1');
error_reporting(E_ALL);
// --- TEMP DEBUG END ---

require XGP_ROOT . 'app' . DIRECTORY_SEPARATOR . 'Core' . DIRECTORY_SEPARATOR . 'Common.php';

$system = new Common();
$system->bootUp('admin');

include_once XGP_ROOT . 'app' . DIRECTORY_SEPARATOR . 'Libraries' . DIRECTORY_SEPARATOR . 'Adm' . DIRECTORY_SEPARATOR . 'AdministrationLib.php';

// check updates
$page = filter_input(INPUT_GET, 'page');
if (is_null($page) || $page === '') {
    $page = 'home';
}

$file_name = XGP_ROOT . ADMIN_PATH . ucfirst($page) . 'Controller.php';

// logout
if ($page === 'logout') {
    AdministrationLib::closeSession();
    Functions::redirect(SYSTEM_ROOT . 'admin.php?page=login');
}

if (file_exists($file_name)) {
    require $file_name;

    $class_name = 'App\Http\Controllers\Adm\\' . ucfirst($page) . 'Controller';
    (new $class_name())->index();
} else {
    // NICHT XGP_ROOT (Filesystem) -> URL Redirect:
    Functions::redirect(SYSTEM_ROOT . 'admin.php');
}
