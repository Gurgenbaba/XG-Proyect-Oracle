<?php

namespace App\Core;

use App\Libraries\DebugLib;
use Exception;
use mysqli;

class Database
{
    private string $last_query = '';
    private mysqli $connection;
    private DebugLib $debug;

    private array $db_data = [
        'host' => '',
        'user' => '',
        'pass' => '',
        'name' => '',
        'prefix' => '',
        'port' => 3306,
    ];

    public function __construct()
    {
        require_once XGP_ROOT . CONFIGS_PATH . 'config.php';

        // Railway ENV
        $envHost = getenv('MYSQLHOST') ?: '';
        $envUser = getenv('MYSQLUSER') ?: '';
        $envPass = getenv('MYSQLPASSWORD') ?: '';
        $envName = getenv('MYSQLDATABASE') ?: '';
        $envPort = getenv('MYSQLPORT') ?: '';

        $prefix = defined('DB_PREFIX') ? DB_PREFIX : 'xgp_';

        if (!empty($envHost) && !empty($envUser) && !empty($envName)) {
            $this->db_data = [
                'host'   => $envHost,
                'user'   => $envUser,
                'pass'   => $envPass,
                'name'   => $envName,
                'prefix' => $prefix,
                'port'   => (int)($envPort ?: 3306),
            ];
        } elseif (
            defined('DB_HOST') &&
            defined('DB_USER') &&
            defined('DB_PASS') &&
            defined('DB_NAME') &&
            defined('DB_PREFIX')
        ) {
            $this->db_data = [
                'host'   => DB_HOST,
                'user'   => DB_USER,
                'pass'   => DB_PASS,
                'name'   => DB_NAME,
                'prefix' => DB_PREFIX,
                'port'   => defined('DB_PORT') ? (int)DB_PORT : 3306,
            ];
        } else {
            $this->db_data = [
                'host'   => 'localhost',
                'user'   => 'root',
                'pass'   => '',
                'name'   => 'xgp',
                'prefix' => $prefix,
                'port'   => 3306,
            ];
        }

        $this->debug = new DebugLib();
        $this->openConnection();
    }

    public function openConnection(): bool
    {
        if (!$this->tryConnection(
            $this->db_data['host'],
            $this->db_data['user'],
            $this->db_data['pass'],
            $this->db_data['port']
        )) {
            if (!defined('IN_INSTALL')) {
                die($this->debug->error(
                    -1,
                    'Database connection failed: ' . $this->connection->connect_error
                ));
            }
            return false;
        }

        if (!$this->tryDatabase($this->db_data['name'])) {
            if (!defined('IN_INSTALL')) {
                die($this->debug->error(
                    -1,
                    'Database selection failed: ' . $this->connection->connect_error
                ));
            }
            return false;
        }

        return true;
    }

    public function tryConnection(
        string $host = '',
        string $user = '',
        string $pass = '',
        int $port = 3306
    ): bool {
        try {
            if (empty($host) || empty($user)) {
                return false;
            }

            $this->connection = new mysqli($host, $user, $pass, '', $port);

            if ($this->connection->connect_error) {
                return false;
            }

            // utf8mb4 for modern MySQL (Railway compatible)
            $this->connection->set_charset('utf8mb4');

            return true;
        } catch (Exception $e) {
            return false;
        }
    }

    public function tryDatabase(string $db_name): bool
    {
        if (empty($db_name)) {
            return false;
        }

        return $this->connection->select_db($db_name);
    }

    public function testConnection(): bool
    {
        return isset($this->connection) && $this->connection->ping();
    }

    public function closeConnection(): bool
    {
        if (isset($this->connection)) {
            $this->connection->close();
            unset($this->connection);
            return true;
        }

        return false;
    }

    public function query(string $sql = '')
    {
        if ($sql === '') return false;

        $sql = $this->prepareSql($sql);
        $this->last_query = $sql;

        $result = $this->connection->query($sql);
        $this->confirmQuery($result);

        return $result;
    }

    public function queryFetch(string $sql = '')
    {
        $result = $this->query($sql);
        return $result ? $this->fetchArray($result) : false;
    }

    public function queryFetchAll(string $sql = '')
    {
        $result = $this->query($sql);
        return $result ? $this->fetchAll($result) : false;
    }

    public function escapeValue($value)
    {
        return $this->connection->real_escape_string($value);
    }

    public function fetchArray($result_set)
    {
        return $result_set->fetch_array(MYSQLI_ASSOC);
    }

    public function fetchAll($result_set)
    {
        return $result_set->fetch_all(MYSQLI_ASSOC);
    }

    public function fetchAssoc($result_set)
    {
        return $result_set->fetch_assoc();
    }

    public function fetchRow($result_set)
    {
        return $result_set->fetch_row();
    }

    public function numRows($result_set)
    {
        return $result_set->num_rows;
    }

    public function insertId()
    {
        return $this->connection->insert_id;
    }

    public function affectedRows()
    {
        return $this->connection->affected_rows;
    }

    private function confirmQuery($result)
    {
        if (!$result) {
            die($this->debug->error(
                -1,
                'Database query failed: ' .
                $this->connection->error .
                ' | SQL: ' . $this->last_query
            ));
        }

        $this->debug->add($this->last_query);
    }

    private function prepareSql(string $query): string
    {
        return strtr($query, ['{xgp_prefix}' => $this->db_data['prefix']]);
    }
}
