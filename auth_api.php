<?php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Content-Type: application/json; charset=utf-8');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit;
}

ini_set('display_errors', '0');
ini_set('html_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

register_shutdown_function(function () {
    $e = error_get_last();
    if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR], true)) {
        if (!headers_sent()) {
            http_response_code(500);
            header('Content-Type: application/json; charset=utf-8');
        }
        echo json_encode([
            'success' => false,
            'message' => 'Fatal: ' . $e['message'] . ' @' . $e['file'] . ':' . $e['line'],
        ], JSON_UNESCAPED_UNICODE);
    }
});

require_once __DIR__ . '/db.php';
mysqli_set_charset($conn, 'utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function auth_json(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function auth_request_data(): array {
    $data = $_GET + $_POST;
    $raw = file_get_contents('php://input');
    if ($raw !== '') {
        $json = json_decode($raw, true);
        if (is_array($json)) {
            $data = array_merge($data, $json);
        }
    }
    return $data;
}

function has_text(array $data, string $key): bool {
    return isset($data[$key]) && trim((string)$data[$key]) !== '';
}

function infer_auth_action(array $data): string {
    $action = trim((string)($data['action'] ?? ''));
    if ($action !== '') return $action;

    if (has_text($data, 'username') && has_text($data, 'password') && has_text($data, 'full_name') && has_text($data, 'phone') && has_text($data, 'dorm_code')) {
        return 'register';
    }
    if (has_text($data, 'dorm_code') && !has_text($data, 'username') && !has_text($data, 'password') && !has_text($data, 'full_name') && !has_text($data, 'phone')) {
        return 'lookup_dorm';
    }
    if (has_text($data, 'username') && has_text($data, 'dorm_code') && has_text($data, 'phone') && has_text($data, 'new_password') && !has_text($data, 'user_id')) {
        return 'forgot_password';
    }
    if (has_text($data, 'username') && has_text($data, 'password') && !has_text($data, 'full_name') && !has_text($data, 'dorm_code')) {
        return 'login';
    }
    if (isset($data['user_id']) || isset($data['userId'])) {
        if (has_text($data, 'old_password') && has_text($data, 'new_password')) return 'change_password';
        if (has_text($data, 'username') || has_text($data, 'full_name') || has_text($data, 'phone')) return 'update';
        return 'get';
    }
    return '';
}

function role_in_dorm_from_code(?string $roleCode): string {
    if ($roleCode === 'o') return 'owner';
    if ($roleCode === 'a') return 'admin';
    return 'tenant';
}

function format_mysql_date(?string $value): ?string {
    if ($value === null || trim($value) === '') return null;
    $ts = strtotime($value);
    if ($ts === false) return $value;
    return date('Y-m-d', $ts);
}

function find_dorm_by_code(mysqli $conn, string $dormCode): ?array {
    $stmt = $conn->prepare('SELECT dorm_id, dorm_name, dorm_code FROM rh_dorms WHERE dorm_code=? LIMIT 1');
    $stmt->bind_param('s', $dormCode);
    $stmt->execute();
    $dorm = $stmt->get_result()->fetch_assoc();
    $stmt->close();
    return $dorm ?: null;
}

function load_profile_payload(mysqli $conn, int $userId): array {
    $stmt = $conn->prepare('SELECT user_id, username, full_name, phone, user_level FROM rh_users WHERE user_id=? LIMIT 1');
    $stmt->bind_param('i', $userId);
    $stmt->execute();
    $user = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$user) {
        auth_json(['success' => false, 'message' => 'ไม่พบผู้ใช้'], 404);
    }

    $stmt = $conn->prepare(
        "SELECT
            m.membership_id, m.dorm_id, m.room_id, m.role_code, m.approve_status,
            m.move_in_date, m.move_out_date, d.dorm_name
         FROM rh_dorm_memberships m
         LEFT JOIN rh_dorms d ON d.dorm_id = m.dorm_id
         WHERE m.user_id=?
         ORDER BY
            CASE
                WHEN m.approve_status = 'approved' AND m.move_out_date IS NULL THEN 0
                WHEN m.move_out_date IS NOT NULL THEN 1
                WHEN m.approve_status = 'pending' THEN 2
                ELSE 3
            END,
            m.membership_id DESC
         LIMIT 1"
    );
    $stmt->bind_param('i', $userId);
    $stmt->execute();
    $membership = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    $room = null;
    if ($membership) {
        $dormId = (int)($membership['dorm_id'] ?? 0);
        $roomId = (int)($membership['room_id'] ?? 0);

        if ($roomId > 0 && $dormId > 0) {
            $stmt = $conn->prepare(
                "SELECT
                    r.room_id, r.room_number, r.floor, r.base_rent, r.status,
                    b.building_id, b.building_name,
                    rt.type_id, rt.type_name
                 FROM rh_rooms r
                 LEFT JOIN rh_buildings b ON b.building_id = r.building_id
                 LEFT JOIN rh_room_types rt ON rt.type_id = r.type_id
                 WHERE r.room_id=? AND r.dorm_id=?
                 LIMIT 1"
            );
            $stmt->bind_param('ii', $roomId, $dormId);
            $stmt->execute();
            $room = $stmt->get_result()->fetch_assoc();
            $stmt->close();
        }

        if (!$room && $dormId > 0 && (($membership['move_out_date'] ?? null) === null || trim((string)$membership['move_out_date']) === '')) {
            $stmt = $conn->prepare(
                "SELECT
                    r.room_id, r.room_number, r.floor, r.base_rent, r.status,
                    b.building_id, b.building_name,
                    rt.type_id, rt.type_name
                 FROM rh_rooms r
                 LEFT JOIN rh_buildings b ON b.building_id = r.building_id
                 LEFT JOIN rh_room_types rt ON rt.type_id = r.type_id
                 WHERE r.tenant_id=? AND r.dorm_id=?
                 ORDER BY r.room_id ASC
                 LIMIT 1"
            );
            $stmt->bind_param('ii', $userId, $dormId);
            $stmt->execute();
            $room = $stmt->get_result()->fetch_assoc();
            $stmt->close();
        }
    }

    $roleInDorm = $membership ? role_in_dorm_from_code($membership['role_code'] ?? null) : null;
    $approveStatus = $membership['approve_status'] ?? null;
    $tenantStatus = 'waiting';

    if ($membership) {
        if (!empty($membership['move_out_date'])) {
            $tenantStatus = 'former';
            $approveStatus = 'inactive'; 
        } elseif (($membership['approve_status'] ?? '') === 'approved') {
            $tenantStatus = 'active';
        }
    }

    return [
        'user_id' => (int)$user['user_id'],
        'username' => $user['username'],
        'full_name' => $user['full_name'],
        'phone' => $user['phone'],
        'user_level' => $user['user_level'],
        'platform_role' => $user['user_level'] === 'a' ? 'platform_admin' : 'user',

        'membership_id' => $membership ? (int)$membership['membership_id'] : 0,
        'role_in_dorm' => $roleInDorm,
        'approve_status' => $approveStatus,
        'tenant_status' => $tenantStatus,

        'dorm_id' => isset($membership['dorm_id']) ? (int)$membership['dorm_id'] : null,
        'dorm_name' => $membership['dorm_name'] ?? null,

        'move_in_date' => format_mysql_date($membership['move_in_date'] ?? null),
        'move_out_date' => format_mysql_date($membership['move_out_date'] ?? null),

        'room_id' => $room ? (int)$room['room_id'] : (int)($membership['room_id'] ?? 0),
        'room_number' => $room['room_number'] ?? null,
        'floor' => $room ? (int)$room['floor'] : null,
        'room_status' => $room['status'] ?? null,
        'base_rent' => $room ? (float)$room['base_rent'] : null,
        'building_id' => ($room && $room['building_id'] !== null) ? (int)$room['building_id'] : null,
        'building_name' => $room['building_name'] ?? null,
        'building' => $room['building_name'] ?? null,
        'room_type_id' => ($room && $room['type_id'] !== null) ? (int)$room['type_id'] : null,
        'room_type_name' => $room['type_name'] ?? null,
    ];
}

try {
    $data = auth_request_data();
    $action = infer_auth_action($data);

    if ($action === '') {
        auth_json(['success' => false, 'message' => 'Missing action'], 400);
    }

    if ($action === 'lookup_dorm') {
        $dormCode = trim((string)($data['dorm_code'] ?? ''));
        if ($dormCode === '') auth_json(['success' => false, 'message' => 'กรุณากรอกโค้ดหอพัก'], 400);
        $dorm = find_dorm_by_code($conn, $dormCode);
        if (!$dorm) auth_json(['success' => false, 'message' => 'โค้ดหอพักไม่ถูกต้อง'], 404);
        auth_json(['success' => true, 'dorm_id' => (int)$dorm['dorm_id'], 'dorm_name' => $dorm['dorm_name'], 'dorm_code' => $dorm['dorm_code']]);
    }

    if ($action === 'login') {
        $username = trim((string)($data['username'] ?? ''));
        $password = (string)($data['password'] ?? '');
        if ($username === '' || $password === '') auth_json(['success' => false, 'message' => 'กรอกข้อมูลไม่ครบ'], 400);

        $stmt = $conn->prepare('SELECT user_id, username, password, full_name, user_level FROM rh_users WHERE username=? LIMIT 1');
        $stmt->bind_param('s', $username);
        $stmt->execute();
        $user = $stmt->get_result()->fetch_assoc();
        $stmt->close();

        if (!$user || !password_verify($password, (string)$user['password'])) {
            auth_json(['success' => false, 'message' => 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'], 401);
        }

        $userId = (int)$user['user_id'];
        if (($user['user_level'] ?? '') === 'a') {
            auth_json(['success' => true, 'user' => ['user_id' => $userId, 'username' => $user['username'], 'full_name' => $user['full_name'], 'platform_role' => 'platform_admin', 'approve_status' => 'approved', 'role_in_dorm' => 'admin']]);
        }

        $profile = load_profile_payload($conn, $userId);

        // 🛑 แก้ไขจุดที่ 1: ดักคนเก่าให้ขึ้นว่ารหัสผิด (401) เพื่อความเนียน
        if ($profile['tenant_status'] === 'former' || $profile['approve_status'] === 'inactive' || $profile['approve_status'] === 'rejected') {
            auth_json(['success' => false, 'message' => 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'], 401);
        }

        auth_json(['success' => true, 'user' => $profile]);
    }

    if ($action === 'register') {
        $fullName = trim((string)($data['full_name'] ?? ''));
        $phone = trim((string)($data['phone'] ?? ''));
        $username = trim((string)($data['username'] ?? ''));
        $password = trim((string)($data['password'] ?? ''));
        $dormCode = trim((string)($data['dorm_code'] ?? ''));

        if ($fullName === '' || $phone === '' || $username === '' || $password === '' || $dormCode === '') auth_json(['success' => false, 'message' => 'กรุณากรอกข้อมูลให้ครบ'], 400);

        $conn->begin_transaction();
        try {
            $dorm = find_dorm_by_code($conn, $dormCode);
            if (!$dorm) throw new Exception('ไม่พบโค้ดหอพักนี้');
            $dormId = (int)$dorm['dorm_id'];

            $stmtCheck = $conn->prepare('SELECT user_id FROM rh_users WHERE username=? LIMIT 1');
            $stmtCheck->bind_param('s', $username); $stmtCheck->execute();
            if ($stmtCheck->get_result()->fetch_assoc()) throw new Exception('Username นี้ถูกใช้งานแล้ว');
            $stmtCheck->close();

            $hash = password_hash($password, PASSWORD_DEFAULT);
            $stmt = $conn->prepare("INSERT INTO rh_users (username, password, full_name, phone, user_level) VALUES (?, ?, ?, ?, 't')");
            $stmt->bind_param('ssss', $username, $hash, $fullName, $phone); $stmt->execute();
            $userId = (int)$conn->insert_id; $stmt->close();

            $stmt2 = $conn->prepare("INSERT INTO rh_dorm_memberships (user_id, dorm_id, role_code, approve_status) VALUES (?, ?, 't', 'pending')");
            $stmt2->bind_param('ii', $userId, $dormId); $stmt2->execute(); $stmt2->close();

            $stmtNoti = $conn->prepare('INSERT INTO rh_notifications (user_id, dorm_id, type_id, message) VALUES (?, ?, 1, ?)');
            $msg = 'มีผู้ขอเข้าร่วมหอพัก: ' . $fullName;
            $stmtNoti->bind_param('iis', $userId, $dormId, $msg); $stmtNoti->execute(); $stmtNoti->close();

            $conn->commit();
            auth_json(['success' => true, 'user_id' => $userId, 'dorm_id' => $dormId, 'dorm_name' => $dorm['dorm_name']]);
        } catch (Throwable $e) { $conn->rollback(); auth_json(['success' => false, 'message' => $e->getMessage()], 500); }
    }

    if ($action === 'forgot_password') {
        $username = trim((string)($data['username'] ?? ''));
        $dormCode = trim((string)($data['dorm_code'] ?? ''));
        $phone = trim((string)($data['phone'] ?? ''));
        $newPassword = trim((string)($data['new_password'] ?? ''));

        $conn->begin_transaction();
        try {
            // 🛑 แก้ไขจุดที่ 2: เพิ่มเงื่อนไขสถานะใน Query เพื่อไม่ให้คนเก่ามาเปลี่ยนรหัสได้
            $stmt = $conn->prepare('
                SELECT u.user_id 
                FROM rh_users u 
                JOIN rh_dorm_memberships m ON m.user_id = u.user_id 
                JOIN rh_dorms d ON d.dorm_id = m.dorm_id 
                WHERE u.username = ? 
                  AND u.phone = ? 
                  AND d.dorm_code = ? 
                  AND m.approve_status = "approved" 
                  AND m.move_out_date IS NULL 
                LIMIT 1
            ');
            $stmt->bind_param('sss', $username, $phone, $dormCode); $stmt->execute();
            $row = $stmt->get_result()->fetch_assoc(); $stmt->close();

            if (!$row) throw new Exception('ข้อมูลไม่ถูกต้อง');

            $hash = password_hash($newPassword, PASSWORD_DEFAULT);
            $upd = $conn->prepare('UPDATE rh_users SET password = ? WHERE user_id = ?');
            $upd->bind_param('si', $hash, $row['user_id']); $upd->execute(); $upd->close();

            $conn->commit();
            auth_json(['success' => true, 'message' => 'เปลี่ยนรหัสผ่านเรียบร้อย']);
        } catch (Throwable $e) { $conn->rollback(); auth_json(['success' => false, 'message' => $e->getMessage()], 500); }
    }

    if (in_array($action, ['check_status', 'get', 'profile'], true)) {
        $userId = (int)($data['user_id'] ?? $data['userId'] ?? 0);
        if ($userId <= 0) auth_json(['success' => false, 'message' => 'missing user_id'], 400);
        $profile = load_profile_payload($conn, $userId);
        if ($profile['tenant_status'] === 'former') auth_json(['success' => false, 'message' => 'พ้นสภาพการใช้งาน'], 403);
        auth_json(['success' => true, 'data' => $profile, 'user' => $profile]);
    }

    if ($action === 'change_password') {
        $userId = (int)($data['user_id'] ?? $data['userId'] ?? 0);
        $old = trim((string)($data['old_password'] ?? ''));
        $new = trim((string)($data['new_password'] ?? ''));
        $stmt = $conn->prepare('SELECT password FROM rh_users WHERE user_id=? LIMIT 1');
        $stmt->bind_param('i', $userId); $stmt->execute(); $u = $stmt->get_result()->fetch_assoc(); $stmt->close();
        if (!$u || !password_verify($old, $u['password'])) auth_json(['success' => false, 'message' => 'รหัสผ่านเดิมไม่ถูกต้อง'], 401);
        $hash = password_hash($new, PASSWORD_DEFAULT);
        $stmt = $conn->prepare('UPDATE rh_users SET password=? WHERE user_id=?');
        $stmt->bind_param('si', $hash, $userId); $stmt->execute(); $stmt->close();
        auth_json(['success' => true, 'message' => 'เปลี่ยนรหัสผ่านสำเร็จ']);
    }

    if ($action === 'update') {
        $userId = (int)($data['user_id'] ?? $data['userId'] ?? 0);
        $stmt = $conn->prepare('UPDATE rh_users SET username=?, full_name=?, phone=? WHERE user_id=?');
        $stmt->bind_param('sssi', $data['username'], $data['full_name'], $data['phone'], $userId); $stmt->execute(); $stmt->close();
        auth_json(['success' => true, 'data' => load_profile_payload($conn, $userId)]);
    }

    auth_json(['success' => false, 'message' => 'Unknown action'], 400);
} catch (Throwable $e) {
    auth_json(['success' => false, 'message' => 'Server error: ' . $e->getMessage()], 500);
}
?>