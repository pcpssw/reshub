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
            r.floor
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
| และถ้าเป็นแอดมิน จะส่ง pending + rooms กลับไปด้วย เพื่อรองรับหน้าเดิม
|--------------------------------------------------------------------------
*/
if ($action === "list") {
    $where = "WHERE COALESCE(u.user_level, '') <> 'a'
              AND (m.approve_status = 'approved' OR m.move_out_date IS NOT NULL)";
    $types = '';
    $params = [];

    if ($dorm_id > 0) {
        $where .= " AND m.dorm_id = ?";
        $types .= 'i';
        $params[] = $dorm_id;
    }

    $sql = "
        SELECT
            m.membership_id,
            m.membership_id AS tenant_id,
            m.user_id,
            m.dorm_id,
            COALESCE(m.room_id, r2.room_id, 0) AS room_id,
            m.role_code,
            m.approve_status,
            u.username,
            u.full_name,
            u.phone,
            u.user_level,
            COALESCE(r1.room_number, r2.room_number) AS room_number,
            COALESCE(r1.floor, r2.floor) AS floor,
            COALESCE(b1.building_name, b2.building_name, '') AS building,
            COALESCE(b1.building_name, b2.building_name, '') AS building_name,
            d.dorm_name,
            CASE
                WHEN m.role_code IN ('a', 'o') THEN 'admin'
                ELSE 'tenant'
            END AS role,
            CASE
                WHEN m.role_code = 'o' THEN 'owner'
                WHEN m.role_code = 'a' THEN 'admin'
                ELSE 'tenant'
            END AS role_in_dorm,
            CASE
                WHEN m.move_out_date IS NOT NULL THEN 'former'
                WHEN m.approve_status = 'approved' THEN 'active'
                ELSE 'waiting'
            END AS tenant_status,
            CASE
                WHEN m.move_in_date IS NOT NULL THEN DATE_FORMAT(m.move_in_date, '%Y-%m-%d')
                ELSE NULL
            END AS move_in_date,
            CASE
                WHEN m.move_out_date IS NOT NULL THEN DATE_FORMAT(m.move_out_date, '%Y-%m-%d')
                ELSE NULL
            END AS move_out_date
        FROM {$T_MEM} m
        INNER JOIN {$T_USERS} u
            ON u.user_id = m.user_id
        INNER JOIN {$T_DORMS} d
            ON d.dorm_id = m.dorm_id
        LEFT JOIN {$T_ROOMS} r1
            ON r1.room_id = m.room_id
        LEFT JOIN {$T_BLD} b1
            ON b1.building_id = r1.building_id
        LEFT JOIN {$T_ROOMS} r2
            ON r2.tenant_id = m.user_id
           AND r2.dorm_id = m.dorm_id
           AND m.approve_status = 'approved'
           AND m.move_out_date IS NULL
        LEFT JOIN {$T_BLD} b2
            ON b2.building_id = r2.building_id
        {$where}
        ORDER BY
            CASE
                WHEN m.role_code IN ('a', 'o') THEN 0
                WHEN m.move_out_date IS NOT NULL THEN 2
                ELSE 1
            END,
            COALESCE(b1.building_name, b2.building_name, ''),
            COALESCE(r1.floor, r2.floor, 0),
            COALESCE(r1.room_number, r2.room_number, ''),
            COALESCE(u.full_name, u.username, ''),
            COALESCE(m.move_in_date, m.created_at) DESC,
            m.membership_id DESC
    ";

    $st = $conn->prepare($sql);
    if (!$st) {
        jexit_api([
            'ok' => false,
            'success' => false,
            'message' => 'prepare failed: ' . $conn->error
        ], 500);
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
        jexit_api([
            'ok' => false,
            'success' => false,
            'message' => 'missing user_id'
        ], 400);
    }

    $whereDorm = '';
    $types = 'i';
    $params = [$user_id];

    if ($dorm_id > 0) {
        $whereDorm = " AND m.dorm_id = ? ";
        $types .= 'i';
        $params[] = $dorm_id;
    }

    $sql = "
        SELECT
            u.user_id,
            u.username,
            u.full_name,
            u.phone,
            u.user_level,
            m.membership_id,
            m.dorm_id,
            d.dorm_name,
            m.role_code,
            m.approve_status,
            CASE
                WHEN m.role_code = 'o' THEN 'owner'
                WHEN m.role_code = 'a' THEN 'admin'
                ELSE 'tenant'
            END AS role_in_dorm,
            CASE
                WHEN m.move_out_date IS NOT NULL THEN 'former'
                WHEN m.approve_status = 'approved' THEN 'active'
                ELSE 'waiting'
            END AS tenant_status,
            COALESCE(b1.building_name, b2.building_name, '') AS building,
            COALESCE(m.room_id, r2.room_id, 0) AS room_id,
            COALESCE(r1.room_number, r2.room_number) AS room_number,
            CASE
                WHEN m.move_in_date IS NOT NULL THEN DATE_FORMAT(m.move_in_date, '%Y-%m-%d')
                ELSE NULL
            END AS move_in_date,
            CASE
                WHEN m.move_out_date IS NOT NULL THEN DATE_FORMAT(m.move_out_date, '%Y-%m-%d')
                ELSE NULL
            END AS move_out_date
        FROM {$T_USERS} u
        LEFT JOIN {$T_MEM} m
            ON m.user_id = u.user_id
           AND (m.approve_status = 'approved' OR m.move_out_date IS NOT NULL)
        LEFT JOIN {$T_DORMS} d
            ON d.dorm_id = m.dorm_id
        LEFT JOIN {$T_ROOMS} r1
            ON r1.room_id = m.room_id
        LEFT JOIN {$T_BLD} b1
            ON b1.building_id = r1.building_id
        LEFT JOIN {$T_ROOMS} r2
            ON r2.tenant_id = u.user_id
           AND r2.dorm_id = m.dorm_id
           AND m.approve_status = 'approved'
           AND m.move_out_date IS NULL
        LEFT JOIN {$T_BLD} b2
            ON b2.building_id = r2.building_id
        WHERE u.user_id = ?
          AND COALESCE(u.user_level, '') <> 'a'
        {$whereDorm}
        ORDER BY
            CASE
                WHEN m.move_out_date IS NULL AND m.approve_status = 'approved' THEN 0
                ELSE 1
            END,
            COALESCE(m.move_in_date, m.created_at) DESC,
            m.membership_id DESC
        LIMIT 1
    ";

    $st = $conn->prepare($sql);
    if (!$st) {
        jexit_api([
            'ok' => false,
            'success' => false,
            'message' => 'prepare failed: ' . $conn->error
        ], 500);
    }

    $st->bind_param($types, ...$params);
    $st->execute();
    $res = $st->get_result();
    $row = $res->fetch_assoc();
    $st->close();

    if (!$row) {
        jexit_api([
            'ok' => false,
            'success' => false,
            'message' => 'ไม่พบข้อมูลผู้ใช้'
        ], 404);
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

    if ($target_user_id <= 0) {
        jexit_api([
            'ok' => false,
            'success' => false,
            'message' => 'missing user_id'
        ], 400);
    }

    if ($dorm_id <= 0) {
        jexit_api([
            'ok' => false,
            'success' => false,
            'message' => 'missing dorm_id'
        ], 400);
    }

    $conn->begin_transaction();
    try {
        $findMember = $conn->prepare("
            SELECT membership_id, room_id
            FROM {$T_MEM}
            WHERE user_id = ?
              AND dorm_id = ?
              AND approve_status = 'approved'
              AND role_code = 't'
              AND move_out_date IS NULL
            ORDER BY membership_id DESC
            LIMIT 1
        ");
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
            $updRoom = $conn->prepare("
                UPDATE {$T_ROOMS}
                SET tenant_id = NULL, status = 'vacant'
                WHERE room_id = ? AND dorm_id = ?
            ");
            $updRoom->bind_param('ii', $room_id, $dorm_id);
            $updRoom->execute();
            $updRoom->close();
        } else {
            $findRoom = $conn->prepare("
                SELECT room_id
                FROM {$T_ROOMS}
                WHERE dorm_id = ? AND tenant_id = ?
                LIMIT 1
            ");
            $findRoom->bind_param('ii', $dorm_id, $target_user_id);
            $findRoom->execute();
            $roomRes = $findRoom->get_result();
            $room = $roomRes->fetch_assoc();
            $findRoom->close();

            if ($room && !empty($room['room_id'])) {
                $room_id = (int)$room['room_id'];

                $updRoom = $conn->prepare("
                    UPDATE {$T_ROOMS}
                    SET tenant_id = NULL, status = 'vacant'
                    WHERE room_id = ? AND dorm_id = ?
                ");
                $updRoom->bind_param('ii', $room_id, $dorm_id);
                $updRoom->execute();
                $updRoom->close();
            }
        }

        $updMember = $conn->prepare("
            UPDATE {$T_MEM}
            SET move_out_date = NOW()
            WHERE membership_id = ? AND dorm_id = ?
        ");
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

        jexit_api([
            'ok' => false,
            'success' => false,
            'message' => 'Error: ' . $e->getMessage(),
        ], 500);
    }
}

/*
|--------------------------------------------------------------------------
| pending_list = รายการรออนุมัติ + ห้องว่าง
|--------------------------------------------------------------------------
*/
if ($action === "pending_list" || $action === "pending") {
    if ($dorm_id <= 0 || $admin_user_id <= 0) {
        jexit_api([
            "success" => false,
            "ok" => false,
            "message" => "ข้อมูล dorm_id หรือ admin_user_id ไม่ครบ"
        ], 400);
    }

    check_admin_permission($conn, $T_MEM, $admin_user_id, $dorm_id);

    try {
        $bundle = fetch_pending_rooms_bundle($conn, $T_MEM, $T_USERS, $T_ROOMS, $T_BLD, $dorm_id);

        jexit_api([
            "success" => true,
            "ok" => true,
            "pending" => $bundle["pending"],
            "rooms" => $bundle["rooms"]
        ]);
    } catch (Throwable $e) {
        jexit_api([
            "success" => false,
            "ok" => false,
            "message" => $e->getMessage()
        ], 500);
    }
}

/*
|--------------------------------------------------------------------------
| approve = อนุมัติผู้เช่า / ผู้ดูแล
|--------------------------------------------------------------------------
*/
if ($action === "approve") {
    if ($dorm_id <= 0 || $admin_user_id <= 0) {
        jexit_api([
            "success" => false,
            "ok" => false,
            "message" => "ข้อมูล dorm_id หรือ admin_user_id ไม่ครบ"
        ], 400);
    }

    check_admin_permission($conn, $T_MEM, $admin_user_id, $dorm_id);

    $user_dorm_id = (int)param_api("user_dorm_id", 0);
    $target_user_id = (int)param_api("user_id", 0);
    $room_id = (int)param_api("room_id", 0);
    $role_selected = trim((string)param_api("role", "tenant"));
    $role_code = normalize_role_code($role_selected);
    $move_in_date = trim((string)param_api("move_in_date", ""));

    if ($user_dorm_id <= 0) {
        jexit_api([
            "success" => false,
            "ok" => false,
            "message" => "ข้อมูล user_dorm_id ไม่ถูกต้อง"
        ], 400);
    }

    if ($role_code === "t" && $room_id <= 0) {
        jexit_api([
            "success" => false,
            "ok" => false,
            "message" => "กรุณาเลือกห้องพัก"
        ], 400);
    }

    if ($move_in_date !== "") {
        $dt = DateTime::createFromFormat("Y-m-d", $move_in_date);
        if (!$dt || $dt->format("Y-m-d") !== $move_in_date) {
            jexit_api([
                "success" => false,
                "ok" => false,
                "message" => "รูปแบบ move_in_date ไม่ถูกต้อง ต้องเป็น YYYY-MM-DD"
            ], 400);
        }
    }

    $conn->begin_transaction();
    try {
        $stMem = $conn->prepare("
            SELECT membership_id, user_id, dorm_id, approve_status
            FROM {$T_MEM}
            WHERE membership_id = ? AND dorm_id = ?
            LIMIT 1
        ");
        $stMem->bind_param("ii", $user_dorm_id, $dorm_id);
        $stMem->execute();
        $memRow = $stMem->get_result()->fetch_assoc();
        $stMem->close();

        if (!$memRow) {
            throw new Exception("ไม่พบคำขอที่ต้องการอนุมัติ");
        }

        if (($memRow["approve_status"] ?? "") !== "pending") {
            throw new Exception("รายการนี้ไม่อยู่สถานะ pending");
        }

        $target_user_id = (int)$memRow["user_id"];

        $stDup = $conn->prepare("
            SELECT membership_id
            FROM {$T_MEM}
            WHERE user_id = ?
              AND dorm_id = ?
              AND approve_status = 'approved'
              AND move_out_date IS NULL
              AND membership_id <> ?
            LIMIT 1
        ");
        $stDup->bind_param("iii", $target_user_id, $dorm_id, $user_dorm_id);
        $stDup->execute();
        $dupRow = $stDup->get_result()->fetch_assoc();
        $stDup->close();

        if ($dupRow) {
            throw new Exception("ผู้ใช้นี้มีสถานะอยู่ในหอนี้แล้ว");
        }

        $move_in_db = null;
        $roomLabelForMessage = "";

        if ($role_code === "t") {
            if ($move_in_date === "") {
                $move_in_date = date("Y-m-d");
            }
            $move_in_db = $move_in_date . " 00:00:00";

            $stRoom = $conn->prepare("
                SELECT room_id, tenant_id, status, room_number
                FROM {$T_ROOMS}
                WHERE room_id = ? AND dorm_id = ?
                LIMIT 1
            ");
            $stRoom->bind_param("ii", $room_id, $dorm_id);
            $stRoom->execute();
            $roomRow = $stRoom->get_result()->fetch_assoc();
            $stRoom->close();

            if (!$roomRow) {
                throw new Exception("ไม่พบห้องพักที่เลือก");
            }

            if (!empty($roomRow["tenant_id"])) {
                throw new Exception("ห้องนี้มีผู้เช่าแล้ว");
            }

            if (($roomRow["status"] ?? "") === "maintenance") {
                throw new Exception("ห้องนี้อยู่ระหว่างซ่อมบำรุง");
            }

            $roomLabelForMessage = (string)($roomRow["room_number"] ?? $room_id);

            $stExistRoom = $conn->prepare("
                SELECT room_id
                FROM {$T_ROOMS}
                WHERE dorm_id = ? AND tenant_id = ?
                LIMIT 1
            ");
            $stExistRoom->bind_param("ii", $dorm_id, $target_user_id);
            $stExistRoom->execute();
            $existRoomRow = $stExistRoom->get_result()->fetch_assoc();
            $stExistRoom->close();

            if ($existRoomRow && (int)$existRoomRow["room_id"] !== $room_id) {
                throw new Exception("ผู้ใช้นี้มีห้องพักอยู่แล้ว");
            }

            $stRoomUpd = $conn->prepare("
                UPDATE {$T_ROOMS}
                SET tenant_id = ?, status = 'occupied'
                WHERE room_id = ? AND dorm_id = ?
            ");
            $stRoomUpd->bind_param("iii", $target_user_id, $room_id, $dorm_id);
            $stRoomUpd->execute();
            $stRoomUpd->close();

            $st1 = $conn->prepare("
                UPDATE {$T_MEM}
                SET approve_status = 'approved',
                    role_code = ?,
                    room_id = ?,
                    move_in_date = ?,
                    move_out_date = NULL
                WHERE membership_id = ? AND dorm_id = ?
            ");
            $st1->bind_param("sisii", $role_code, $room_id, $move_in_db, $user_dorm_id, $dorm_id);
            $st1->execute();
            $st1->close();
        } else {
            $st1 = $conn->prepare("
                UPDATE {$T_MEM}
                SET approve_status = 'approved',
                    role_code = ?,
                    room_id = NULL,
                    move_in_date = NULL,
                    move_out_date = NULL
                WHERE membership_id = ? AND dorm_id = ?
            ");
            $st1->bind_param("sii", $role_code, $user_dorm_id, $dorm_id);
            $st1->execute();
            $st1->close();
        }

        $message = $role_code === "a"
            ? "คำขอเข้าร่วมหอพักของคุณได้รับการอนุมัติเป็นผู้ดูแลแล้ว"
            : "คำขอเข้าพักของคุณได้รับการอนุมัติแล้ว ห้อง " . $roomLabelForMessage;

        $stN = $conn->prepare("
            INSERT INTO {$T_NOTI} (user_id, dorm_id, type_id, message, is_read)
            VALUES (?, ?, 1, ?, 0)
        ");
        $stN->bind_param("iis", $target_user_id, $dorm_id, $message);
        $stN->execute();
        $stN->close();

        $conn->commit();

        jexit_api([
            "success" => true,
            "ok" => true,
            "message" => "อนุมัติเรียบร้อยแล้ว",
            "user_dorm_id" => $user_dorm_id,
            "user_id" => $target_user_id,
            "room_id" => $room_id,
            "move_in_date" => $move_in_date
        ]);
    } catch (Throwable $e) {
        $conn->rollback();

        jexit_api([
            "success" => false,
            "ok" => false,
            "message" => $e->getMessage()
        ], 500);
    }
}

/*
|--------------------------------------------------------------------------
| reject = ปฏิเสธคำขอ
|--------------------------------------------------------------------------
*/
if ($action === "reject") {
    if ($dorm_id <= 0 || $admin_user_id <= 0) {
        jexit_api([
            "success" => false,
            "ok" => false,
            "message" => "ข้อมูล dorm_id หรือ admin_user_id ไม่ครบ"
        ], 400);
    }

    check_admin_permission($conn, $T_MEM, $admin_user_id, $dorm_id);

    $user_dorm_id = (int)param_api("user_dorm_id", 0);
    if ($user_dorm_id <= 0) {
        jexit_api([
            "success" => false,
            "ok" => false,
            "message" => "ID ไม่ถูกต้อง"
        ], 400);
    }

    try {
        $stGet = $conn->prepare("
            SELECT membership_id, user_id
            FROM {$T_MEM}
            WHERE membership_id = ? AND dorm_id = ?
            LIMIT 1
        ");
        $stGet->bind_param("ii", $user_dorm_id, $dorm_id);
        $stGet->execute();
        $m = $stGet->get_result()->fetch_assoc();
        $stGet->close();

        if (!$m) {
            jexit_api([
                "success" => false,
                "ok" => false,
                "message" => "ไม่พบรายการ"
            ], 404);
        }

        $st = $conn->prepare("
            UPDATE {$T_MEM}
            SET approve_status = 'rejected'
            WHERE membership_id = ? AND dorm_id = ?
        ");
        $st->bind_param("ii", $user_dorm_id, $dorm_id);
        $ok = $st->execute();
        $st->close();

        if (!$ok) {
            jexit_api([
                "success" => false,
                "ok" => false,
                "message" => "ไม่สามารถบันทึกได้"
            ], 500);
        }

        $msg = "คำขอเข้าร่วมหอพักของคุณถูกปฏิเสธ";
        $stN = $conn->prepare("
            INSERT INTO {$T_NOTI} (user_id, dorm_id, type_id, message, is_read)
            VALUES (?, ?, 1, ?, 0)
        ");
        $stN->bind_param("iis", $m["user_id"], $dorm_id, $msg);
        $stN->execute();
        $stN->close();

        jexit_api([
            "success" => true,
            "ok" => true,
            "message" => "ปฏิเสธการสมัครเรียบร้อย"
        ]);
    } catch (Throwable $e) {
        jexit_api([
            "success" => false,
            "ok" => false,
            "message" => $e->getMessage()
        ], 500);
    }
}

jexit_api([
    "success" => false,
    "ok" => false,
    "message" => "ไม่พบ action ที่ต้องการ"
], 400);
?>