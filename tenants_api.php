<?php
header("Content-Type: application/json; charset=utf-8");
ini_set('display_errors', '0');
ini_set('html_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

register_shutdown_function(function () {
    $e = error_get_last();
    if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
        http_response_code(500);
        echo json_encode([
            "success" => false,
            "ok" => false,
            "message" => "Fatal Error: " . $e["message"]
        ], JSON_UNESCAPED_UNICODE);
    }
});

require_once __DIR__ . "/db.php";
if (!isset($conn) || !$conn) {
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "ok" => false,
        "message" => "Database connection failed"
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

mysqli_set_charset($conn, "utf8mb4");
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function jexit_api($arr, $code = 200) {
    http_response_code($code);
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}

$raw = file_get_contents("php://input");
$inputJson = json_decode($raw, true);
if (!is_array($inputJson)) {
    $inputJson = [];
}

function param_api($k, $default = null) {
    global $inputJson;
    if (isset($_POST[$k])) return $_POST[$k];
    if (isset($_GET[$k])) return $_GET[$k];
    if (isset($inputJson[$k])) return $inputJson[$k];
    return $default;
}

function normalize_role_code($role) {
    $role = strtolower(trim((string)$role));
    if ($role === 'owner' || $role === 'o') return 'o';
    if ($role === 'admin' || $role === 'a') return 'a';
    return 't';
}

function has_admin_permission($conn, $tableMem, $admin_user_id, $dorm_id) {
    if ($admin_user_id <= 0 || $dorm_id <= 0) return false;

    $chk = $conn->prepare("
        SELECT membership_id
        FROM {$tableMem}
        WHERE user_id = ?
          AND dorm_id = ?
          AND approve_status = 'approved'
          AND move_out_date IS NULL
          AND role_code IN ('o', 'a')
        ORDER BY membership_id DESC
        LIMIT 1
    ");
    $chk->bind_param("ii", $admin_user_id, $dorm_id);
    $chk->execute();
    $row = $chk->get_result()->fetch_assoc();
    $chk->close();

    return !empty($row);
}

function check_admin_permission($conn, $tableMem, $admin_user_id, $dorm_id) {
    if (!has_admin_permission($conn, $tableMem, $admin_user_id, $dorm_id)) {
        jexit_api([
            "success" => false,
            "ok" => false,
            "message" => "ไม่มีสิทธิ์เข้าถึงส่วนนี้"
        ], 403);
    }
}

function fetch_pending_rooms_bundle($conn, $T_MEM, $T_USERS, $T_ROOMS, $T_BLD, $dorm_id) {
    $pending = [];
    $stmt = $conn->prepare("
        SELECT
            m.membership_id AS user_dorm_id,
            m.user_id,
            u.username,
            u.full_name,
            u.phone,
            m.created_at
        FROM {$T_MEM} m
        JOIN {$T_USERS} u ON u.user_id = m.user_id
        WHERE m.dorm_id = ?
          AND m.approve_status = 'pending'
          AND COALESCE(u.user_level, '') <> 'a'
        ORDER BY m.created_at ASC, m.membership_id ASC
    ");
    $stmt->bind_param("i", $dorm_id);
    $stmt->execute();
    $rs = $stmt->get_result();
    while ($row = $rs->fetch_assoc()) {
        $row["user_dorm_id"] = (int)$row["user_dorm_id"];
        $row["user_id"] = (int)$row["user_id"];
        $pending[] = $row;
    }
    $stmt->close();

    $rooms = [];
    $stmt2 = $conn->prepare("
        SELECT
            r.room_id,
            r.room_number,
            COALESCE(b.building_name, '') AS building,
            r.floor,
            r.tenant_id,
            r.status
        FROM {$T_ROOMS} r
        LEFT JOIN {$T_BLD} b ON b.building_id = r.building_id
        WHERE r.dorm_id = ?
          AND r.tenant_id IS NULL
          AND (r.status = 'vacant' OR r.status IS NULL OR r.status = '')
        ORDER BY COALESCE(b.building_name, '') ASC, r.floor ASC, r.room_number ASC
    ");
    $stmt2->bind_param("i", $dorm_id);
    $stmt2->execute();
    $rs2 = $stmt2->get_result();
    while ($row = $rs2->fetch_assoc()) {
        $row["room_id"] = (int)$row["room_id"];
        $row["floor"] = isset($row["floor"]) && $row["floor"] !== null ? (int)$row["floor"] : 0;
        $row["tenant_id"] = isset($row["tenant_id"]) ? (int)$row["tenant_id"] : null;
        $rooms[] = $row;
    }
    $stmt2->close();

    return [
        "pending" => $pending,
        "rooms" => $rooms
    ];
}

$T_USERS = "rh_users";
$T_MEM   = "rh_dorm_memberships";
$T_ROOMS = "rh_rooms";
$T_DORMS = "rh_dorms";
$T_BLD   = "rh_buildings";
$T_NOTI  = "rh_notifications";

$action = trim((string)param_api("action", "list"));
$dorm_id = (int)param_api("dorm_id", 0);
$admin_user_id = (int)param_api("admin_user_id", 0);
$user_id = (int)param_api("user_id", 0);

/*
|--------------------------------------------------------------------------
| list = รายชื่อผู้เช่า / ผู้ดูแล / ผู้เช่าเก่า 
|--------------------------------------------------------------------------
*/
if ($action === "list") {
    $where = "WHERE COALESCE(u.user_level, '') <> 'a'";
    $types = '';
    $params = [];

    if ($dorm_id > 0) {
        $where .= " AND m.dorm_id = ?";
        $types .= 'i';
        $params[] = $dorm_id;
    }

    // ✅ แก้ไข SQL: ครอบ MAX() ในส่วนของคอลัมน์จากตาราง m และเพิ่มความชัดเจนใน GROUP BY เพื่อให้ผ่านกฎ ONLY_FULL_GROUP_BY
    $sql = "
        SELECT
            MAX(m.membership_id) AS membership_id,
            m.user_id AS tenant_id,
            m.user_id,
            m.dorm_id,
            MAX(m.role_code) AS role_code,
            MAX(m.approve_status) AS approve_status,
            u.username,
            u.full_name,
            u.phone,
            u.user_level,
            MAX(d.dorm_name) AS dorm_name,
            
            (SELECT r_curr.room_number FROM {$T_ROOMS} r_curr WHERE r_curr.tenant_id = u.user_id AND r_curr.dorm_id = m.dorm_id LIMIT 1) AS room_number,
            (SELECT r_curr.floor FROM {$T_ROOMS} r_curr WHERE r_curr.tenant_id = u.user_id AND r_curr.dorm_id = m.dorm_id LIMIT 1) AS floor,
            (SELECT b_curr.building_name FROM {$T_ROOMS} r_curr LEFT JOIN {$T_BLD} b_curr ON b_curr.building_id = r_curr.building_id WHERE r_curr.tenant_id = u.user_id AND r_curr.dorm_id = m.dorm_id LIMIT 1) AS building,
            (SELECT b_curr.building_name FROM {$T_ROOMS} r_curr LEFT JOIN {$T_BLD} b_curr ON b_curr.building_id = r_curr.building_id WHERE r_curr.tenant_id = u.user_id AND r_curr.dorm_id = m.dorm_id LIMIT 1) AS building_name,
            (SELECT r_curr.room_id FROM {$T_ROOMS} r_curr WHERE r_curr.tenant_id = u.user_id AND r_curr.dorm_id = m.dorm_id LIMIT 1) AS room_id,

            CASE
                WHEN MAX(m.role_code) IN ('a', 'o') THEN 'admin'
                ELSE 'tenant'
            END AS role,
            CASE
                WHEN MAX(m.role_code) = 'o' THEN 'owner'
                WHEN MAX(m.role_code) = 'a' THEN 'admin'
                ELSE 'tenant'
            END AS role_in_dorm,
            
            CASE
                WHEN MAX(m.role_code) IN ('a', 'o') THEN 'active'
                WHEN EXISTS (SELECT 1 FROM {$T_ROOMS} r_chk WHERE r_chk.tenant_id = u.user_id AND r_chk.dorm_id = m.dorm_id) THEN 'active'
                ELSE 'former'
            END AS tenant_status,
            
            (
                SELECT GROUP_CONCAT(DISTINCT COALESCE(r_hist.room_number, '') ORDER BY sub_m.membership_id ASC SEPARATOR ', ')
                FROM {$T_MEM} sub_m
                LEFT JOIN {$T_ROOMS} r_hist ON sub_m.room_id = r_hist.room_id
                WHERE sub_m.user_id = u.user_id 
                  AND sub_m.dorm_id = m.dorm_id 
                  AND sub_m.approve_status = 'approved'
                  AND sub_m.room_id IS NOT NULL
            ) AS all_rooms_history,

            MIN(m.move_in_date) AS move_in_date,
            MAX(m.move_out_date) AS move_out_date
        FROM {$T_MEM} m
        INNER JOIN {$T_USERS} u ON u.user_id = m.user_id
        INNER JOIN {$T_DORMS} d ON d.dorm_id = m.dorm_id
        {$where}
        GROUP BY u.user_id, m.dorm_id
        ORDER BY
            CASE
                WHEN MAX(m.role_code) IN ('a', 'o') THEN 0
                WHEN EXISTS (SELECT 1 FROM {$T_ROOMS} r_chk WHERE r_chk.tenant_id = u.user_id AND r_chk.dorm_id = m.dorm_id) THEN 1
                ELSE 2
            END,
            COALESCE(u.full_name, u.username, '') ASC
    ";

    $st = $conn->prepare($sql);
    if (!$st) {
        jexit_api(['ok' => false, 'success' => false, 'message' => 'prepare failed: ' . $conn->error], 500);
    }

    if (!empty($params)) {
        $st->bind_param($types, ...$params);
    }

    $st->execute();
    $res = $st->get_result();

    $rows = [];
    while ($row = $res->fetch_assoc()) {
        $row['membership_id'] = isset($row['membership_id']) ? (int)$row['membership_id'] : null;
        $row['tenant_id']     = isset($row['tenant_id']) ? (int)$row['tenant_id'] : null;
        $row['user_id']       = isset($row['user_id']) ? (int)$row['user_id'] : null;
        $row['dorm_id']       = isset($row['dorm_id']) ? (int)$row['dorm_id'] : null;
        $row['room_id']       = isset($row['room_id']) && $row['room_id'] !== null ? (int)$row['room_id'] : 0;
        $row['floor']         = isset($row['floor']) && $row['floor'] !== null ? (int)$row['floor'] : null;
        $rows[] = $row;
    }
    $st->close();

    $response = [
        'ok' => true,
        'success' => true,
        'dorm_id' => $dorm_id,
        'count' => count($rows),
        'data' => $rows,
        'pending' => [],
        'rooms' => [],
    ];

    if ($dorm_id > 0 && $admin_user_id > 0 && has_admin_permission($conn, $T_MEM, $admin_user_id, $dorm_id)) {
        $bundle = fetch_pending_rooms_bundle($conn, $T_MEM, $T_USERS, $T_ROOMS, $T_BLD, $dorm_id);
        $response['pending'] = $bundle['pending'];
        $response['rooms'] = $bundle['rooms'];
    }

    jexit_api($response);
}

/*
|--------------------------------------------------------------------------
| get = รายละเอียดคนเดียว 
|--------------------------------------------------------------------------
*/
if ($action === "get") {
    if ($user_id <= 0) {
        jexit_api(['ok' => false, 'success' => false, 'message' => 'missing user_id'], 400);
    }

    $whereDorm = '';
    $types = 'i';
    $params = [$user_id];

    if ($dorm_id > 0) {
        $whereDorm = " AND m.dorm_id = ? ";
        $types .= 'i';
        $params[] = $dorm_id;
    }

    // ✅ แก้ไข SQL: ครอบ MAX() คอลัมน์ที่ไม่ได้อยู่ใน GROUP BY เช่นกัน เพื่อความปลอดภัยในส่วน "get"
    $sql = "
        SELECT
            u.user_id,
            u.username,
            u.full_name,
            u.phone,
            u.user_level,
            MAX(m.membership_id) AS membership_id,
            m.dorm_id,
            MAX(d.dorm_name) AS dorm_name,
            MAX(m.role_code) AS role_code,
            MAX(m.approve_status) AS approve_status,
            CASE
                WHEN MAX(m.role_code) = 'o' THEN 'owner'
                WHEN MAX(m.role_code) = 'a' THEN 'admin'
                ELSE 'tenant'
            END AS role_in_dorm,
            CASE
                WHEN MAX(m.role_code) IN ('a', 'o') THEN 'active'
                WHEN EXISTS (SELECT 1 FROM {$T_ROOMS} r_chk WHERE r_chk.tenant_id = u.user_id AND r_chk.dorm_id = m.dorm_id) THEN 'active'
                ELSE 'former'
            END AS tenant_status,
            
            (SELECT r_curr.room_number FROM {$T_ROOMS} r_curr WHERE r_curr.tenant_id = u.user_id AND r_curr.dorm_id = m.dorm_id LIMIT 1) AS room_number,
            (SELECT r_curr.room_id FROM {$T_ROOMS} r_curr WHERE r_curr.tenant_id = u.user_id AND r_curr.dorm_id = m.dorm_id LIMIT 1) AS room_id,
            (SELECT b_curr.building_name FROM {$T_ROOMS} r_curr LEFT JOIN {$T_BLD} b_curr ON b_curr.building_id = r_curr.building_id WHERE r_curr.tenant_id = u.user_id AND r_curr.dorm_id = m.dorm_id LIMIT 1) AS building,
            
            (
                SELECT GROUP_CONCAT(DISTINCT COALESCE(r_hist.room_number, '') ORDER BY sub_m.membership_id ASC SEPARATOR ', ')
                FROM {$T_MEM} sub_m
                LEFT JOIN {$T_ROOMS} r_hist ON sub_m.room_id = r_hist.room_id
                WHERE sub_m.user_id = u.user_id 
                  AND sub_m.dorm_id = m.dorm_id 
                  AND sub_m.approve_status = 'approved'
                  AND sub_m.room_id IS NOT NULL
            ) AS all_rooms_history,
            
            MIN(m.move_in_date) AS move_in_date,
            MAX(m.move_out_date) AS move_out_date
        FROM {$T_USERS} u
        LEFT JOIN {$T_MEM} m ON m.user_id = u.user_id
        LEFT JOIN {$T_DORMS} d ON d.dorm_id = m.dorm_id
        WHERE u.user_id = ?
          AND COALESCE(u.user_level, '') <> 'a'
        {$whereDorm}
        GROUP BY u.user_id, m.dorm_id
        LIMIT 1
    ";

    $st = $conn->prepare($sql);
    if (!$st) {
        jexit_api(['ok' => false, 'success' => false, 'message' => 'prepare failed: ' . $conn->error], 500);
    }

    $st->bind_param($types, ...$params);
    $st->execute();
    $res = $st->get_result();
    $row = $res->fetch_assoc();
    $st->close();

    if (!$row) {
        jexit_api(['ok' => false, 'success' => false, 'message' => 'ไม่พบข้อมูลผู้ใช้'], 404);
    }

    $row['user_id'] = (int)$row['user_id'];
    $row['membership_id'] = isset($row['membership_id']) ? (int)$row['membership_id'] : 0;
    $row['dorm_id'] = isset($row['dorm_id']) ? (int)$row['dorm_id'] : 0;
    $row['room_id'] = isset($row['room_id']) && $row['room_id'] !== null ? (int)$row['room_id'] : 0;

    jexit_api([
        'ok' => true,
        'success' => true,
        'data' => $row,
    ]);
}

/*
|--------------------------------------------------------------------------
| remove = ย้ายออก / เก็บเป็นประวัติผู้เช่าเก่า
|--------------------------------------------------------------------------
*/
if ($action === "remove") {
    $target_user_id = (int)param_api('user_id', 0);

    if ($target_user_id <= 0 || $dorm_id <= 0) {
        jexit_api(['ok' => false, 'success' => false, 'message' => 'ข้อมูลไม่ครบถ้วน'], 400);
    }

    $conn->begin_transaction();
    try {
        $findMember = $conn->prepare("SELECT membership_id, room_id FROM {$T_MEM} WHERE user_id = ? AND dorm_id = ? AND approve_status = 'approved' AND role_code = 't' AND move_out_date IS NULL ORDER BY membership_id DESC LIMIT 1");
        $findMember->bind_param('ii', $target_user_id, $dorm_id);
        $findMember->execute();
        $member = $findMember->get_result()->fetch_assoc();
        $findMember->close();

        if (!$member) {
            throw new Exception('ไม่พบข้อมูลสมาชิกที่เป็นผู้เช่าปัจจุบัน');
        }

        $membership_id = (int)$member['membership_id'];
        $room_id = isset($member['room_id']) ? (int)$member['room_id'] : 0;

        if ($room_id > 0) {
            $updRoom = $conn->prepare("UPDATE {$T_ROOMS} SET tenant_id = NULL, status = 'vacant' WHERE room_id = ? AND dorm_id = ?");
            $updRoom->bind_param('ii', $room_id, $dorm_id);
            $updRoom->execute();
            $updRoom->close();
        } else {
            $findRoom = $conn->prepare("SELECT room_id FROM {$T_ROOMS} WHERE dorm_id = ? AND tenant_id = ? LIMIT 1");
            $findRoom->bind_param('ii', $dorm_id, $target_user_id);
            $findRoom->execute();
            $room = $findRoom->get_result()->fetch_assoc();
            $findRoom->close();

            if ($room && !empty($room['room_id'])) {
                $room_id = (int)$room['room_id'];

                $updRoom = $conn->prepare("UPDATE {$T_ROOMS} SET tenant_id = NULL, status = 'vacant' WHERE room_id = ? AND dorm_id = ?");
                $updRoom->bind_param('ii', $room_id, $dorm_id);
                $updRoom->execute();
                $updRoom->close();
            }
        }

        $updMember = $conn->prepare("UPDATE {$T_MEM} SET move_out_date = NOW() WHERE membership_id = ? AND dorm_id = ?");
        $updMember->bind_param('ii', $membership_id, $dorm_id);
        $updMember->execute();

        if ($updMember->affected_rows <= 0) {
            $updMember->close();
            throw new Exception('ไม่สามารถอัปเดตวันออกจากห้องได้');
        }
        $updMember->close();

        $conn->commit();

        jexit_api([
            'ok' => true,
            'success' => true,
            'message' => 'ย้ายผู้เช่าไปยังประวัติผู้เช่าเก่าเรียบร้อยแล้ว',
        ]);
    } catch (Throwable $e) {
        $conn->rollback();
        jexit_api(['ok' => false, 'success' => false, 'message' => 'Error: ' . $e->getMessage()], 500);
    }
}

/*
|--------------------------------------------------------------------------
| move_room = ย้ายห้องพักภายในหอเดิม 
|--------------------------------------------------------------------------
*/
if ($action === "move_room") {
    check_admin_permission($conn, $T_MEM, $admin_user_id, $dorm_id);

    $target_user_id = (int)param_api("user_id", 0);
    $old_room_id    = (int)param_api("old_room_id", 0);
    $new_room_id    = (int)param_api("new_room_id", 0);

    if ($target_user_id <= 0 || $dorm_id <= 0 || $old_room_id <= 0 || $new_room_id <= 0) {
        jexit_api(["success" => false, "ok" => false, "message" => "ข้อมูลที่ส่งมาทำรายการย้ายห้องไม่ครบถ้วน"], 400);
    }

    $conn->begin_transaction();
    try {
        $stmt1 = $conn->prepare("UPDATE {$T_ROOMS} SET status = 'vacant', tenant_id = NULL WHERE room_id = ? AND dorm_id = ?");
        $stmt1->bind_param("ii", $old_room_id, $dorm_id);
        $stmt1->execute();
        $stmt1->close();

        $chkRoom = $conn->prepare("SELECT tenant_id, status, room_number FROM {$T_ROOMS} WHERE room_id = ? AND dorm_id = ? LIMIT 1");
        $chkRoom->bind_param("ii", $new_room_id, $dorm_id);
        $chkRoom->execute();
        $roomRow = $chkRoom->get_result()->fetch_assoc();
        $chkRoom->close();

        if (!$roomRow) throw new Exception("ไม่พบข้อมูลห้องพักห้องใหม่ในระบบ");
        if (!empty($roomRow["tenant_id"])) throw new Exception("ห้องใหม่มีผู้เช่าคนอื่นพักอยู่แล้ว");
        if (($roomRow["status"] ?? "") === "maintenance") throw new Exception("ห้องใหม่ปิดปรับปรุงซ่อมบำรุงอยู่");

        $newRoomNumber = (string)$roomRow["room_number"];

        $stmt2 = $conn->prepare("UPDATE {$T_ROOMS} SET status = 'occupied', tenant_id = ? WHERE room_id = ? AND dorm_id = ?");
        $stmt2->bind_param("iii", $target_user_id, $new_room_id, $dorm_id);
        $stmt2->execute();
        $stmt2->close();

        $stmt3 = $conn->prepare("UPDATE {$T_MEM} SET move_out_date = NOW() WHERE user_id = ? AND room_id = ? AND move_out_date IS NULL AND approve_status = 'approved'");
        $stmt3->bind_param("ii", $target_user_id, $old_room_id);
        $stmt3->execute();
        $stmt3->close();

        $stmt4 = $conn->prepare("INSERT INTO {$T_MEM} (user_id, dorm_id, room_id, role_code, approve_status, move_in_date) VALUES (?, ?, ?, 't', 'approved', NOW())");
        $stmt4->bind_param("iii", $target_user_id, $dorm_id, $new_room_id);
        $stmt4->execute();
        $stmt4->close();

        $msgNoti = "ผู้ดูแลระบบได้ทำการย้ายห้องพักของคุณไปยัง ห้อง " . $newRoomNumber . " เรียบร้อยแล้ว";
        $stmtN = $conn->prepare("INSERT INTO {$T_NOTI} (user_id, dorm_id, type_id, message, is_read) VALUES (?, ?, 1, ?, 0)");
        $stmtN->bind_param("iis", $target_user_id, $dorm_id, $msgNoti);
        $stmtN->execute();
        $stmtN->close();

        $conn->commit();
        jexit_api(["success" => true, "ok" => true, "message" => "ดำเนินการย้ายไปยังห้อง " . $newRoomNumber . " สำเร็จเรียบร้อยแล้ว"]);
    } catch (Throwable $e) {
        $conn->rollback();
        jexit_api(["success" => false, "ok" => false, "message" => $e->getMessage()], 500);
    }
}

/*
|--------------------------------------------------------------------------
| pending_list = รายการรออนุมัติ + ห้องว่าง
|--------------------------------------------------------------------------
*/
if ($action === "pending_list" || $action === "pending") {
    if ($dorm_id <= 0 || $admin_user_id <= 0) {
        jexit_api(["success" => false, "ok" => false, "message" => "ข้อมูล dorm_id หรือ admin_user_id ไม่ครบ"], 400);
    }
    check_admin_permission($conn, $T_MEM, $admin_user_id, $dorm_id);
    try {
        jexit_api(array_merge(["success" => true, "ok" => true], fetch_pending_rooms_bundle($conn, $T_MEM, $T_USERS, $T_ROOMS, $T_BLD, $dorm_id)));
    } catch (Throwable $e) {
        jexit_api(["success" => false, "ok" => false, "message" => $e->getMessage()], 500);
    }
}

/*
|--------------------------------------------------------------------------
| approve = อนุมัติผู้เช่า / ผู้ดูแล
|--------------------------------------------------------------------------
*/
if ($action === "approve") {
    if ($dorm_id <= 0 || $admin_user_id <= 0) {
        jexit_api(["success" => false, "ok" => false, "message" => "ข้อมูลไม่ครบถ้วน"], 400);
    }

    check_admin_permission($conn, $T_MEM, $admin_user_id, $dorm_id);

    $user_dorm_id = (int)param_api("user_dorm_id", 0);
    $room_id = (int)param_api("room_id", 0);
    $role_code = normalize_role_code(param_api("role", "tenant"));
    $move_in_date = trim((string)param_api("move_in_date", ""));

    if ($user_dorm_id <= 0) jexit_api(["success" => false, "message" => "ข้อมูลคำขอไม่ถูกต้อง"], 400);
    if ($role_code === "t" && $room_id <= 0) jexit_api(["success" => false, "message" => "กรุณาเลือกห้องพัก"], 400);

    $conn->begin_transaction();
    try {
        $stMem = $conn->prepare("SELECT user_id FROM {$T_MEM} WHERE membership_id = ? AND dorm_id = ? AND approve_status = 'pending' LIMIT 1");
        $stMem->bind_param("ii", $user_dorm_id, $dorm_id);
        $stMem->execute();
        $memRow = $stMem->get_result()->fetch_assoc();
        $stMem->close();

        if (!$memRow) throw new Exception("ไม่พบคำขอรออนุมัติในระบบ");
        $target_user_id = (int)$memRow["user_id"];

        if ($role_code === "t") {
            if ($move_in_date === "") $move_in_date = date("Y-m-d");
            $move_in_db = $move_in_date . " 00:00:00";

            $stRoom = $conn->prepare("SELECT room_number FROM {$T_ROOMS} WHERE room_id = ? AND dorm_id = ? AND tenant_id IS NULL LIMIT 1");
            $stRoom->bind_param("ii", $room_id, $dorm_id);
            $stRoom->execute();
            $rRow = $stRoom->get_result()->fetch_assoc();
            $stRoom->close();
            if (!$rRow) throw new Exception("ห้องไม่ว่างหรือไม่มีอยู่จริง");

            $stRoomUpd = $conn->prepare("UPDATE {$T_ROOMS} SET tenant_id = ?, status = 'occupied' WHERE room_id = ? AND dorm_id = ?");
            $stRoomUpd->bind_param("iii", $target_user_id, $room_id, $dorm_id);
            $stRoomUpd->execute();
            $stRoomUpd->close();

            $st1 = $conn->prepare("UPDATE {$T_MEM} SET approve_status = 'approved', role_code = ?, room_id = ?, move_in_date = ?, move_out_date = NULL WHERE membership_id = ? AND dorm_id = ?");
            $st1->bind_param("sisii", $role_code, $room_id, $move_in_db, $user_dorm_id, $dorm_id);
        } else {
            $st1 = $conn->prepare("UPDATE {$T_MEM} SET approve_status = 'approved', role_code = ?, room_id = NULL, move_in_date = NULL, move_out_date = NULL WHERE membership_id = ? AND dorm_id = ?");
            $st1->bind_param("sii", $role_code, $user_dorm_id, $dorm_id);
        }
        $st1->execute();
        $st1->close();

        $msg = $role_code === "a" ? "คำขอได้รับการอนุมัติเป็นผู้ดูแลแล้ว" : "คำขอเข้าพักได้รับการอนุมัติแล้ว ห้อง " . $rRow["room_number"];
        $stN = $conn->prepare("INSERT INTO {$T_NOTI} (user_id, dorm_id, type_id, message, is_read) VALUES (?, ?, 1, ?, 0)");
        $stN->bind_param("iis", $target_user_id, $dorm_id, $msg);
        $stN->execute();
        $stN->close();

        $conn->commit();
        jexit_api(["success" => true, "ok" => true, "message" => "อนุมัติเรียบร้อยแล้ว"]);
    } catch (Throwable $e) {
        $conn->rollback();
        jexit_api(["success" => false, "message" => $e->getMessage()], 500);
    }
}

/*
|--------------------------------------------------------------------------
| reject = ปฏิเสธคำขอ
|--------------------------------------------------------------------------
*/
if ($action === "reject") {
    check_admin_permission($conn, $T_MEM, $admin_user_id, $dorm_id);
    $user_dorm_id = (int)param_api("user_dorm_id", 0);
    
    $stGet = $conn->prepare("SELECT user_id FROM {$T_MEM} WHERE membership_id = ? AND dorm_id = ? LIMIT 1");
    $stGet->bind_param("ii", $user_dorm_id, $dorm_id);
    $stGet->execute();
    $m = $stGet->get_result()->fetch_assoc();
    $stGet->close();

    if ($m) {
        $st = $conn->prepare("UPDATE {$T_MEM} SET approve_status = 'rejected' WHERE membership_id = ? AND dorm_id = ?");
        $st->bind_param("ii", $user_dorm_id, $dorm_id);
        $st->execute();
        $st->close();

        $stN = $conn->prepare("INSERT INTO {$T_NOTI} (user_id, dorm_id, type_id, message, is_read) VALUES (?, ?, 1, 'คำขอเข้าหอพักถูกปฏิเสธ', 0)");
        $stN->bind_param("ii", $m["user_id"], $dorm_id);
        $stN->execute();
        $stN->close();
        jexit_api(["success" => true, "ok" => true, "message" => "ปฏิเสธคำขอเรียบร้อยแล้ว"]);
    }
    jexit_api(["success" => false, "message" => "ไม่พบรายการที่ต้องการปฏิเสธ"], 404);
}

jexit_api(["success" => false, "message" => "ไม่พบ action ที่ระบุ"], 400);
?>