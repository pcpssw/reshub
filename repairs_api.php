<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit;
}

ob_start();
ini_set('display_errors', '0');
error_reporting(E_ALL);

require_once __DIR__ . '/db.php';
mysqli_set_charset($conn, 'utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function repair_json(array $data, int $code = 200): void {
    if (ob_get_length()) {
        ob_clean();
    }
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function req_param(string $key, $default = null) {
    static $json = null;

    if (isset($_POST[$key])) return $_POST[$key];
    if (isset($_GET[$key])) return $_GET[$key];

    if ($json === null) {
        $raw = file_get_contents('php://input');
        $json = json_decode($raw, true);
        if (!is_array($json)) $json = [];
        foreach ($json as $k => $v) {
            if (!isset($_POST[$k])) $_POST[$k] = $v;
        }
    }

    return $json[$key] ?? $default;
}

function has_column(mysqli $conn, string $table, string $column): bool {
    static $cache = [];
    $key = $table . '.' . $column;
    if (array_key_exists($key, $cache)) return $cache[$key];

    $table = $conn->real_escape_string($table);
    $column = $conn->real_escape_string($column);
    $res = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$column'");
    $cache[$key] = $res && $res->num_rows > 0;
    return $cache[$key];
}

function db_to_thai_status(string $status): string {
    $s = strtolower(trim($status));
    if ($s === 'working') return 'กำลังดำเนินการ';
    if ($s === 'done') return 'เสร็จสิ้น';
    return 'รอดำเนินการ';
}

function thai_to_db_status(string $status): string {
    $s = strtolower(trim($status));
    if ($s === 'working' || str_contains($status, 'กำลัง')) return 'working';
    if ($s === 'done' || str_contains($status, 'เสร็จ')) return 'done';
    return 'pending';
}

function upload_repair_image(string $fieldName = 'image'): string {
    if (!isset($_FILES[$fieldName])) return '';
    $file = $_FILES[$fieldName];
    if (($file['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_NO_FILE) return '';
    if (($file['error'] ?? UPLOAD_ERR_OK) !== UPLOAD_ERR_OK) {
        throw new Exception('อัปโหลดรูปไม่สำเร็จ');
    }

    $tmpPath = $file['tmp_name'] ?? '';
    if (!$tmpPath || !is_uploaded_file($tmpPath)) {
        throw new Exception('ไฟล์รูปไม่ถูกต้อง');
    }

    $ext = strtolower(pathinfo((string)($file['name'] ?? ''), PATHINFO_EXTENSION));
    if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp'], true)) {
        throw new Exception('รองรับเฉพาะ jpg, jpeg, png, webp');
    }

    $uploadDir = __DIR__ . '/uploads/repairs/';
    if (!is_dir($uploadDir) && !mkdir($uploadDir, 0777, true) && !is_dir($uploadDir)) {
        throw new Exception('สร้างโฟลเดอร์อัปโหลดไม่สำเร็จ');
    }

    $newName = 'repair_' . date('Ymd_His') . '_' . bin2hex(random_bytes(5)) . '.' . $ext;
    if (!move_uploaded_file($tmpPath, $uploadDir . $newName)) {
        throw new Exception('บันทึกไฟล์รูปไม่สำเร็จ');
    }

    return 'uploads/repairs/' . $newName;
}

function delete_image_file(?string $relativePath): void {
    if (!$relativePath) return;
    $fullPath = __DIR__ . '/' . ltrim($relativePath, '/');
    if (is_file($fullPath)) {
        @unlink($fullPath);
    }
}

function insert_notification(mysqli $conn, int $dormId, int $userId, string $message, int $typeId = 3, int $refId = 0): void {
    $hasCreatedAt = has_column($conn, 'rh_notifications', 'created_at');
    $hasRefId = has_column($conn, 'rh_notifications', 'ref_id');

    if ($hasCreatedAt && $hasRefId) {
        $st = $conn->prepare('INSERT INTO rh_notifications (user_id, dorm_id, type_id, ref_id, message, is_read, created_at) VALUES (?, ?, ?, ?, ?, 0, NOW())');
        $st->bind_param('iiiis', $userId, $dormId, $typeId, $refId, $message);
    } elseif ($hasRefId) {
        $st = $conn->prepare('INSERT INTO rh_notifications (user_id, dorm_id, type_id, ref_id, message, is_read) VALUES (?, ?, ?, ?, ?, 0)');
        $st->bind_param('iiiis', $userId, $dormId, $typeId, $refId, $message);
    } else {
        $st = $conn->prepare('INSERT INTO rh_notifications (user_id, dorm_id, type_id, message, is_read) VALUES (?, ?, ?, ?, 0)');
        $st->bind_param('iiis', $userId, $dormId, $typeId, $message);
    }
    $st->execute();
    $st->close();
}

function normalize_repair_row(array $row): array {
    $finalRepairType = trim((string)($row['type_name'] ?? $row['repair_type'] ?? ''));
    if ($finalRepairType === '') {
        $finalRepairType = 'อื่น ๆ';
    }

    $img = trim((string)($row['image_path'] ?? ''));

    $row['repair_id'] = (int)($row['repair_id'] ?? 0);
    $row['type_id'] = (int)($row['type_id'] ?? 0);
    $row['repair_type'] = $finalRepairType;
    $row['title'] = 'แจ้งซ่อม' . $finalRepairType;
    $row['status'] = (string)($row['status'] ?? 'pending');
    $row['status_th'] = db_to_thai_status($row['status']);
    $row['image_path'] = $img;
    $row['image_first'] = $img;
    $row['images'] = $img !== '' ? json_encode([$img], JSON_UNESCAPED_UNICODE) : '[]';

    return $row;
}

$action = trim((string)req_param('action', ''));
if ($action === '') {
    repair_json(['success' => false, 'ok' => false, 'message' => 'ไม่พบ action'], 400);
}

if ($action === 'create') {
    try {
        $userId = (int)req_param('user_id', req_param('userId', 0));
        $dormId = (int)req_param('dorm_id', req_param('dormId', 0));
        $typeId = (int)req_param('type_id', req_param('typeId', 0));
        $detail = trim((string)req_param('detail', ''));

        if ($userId <= 0 || $dormId <= 0 || $typeId <= 0 || $detail === '') {
            repair_json(['success' => false, 'ok' => false, 'message' => 'ข้อมูลไม่ครบถ้วน'], 400);
        }

        $stmt = $conn->prepare('SELECT room_id, room_number FROM rh_rooms WHERE tenant_id = ? AND dorm_id = ? LIMIT 1');
        $stmt->bind_param('ii', $userId, $dormId);
        $stmt->execute();
        $room = $stmt->get_result()->fetch_assoc();
        $stmt->close();

        if (!$room) {
            repair_json(['success' => false, 'ok' => false, 'message' => 'ยังไม่พบห้องพักของคุณในหอนี้'], 404);
        }

        $roomId = (int)$room['room_id'];
        $imagePath = upload_repair_image('image');

        $stmt = $conn->prepare("INSERT INTO rh_repairs (dorm_id, room_id, user_id, type_id, detail, image_path, status, created_at) VALUES (?, ?, ?, ?, ?, ?, 'pending', NOW())");
        $stmt->bind_param('iiiiss', $dormId, $roomId, $userId, $typeId, $detail, $imagePath);
        $stmt->execute();
        $repairId = (int)$stmt->insert_id;
        $stmt->close();

        $stmt = $conn->prepare('SELECT type_name FROM rh_repair_types WHERE type_id = ?');
        $stmt->bind_param('i', $typeId);
        $stmt->execute();
        $tRow = $stmt->get_result()->fetch_assoc();
        $stmt->close();
        $typeName = $tRow['type_name'] ?? 'ทั่วไป';

        $message = 'มีรายการแจ้งซ่อมใหม่ ห้อง ' . ($room['room_number'] ?? '-') . ' ประเภท : ' . $typeName;
        $stmt = $conn->prepare("SELECT user_id FROM rh_dorm_memberships WHERE dorm_id = ? AND approve_status = 'approved' AND role_code IN ('a', 'o')");
        $stmt->bind_param('i', $dormId);
        $stmt->execute();
        $admins = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $stmt->close();

        foreach ($admins as $a) {
            insert_notification($conn, $dormId, (int)$a['user_id'], $message, 3, $repairId);
        }

        repair_json([
            'success' => true,
            'ok' => true,
            'message' => 'บันทึกการแจ้งซ่อมสำเร็จ',
            'repair_id' => $repairId,
            'image_path' => $imagePath,
        ]);
    } catch (Throwable $e) {
        repair_json(['success' => false, 'ok' => false, 'message' => $e->getMessage()], 500);
    }
}

if ($action === 'listMyRepairs') {
    $userId = (int)req_param('user_id', req_param('userId', 0));
    $dormId = (int)req_param('dorm_id', req_param('dormId', 0));

    if ($userId <= 0) {
        repair_json(['success' => false, 'ok' => false, 'message' => 'user_id ไม่ถูกต้อง'], 400);
    }

    $sql = "SELECT r.*, rt.type_name, rm.room_number, b.building_name, u.full_name, u.phone
            FROM rh_repairs r
            LEFT JOIN rh_repair_types rt ON rt.type_id = r.type_id
            LEFT JOIN rh_rooms rm ON rm.room_id = r.room_id
            LEFT JOIN rh_buildings b ON b.building_id = rm.building_id
            LEFT JOIN rh_users u ON u.user_id = r.user_id
            WHERE r.user_id = ?";

    if ($dormId > 0) {
        $sql .= ' AND r.dorm_id = ?';
    }

    $sql .= ' ORDER BY r.repair_id DESC';

    $st = $conn->prepare($sql);
    if ($dormId > 0) {
        $st->bind_param('ii', $userId, $dormId);
    } else {
        $st->bind_param('i', $userId);
    }
    $st->execute();
    $res = $st->get_result();
    $items = [];
    while ($row = $res->fetch_assoc()) {
        $items[] = normalize_repair_row($row);
    }
    $st->close();

    repair_json(['success' => true, 'ok' => true, 'data' => $items]);
}

if ($action === 'list') {
    $dormId = (int)req_param('dorm_id', 0);
    if ($dormId <= 0) {
        repair_json(['success' => false, 'ok' => false, 'message' => 'missing dorm_id'], 400);
    }

    $status = trim((string)req_param('status', ''));
    $whereStatus = '';
    $params = [$dormId];
    $types = 'i';

    if ($status !== '' && $status !== 'all' && $status !== 'ทั้งหมด') {
        $whereStatus = ' AND r.status = ? ';
        $params[] = thai_to_db_status($status);
        $types .= 's';
    }

    $sql = "SELECT r.*, rt.type_name, rm.room_number, b.building_name, u.full_name, u.phone
            FROM rh_repairs r
            LEFT JOIN rh_repair_types rt ON rt.type_id = r.type_id
            LEFT JOIN rh_rooms rm ON rm.room_id = r.room_id
            LEFT JOIN rh_buildings b ON b.building_id = rm.building_id
            LEFT JOIN rh_users u ON u.user_id = r.user_id
            WHERE r.dorm_id = ? {$whereStatus}
            ORDER BY r.repair_id DESC";

    $st = $conn->prepare($sql);
    $st->bind_param($types, ...$params);
    $st->execute();
    $res = $st->get_result();
    $items = [];
    while ($row = $res->fetch_assoc()) {
        $items[] = normalize_repair_row($row);
    }
    $st->close();

    repair_json(['success' => true, 'ok' => true, 'data' => $items]);
}

if ($action === 'getRepairById') {
    $repairId = (int)req_param('repair_id', req_param('id', 0));
    $dormId = (int)req_param('dorm_id', 0);

    if ($repairId <= 0) {
        repair_json(['success' => false, 'ok' => false, 'message' => 'repair_id ไม่ถูกต้อง'], 400);
    }

    $sql = "SELECT r.*, rt.type_name, rm.room_number, b.building_name, u.full_name, u.phone
            FROM rh_repairs r
            LEFT JOIN rh_repair_types rt ON rt.type_id = r.type_id
            LEFT JOIN rh_rooms rm ON rm.room_id = r.room_id
            LEFT JOIN rh_buildings b ON b.building_id = rm.building_id
            LEFT JOIN rh_users u ON u.user_id = r.user_id
            WHERE r.repair_id = ?";

    $types = 'i';
    $params = [$repairId];
    if ($dormId > 0) {
        $sql .= ' AND r.dorm_id = ?';
        $types .= 'i';
        $params[] = $dormId;
    }
    $sql .= ' LIMIT 1';

    $st = $conn->prepare($sql);
    $st->bind_param($types, ...$params);
    $st->execute();
    $row = $st->get_result()->fetch_assoc();
    $st->close();

    if (!$row) {
        repair_json(['success' => false, 'ok' => false, 'message' => 'ไม่พบข้อมูล'], 404);
    }

    repair_json(['success' => true, 'ok' => true, 'data' => normalize_repair_row($row)]);
}

if ($action === 'update') {
    try {
        $repairId = (int)req_param('repair_id', req_param('id', 0));
        $userId = (int)req_param('user_id', req_param('userId', 0));
        $typeId = (int)req_param('type_id', req_param('typeId', 0));
        $detail = trim((string)req_param('detail', ''));
        $isImageDeleted = (string)req_param('is_image_deleted', '0') === '1';

        $stmt = $conn->prepare('SELECT status, image_path FROM rh_repairs WHERE repair_id = ? AND user_id = ? LIMIT 1');
        $stmt->bind_param('ii', $repairId, $userId);
        $stmt->execute();
        $old = $stmt->get_result()->fetch_assoc();
        $stmt->close();

        if (!$old) {
            repair_json(['success' => false, 'ok' => false, 'message' => 'ไม่พบรายการ'], 404);
        }
        if (($old['status'] ?? '') !== 'pending') {
            repair_json(['success' => false, 'ok' => false, 'message' => 'แก้ไขได้เฉพาะรายการรอดำเนินการ'], 400);
        }

        $finalImage = (string)($old['image_path'] ?? '');
        if ($isImageDeleted) {
            delete_image_file($finalImage);
            $finalImage = '';
        }

        $newUploaded = upload_repair_image('image');
        if ($newUploaded !== '') {
            if ($finalImage !== '') {
                delete_image_file($finalImage);
            }
            $finalImage = $newUploaded;
        }

        $stmt = $conn->prepare('UPDATE rh_repairs SET type_id = ?, detail = ?, image_path = ? WHERE repair_id = ? AND user_id = ?');
        $stmt->bind_param('issii', $typeId, $detail, $finalImage, $repairId, $userId);
        $stmt->execute();
        $stmt->close();

        repair_json(['success' => true, 'ok' => true, 'message' => 'แก้ไขข้อมูลสำเร็จ', 'image_path' => $finalImage]);
    } catch (Throwable $e) {
        repair_json(['success' => false, 'ok' => false, 'message' => $e->getMessage()], 500);
    }
}

if ($action === 'deleteMyRepair') {
    $repairId = (int)req_param('repair_id', req_param('id', 0));
    $userId = (int)req_param('user_id', req_param('userId', 0));

    $stmt = $conn->prepare("SELECT image_path FROM rh_repairs WHERE repair_id = ? AND user_id = ? AND status = 'pending' LIMIT 1");
    $stmt->bind_param('ii', $repairId, $userId);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    $stmt = $conn->prepare("DELETE FROM rh_repairs WHERE repair_id = ? AND user_id = ? AND status = 'pending'");
    $stmt->bind_param('ii', $repairId, $userId);
    $stmt->execute();
    $affected = $stmt->affected_rows;
    $stmt->close();

    if ($affected > 0) {
        if (!empty($row['image_path'])) {
            delete_image_file((string)$row['image_path']);
        }
        repair_json(['success' => true, 'ok' => true, 'message' => 'ลบรายการสำเร็จ']);
    }

    repair_json(['success' => false, 'ok' => false, 'message' => 'ลบไม่ได้ หรือไม่พบรายการ'], 400);
}

if ($action === 'update_status') {
    $repairId = (int)req_param('repair_id', 0);
    $statusDb = thai_to_db_status((string)req_param('status', 'pending'));

    $st = $conn->prepare('UPDATE rh_repairs SET status = ? WHERE repair_id = ?');
    $st->bind_param('si', $statusDb, $repairId);
    $ok = $st->execute();
    $st->close();

    if (!$ok) {
        repair_json(['success' => false, 'ok' => false, 'message' => 'Update failed'], 500);
    }

    $infoSql = "SELECT r.dorm_id, r.user_id, rt.type_name, rm.room_number
                FROM rh_repairs r
                LEFT JOIN rh_repair_types rt ON rt.type_id = r.type_id
                LEFT JOIN rh_rooms rm ON rm.room_id = r.room_id
                WHERE r.repair_id = ? LIMIT 1";
    $infoSt = $conn->prepare($infoSql);
    $infoSt->bind_param('i', $repairId);
    $infoSt->execute();
    $info = $infoSt->get_result()->fetch_assoc();
    $infoSt->close();

    if ($info) {
        $typeName = $info['type_name'] ?? 'ทั่วไป';
        $msg = 'งานซ่อมแจ้งซ่อม' . $typeName . ' (ห้อง ' . ($info['room_number'] ?? '-') . ') ' . db_to_thai_status($statusDb);
        insert_notification($conn, (int)$info['dorm_id'], (int)$info['user_id'], $msg, 3, $repairId);
    }

    repair_json(['success' => true, 'ok' => true, 'status_th' => db_to_thai_status($statusDb)]);
}

repair_json(['success' => false, 'ok' => false, 'message' => 'action ไม่ถูกต้อง'], 400);
