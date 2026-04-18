<?php
ob_start();
ini_set('display_errors', '0');
error_reporting(E_ALL);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit;
}

require_once __DIR__ . '/db.php';
mysqli_set_charset($conn, 'utf8mb4');

function j(array $arr, int $code = 200): void {
    if (ob_get_length()) {
        ob_clean();
    }
    http_response_code($code);
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}

function requireFields(array $data, array $fields): void {
    foreach ($fields as $field) {
        if (!isset($data[$field]) || trim((string)$data[$field]) === '') {
            j(['success' => false, 'message' => "ข้อมูลไม่ครบ: {$field}"], 400);
        }
    }
}

function hasColumn(mysqli $conn, string $table, string $column): bool {
    static $cache = [];
    $key = $table . '.' . $column;
    if (array_key_exists($key, $cache)) {
        return $cache[$key];
    }

    $table = $conn->real_escape_string($table);
    $column = $conn->real_escape_string($column);
    $res = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$column'");
    $cache[$key] = $res && $res->num_rows > 0;
    return $cache[$key];
}

function getBaseUrl(): string {
    if (!empty($_ENV['APP_BASE_URL'])) {
        return rtrim($_ENV['APP_BASE_URL'], '/') . '/';
    }
    if (!empty($_SERVER['APP_BASE_URL'])) {
        return rtrim($_SERVER['APP_BASE_URL'], '/') . '/';
    }

    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
    $scheme = $https ? 'https' : 'http';
    $host = $_SERVER['HTTP_HOST'] ?? 'localhost';
    $scriptDir = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
    if ($scriptDir === '' || $scriptDir === '.') {
        $scriptDir = '';
    }

    return $scheme . '://' . $host . $scriptDir . '/';
}

function absoluteImageUrl(string $baseUrl, string $path): string {
    $path = trim($path);
    if ($path === '' || $path === 'DEL') {
        return '';
    }
    if (preg_match('~^https?://~i', $path)) {
        return $path;
    }
    return $baseUrl . ltrim($path, '/');
}

try {
    $data = $_SERVER['REQUEST_METHOD'] === 'POST' ? $_POST : $_GET;
    $action = trim((string)($data['action'] ?? ''));

    switch ($action) {
        // ===== เดิมจาก dashboard_api.php =====
        case 'get_all_stats':
            $dorm_id = isset($data['dorm_id']) ? (int)$data['dorm_id'] : 0;
            $user_id = isset($data['user_id']) ? (int)$data['user_id'] : 0;

            if ($dorm_id <= 0 || $user_id <= 0) {
                j(['success' => false, 'message' => 'dorm_id หรือ user_id ไม่ถูกต้อง'], 400);
            }

            $hasImageColumn = hasColumn($conn, 'rh_announcements', 'image');
            $selectImage = $hasImageColumn ? ', COALESCE(image, "") AS image' : ', "" AS image';
            $baseUrl = getBaseUrl();

            $stmt = $conn->prepare("SELECT COUNT(*) AS total FROM rh_dorm_memberships WHERE dorm_id = ? AND approve_status = 'pending'");
            $stmt->bind_param('i', $dorm_id);
            $stmt->execute();
            $r_pending = $stmt->get_result()->fetch_assoc();
            $stmt->close();

            $stmt = $conn->prepare("SELECT COUNT(*) AS total FROM rh_repairs WHERE dorm_id = ? AND status <> 'done'");
            $stmt->bind_param('i', $dorm_id);
            $stmt->execute();
            $r_repair = $stmt->get_result()->fetch_assoc();
            $stmt->close();

            $stmt = $conn->prepare("SELECT COUNT(*) AS total FROM rh_notifications WHERE user_id = ? AND is_read = 0");
            $stmt->bind_param('i', $user_id);
            $stmt->execute();
            $r_noti = $stmt->get_result()->fetch_assoc();
            $stmt->close();

            $sqlAnn = "SELECT announce_id, title, detail, is_pinned, created_at $selectImage
                       FROM rh_announcements
                       WHERE dorm_id = ? AND status = 'active'
                       ORDER BY is_pinned DESC, created_at DESC, announce_id DESC
                       LIMIT 5";
            $stmt = $conn->prepare($sqlAnn);
            $stmt->bind_param('i', $dorm_id);
            $stmt->execute();
            $resAnn = $stmt->get_result();

            $announcements = [];
            while ($row = $resAnn->fetch_assoc()) {
                $announcements[] = [
                    'announce_id' => (int)$row['announce_id'],
                    'title' => $row['title'] ?? '',
                    'detail' => $row['detail'] ?? '',
                    'image' => absoluteImageUrl($baseUrl, $row['image'] ?? ''),
                    'is_pinned' => (int)($row['is_pinned'] ?? 0),
                    'created_at' => $row['created_at'] ?? null,
                ];
            }
            $stmt->close();

            j([
                'success' => true,
                'pending_approve' => (int)($r_pending['total'] ?? 0),
                'pending_repair' => (int)($r_repair['total'] ?? 0),
                'unread_count' => (int)($r_noti['total'] ?? 0),
                'total_announcements' => count($announcements),
                'announcements_list' => $announcements,
            ]);
            break;

        // ===== เดิมจาก dashboard_api.php =====
        case 'dashboard':
            $resDorms = $conn->query("SELECT COUNT(*) AS c FROM rh_dorms");
            $resUsers = $conn->query("SELECT COUNT(*) AS c FROM rh_users");
            $resActive = $conn->query("SELECT COUNT(*) AS c FROM rh_dorms WHERE status = 'active'");
            $resSuspended = $conn->query("SELECT COUNT(*) AS c FROM rh_dorms WHERE status = 'suspended'");

            j([
                'success' => true,
                'data' => [
                    'total_dorms' => (int)($resDorms->fetch_assoc()['c'] ?? 0),
                    'total_users' => (int)($resUsers->fetch_assoc()['c'] ?? 0),
                    'dorm_status' => [
                        'active' => (int)($resActive->fetch_assoc()['c'] ?? 0),
                        'suspended' => (int)($resSuspended->fetch_assoc()['c'] ?? 0),
                    ],
                ],
            ]);
            break;

        case 'listDorms':
            $kw = '%' . trim((string)($data['q'] ?? '')) . '%';
            $sql = "SELECT d.dorm_id, d.dorm_name, d.dorm_code, d.status, d.dorm_address, d.dorm_phone,
                        (SELECT COUNT(*) FROM rh_dorm_memberships m WHERE m.dorm_id = d.dorm_id AND m.role_code = 't' AND m.approve_status = 'approved') AS tenant_count,
                        (SELECT COUNT(*) FROM rh_dorm_memberships m WHERE m.dorm_id = d.dorm_id AND m.role_code = 'o' AND m.approve_status = 'approved') AS admin_count,
                        (SELECT COUNT(*) FROM rh_dorm_memberships m WHERE m.dorm_id = d.dorm_id AND m.approve_status = 'pending') AS pending_count
                    FROM rh_dorms d
                    WHERE d.dorm_name LIKE ? OR d.dorm_code LIKE ?
                    ORDER BY d.dorm_id DESC";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param('ss', $kw, $kw);
            $stmt->execute();
            j(['success' => true, 'data' => $stmt->get_result()->fetch_all(MYSQLI_ASSOC)]);
            break;

        case 'listUsers':
            $kw = '%' . trim((string)($data['q'] ?? '')) . '%';
            $sql = "SELECT u.user_id, u.username, u.full_name, u.phone,
                           CASE WHEN u.user_level = 'a' THEN 'platform_admin' ELSE 'user' END AS platform_role,
                           (SELECT d.dorm_name
                              FROM rh_dorm_memberships m
                              JOIN rh_dorms d ON m.dorm_id = d.dorm_id
                             WHERE m.user_id = u.user_id AND m.role_code = 'o'
                             ORDER BY m.membership_id DESC
                             LIMIT 1) AS dorm_name
                    FROM rh_users u
                    WHERE u.full_name LIKE ? OR u.username LIKE ? OR u.phone LIKE ?
                    ORDER BY u.user_level ASC, u.user_id DESC";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param('sss', $kw, $kw, $kw);
            $stmt->execute();
            j(['success' => true, 'data' => $stmt->get_result()->fetch_all(MYSQLI_ASSOC)]);
            break;

        case 'createDorm':
            requireFields($data, ['dorm_name', 'dorm_code', 'owner_username', 'owner_password']);
            $dormName = trim((string)$data['dorm_name']);
            $dormCode = trim((string)$data['dorm_code']);
            $ownerUser = trim((string)$data['owner_username']);
            $ownerPass = password_hash((string)$data['owner_password'], PASSWORD_BCRYPT);
            $ownerFullName = trim((string)($data['owner_full_name'] ?? ''));
            $ownerPhone = trim((string)($data['owner_phone'] ?? ''));

            $conn->begin_transaction();
            try {
                $stmt = $conn->prepare("INSERT INTO rh_dorms (dorm_name, dorm_code, status) VALUES (?, ?, 'active')");
                $stmt->bind_param('ss', $dormName, $dormCode);
                $stmt->execute();
                $dormId = (int)$conn->insert_id;

                $stmtU = $conn->prepare("INSERT INTO rh_users (username, password, full_name, phone, user_level) VALUES (?, ?, ?, ?, 'o')");
                $stmtU->bind_param('ssss', $ownerUser, $ownerPass, $ownerFullName, $ownerPhone);
                $stmtU->execute();
                $userId = (int)$conn->insert_id;

                $stmtM = $conn->prepare("INSERT INTO rh_dorm_memberships (user_id, dorm_id, role_code, approve_status) VALUES (?, ?, 'o', 'approved')");
                $stmtM->bind_param('ii', $userId, $dormId);
                $stmtM->execute();

                $stmtS = $conn->prepare("INSERT INTO rh_dorm_settings (dorm_id, water_rate, electric_rate) VALUES (?, 0.00, 0.00)");
                $stmtS->bind_param('i', $dormId);
                $stmtS->execute();

                $conn->commit();
                j(['success' => true, 'message' => 'สร้างหอพักและบัญชีผู้ดูแลหอพักสำเร็จ ']);
            } catch (Throwable $e) {
                $conn->rollback();
                j(['success' => false, 'message' => 'เกิดข้อผิดพลาด: ' . $e->getMessage()], 500);
            }
            break;

        case 'addAdmin':
            requireFields($data, ['username', 'password', 'full_name']);
            $user = trim((string)$data['username']);
            $pass = password_hash((string)$data['password'], PASSWORD_BCRYPT);
            $name = trim((string)$data['full_name']);
            $phone = trim((string)($data['phone'] ?? ''));

            $stmt = $conn->prepare("INSERT INTO rh_users (username, password, full_name, phone, user_level) VALUES (?, ?, ?, ?, 'a')");
            $stmt->bind_param('ssss', $user, $pass, $name, $phone);
            if ($stmt->execute()) {
                j(['success' => true, 'message' => 'เพิ่มแอดมินระบบเรียบร้อย ✅']);
            }
            j(['success' => false, 'message' => 'ไม่สามารถเพิ่มได้ (Username อาจซ้ำ)'], 500);
            break;

        case 'setDormStatus':
            $did = (int)($data['dorm_id'] ?? 0);
            $status = trim((string)($data['status'] ?? ''));
            if ($did <= 0 || !in_array($status, ['active', 'suspended'], true)) {
                j(['success' => false, 'message' => 'ข้อมูลไม่ถูกต้อง'], 400);
            }
            $stmt = $conn->prepare("UPDATE rh_dorms SET status = ? WHERE dorm_id = ?");
            $stmt->bind_param('si', $status, $did);
            $stmt->execute();
            j(['success' => true, 'message' => 'อัปเดตสถานะสำเร็จ']);
            break;

        case 'bank_list':
            $dormId = (int)($data['dorm_id'] ?? 0);
            if ($dormId <= 0) {
                j(['success' => false, 'message' => 'ไม่พบ dorm_id'], 400);
            }
            $stmt = $conn->prepare("SELECT bank_id, dorm_id, bank_name, account_name, account_no
                                    FROM rh_bank_accounts
                                    WHERE dorm_id = ?
                                    ORDER BY bank_id DESC");
            $stmt->bind_param('i', $dormId);
            $stmt->execute();
            j(['success' => true, 'accounts' => $stmt->get_result()->fetch_all(MYSQLI_ASSOC)]);
            break;

        case 'bank_add':
            requireFields($data, ['dorm_id', 'bank_name', 'account_name', 'account_no']);
            $dormId = (int)$data['dorm_id'];
            $bankName = trim((string)$data['bank_name']);
            $accountName = trim((string)$data['account_name']);
            $accountNo = trim((string)$data['account_no']);

            $stmt = $conn->prepare("INSERT INTO rh_bank_accounts (dorm_id, bank_name, account_name, account_no)
                                    VALUES (?, ?, ?, ?)");
            $stmt->bind_param('isss', $dormId, $bankName, $accountName, $accountNo);
            if ($stmt->execute()) {
                j(['success' => true, 'message' => 'เพิ่มบัญชีธนาคารสำเร็จ', 'bank_id' => (int)$conn->insert_id]);
            }
            j(['success' => false, 'message' => 'ไม่สามารถเพิ่มบัญชีธนาคารได้'], 500);
            break;

        case 'bank_update':
            requireFields($data, ['bank_id', 'dorm_id', 'bank_name', 'account_name', 'account_no']);
            $bankId = (int)$data['bank_id'];
            $dormId = (int)$data['dorm_id'];
            $bankName = trim((string)$data['bank_name']);
            $accountName = trim((string)$data['account_name']);
            $accountNo = trim((string)$data['account_no']);

            $stmt = $conn->prepare("UPDATE rh_bank_accounts
                                       SET bank_name = ?, account_name = ?, account_no = ?
                                     WHERE bank_id = ? AND dorm_id = ?");
            $stmt->bind_param('sssii', $bankName, $accountName, $accountNo, $bankId, $dormId);
            $stmt->execute();
            j(['success' => true, 'message' => 'อัปเดตบัญชีธนาคารสำเร็จ']);
            break;

        case 'bank_delete':
            requireFields($data, ['bank_id', 'dorm_id']);
            $bankId = (int)$data['bank_id'];
            $dormId = (int)$data['dorm_id'];
            $stmt = $conn->prepare("DELETE FROM rh_bank_accounts WHERE bank_id = ? AND dorm_id = ?");
            $stmt->bind_param('ii', $bankId, $dormId);
            $stmt->execute();
            j(['success' => true, 'message' => 'ลบบัญชีธนาคารสำเร็จ']);
            break;

        default:
            j(['success' => false, 'message' => 'ไม่พบ Action ที่ระบุ'], 404);
    }
} catch (Throwable $e) {
    j(['success' => false, 'message' => 'Server Error: ' . $e->getMessage()], 500);
}
