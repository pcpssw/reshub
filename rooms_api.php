<?php
header("Content-Type: application/json; charset=utf-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit;
}

ini_set('display_errors', '0');
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
            'ok' => false,
            'success' => false,
            'message' => 'Fatal: ' . $e['message'],
        ], JSON_UNESCAPED_UNICODE);
    }
});

require_once __DIR__ . '/db.php';
mysqli_set_charset($conn, 'utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function out_ok(array $extra = [], int $code = 200): void {
    http_response_code($code);
    echo json_encode(array_merge([
        'ok' => true,
        'success' => true,
    ], $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

function out_fail(string $msg, int $code = 400, array $extra = []): void {
    http_response_code($code);
    echo json_encode(array_merge([
        'ok' => false,
        'success' => false,
        'message' => $msg,
    ], $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

function read_json_body(): array {
    static $cached = null;
    if ($cached !== null) return $cached;
    $raw = file_get_contents('php://input');
    $data = json_decode($raw ?: '', true);
    $cached = is_array($data) ? $data : [];
    return $cached;
}

function req(string $key, $default = null) {
    if (array_key_exists($key, $_POST)) return $_POST[$key];
    if (array_key_exists($key, $_GET)) return $_GET[$key];
    $json = read_json_body();
    return array_key_exists($key, $json) ? $json[$key] : $default;
}

function has_table(mysqli $conn, string $table): bool {
    $table = $conn->real_escape_string($table);
    $res = $conn->query("SHOW TABLES LIKE '$table'");
    return $res && $res->num_rows > 0;
}

function has_column(mysqli $conn, string $table, string $column): bool {
    $table = $conn->real_escape_string($table);
    $column = $conn->real_escape_string($column);
    $res = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$column'");
    return $res && $res->num_rows > 0;
}

function normalize_room_type_name($name): string {
    $s = mb_strtolower(trim((string)$name), 'UTF-8');
    if ($s === '') return 'fan';
    if (strpos($s, 'air') !== false || strpos($s, 'แอร์') !== false || strpos($s, 'ac') !== false) return 'air';
    return 'fan';
}

function resolve_room_type_id(mysqli $conn, int $dorm_id, string $kind): array {
    $stmt = $conn->prepare("SELECT type_id, type_name, default_rent FROM rh_room_types WHERE dorm_id=? ORDER BY type_id ASC");
    $stmt->bind_param('i', $dorm_id);
    $stmt->execute();
    $res = $stmt->get_result();

    $rows = [];
    while ($row = $res->fetch_assoc()) {
        $rows[] = $row;
    }
    $stmt->close();

    foreach ($rows as $row) {
        if (normalize_room_type_name($row['type_name'] ?? '') === $kind) {
            return [(int)$row['type_id'], (float)($row['default_rent'] ?? 0)];
        }
    }

    if (!empty($rows)) {
        return [(int)$rows[0]['type_id'], (float)($rows[0]['default_rent'] ?? 0)];
    }

    return [0, 0.0];
}

function room_select_sql(mysqli $conn): array {
    $hasBuildings = has_table($conn, 'rh_buildings') && has_column($conn, 'rh_rooms', 'building_id');
    $hasRoomTypes = has_table($conn, 'rh_room_types') && has_column($conn, 'rh_rooms', 'type_id');
    $hasTenantId = has_column($conn, 'rh_rooms', 'tenant_id');
    $hasBaseRent = has_column($conn, 'rh_rooms', 'base_rent');
    $hasStatus = has_column($conn, 'rh_rooms', 'status');
    $hasFloor = has_column($conn, 'rh_rooms', 'floor');

    $buildingJoin = $hasBuildings ? ' LEFT JOIN rh_buildings b ON b.building_id = r.building_id ' : '';
    $typeJoin = $hasRoomTypes ? ' LEFT JOIN rh_room_types rt ON rt.type_id = r.type_id ' : '';
    $userJoin = $hasTenantId ? ' LEFT JOIN rh_users u ON u.user_id = r.tenant_id ' : '';

    $buildingExpr = $hasBuildings
        ? (has_column($conn, 'rh_buildings', 'building_name') ? 'COALESCE(b.building_name, \'\')' : 'COALESCE(b.name, \'\')')
        : "''";

    $typeExpr = $hasRoomTypes
        ? (has_column($conn, 'rh_room_types', 'type_name') ? 'COALESCE(rt.type_name, \'\')' : "''")
        : (has_column($conn, 'rh_rooms', 'room_type') ? 'COALESCE(r.room_type, \'\')' : "''");

    $rentExpr = $hasBaseRent
        ? 'COALESCE(r.base_rent, 0)'
        : (has_column($conn, 'rh_rooms', 'rent_price') ? 'COALESCE(r.rent_price, 0)' : '0');

    $statusExpr = $hasStatus ? 'COALESCE(r.status, \'vacant\')' : "'vacant'";
    $floorExpr = $hasFloor ? 'COALESCE(r.floor, 0)' : '0';
    $tenantExpr = $hasTenantId ? 'u.user_id AS tenant_id, u.full_name, u.phone' : 'NULL AS tenant_id, NULL AS full_name, NULL AS phone';

    $sql = "
        SELECT
            r.room_id,
            r.dorm_id,
            " . (has_column($conn, 'rh_rooms', 'building_id') ? 'r.building_id' : 'NULL AS building_id') . ",
            " . (has_column($conn, 'rh_rooms', 'type_id') ? 'r.type_id' : 'NULL AS type_id') . ",
            COALESCE(r.room_number, '') AS room_number,
            {$floorExpr} AS floor,
            {$rentExpr} AS rent_price,
            {$statusExpr} AS status,
            {$buildingExpr} AS building,
            {$typeExpr} AS room_type,
            " . ($hasRoomTypes ? 'COALESCE(rt.default_rent, 0)' : '0') . " AS default_rent,
            {$tenantExpr}
        FROM rh_rooms r
        {$buildingJoin}
        {$typeJoin}
        {$userJoin}
    ";

    return [$sql, $hasBuildings, $hasRoomTypes];
}

$action = (string)req('action', 'list');

$dorm_id = (int)req('dorm_id', 0);
if ($dorm_id <= 0) {
    out_fail('missing dorm_id', 400);
}

const T_DORMS = 'rh_dorms';
const T_SETTINGS = 'rh_dorm_settings';
const T_BUILDINGS = 'rh_buildings';
const T_ROOM_TYPES = 'rh_room_types';
const T_ROOMS = 'rh_rooms';

function ensure_dorm_settings(mysqli $conn, int $dorm_id): void {
    $st = $conn->prepare("INSERT IGNORE INTO " . T_SETTINGS . " (dorm_id, water_rate, electric_rate) VALUES (?, 0.00, 0.00)");
    $st->bind_param('i', $dorm_id);
    $st->execute();
    $st->close();
}

function find_type_by_keyword(mysqli $conn, int $dorm_id, string $keyword): ?array {
    $kw = '%' . $keyword . '%';
    $st = $conn->prepare(
        "SELECT type_id, type_name, default_rent
         FROM " . T_ROOM_TYPES . "
         WHERE dorm_id = ? AND type_name LIKE ?
         ORDER BY type_id ASC
         LIMIT 1"
    );
    $st->bind_param('is', $dorm_id, $kw);
    $st->execute();
    $row = $st->get_result()->fetch_assoc();
    $st->close();
    return $row ?: null;
}

function ensure_default_room_types(mysqli $conn, int $dorm_id): array {
    $fan = find_type_by_keyword($conn, $dorm_id, 'Fan');
    $air = find_type_by_keyword($conn, $dorm_id, 'Air');

    if (!$fan) {
        $name = 'Standard Fan';
        $rent = 0.00;
        $st = $conn->prepare("INSERT INTO " . T_ROOM_TYPES . " (dorm_id, type_name, default_rent) VALUES (?, ?, ?)");
        $st->bind_param('isd', $dorm_id, $name, $rent);
        $st->execute();
        $st->close();
        $fan = find_type_by_keyword($conn, $dorm_id, 'Fan');
    }

    if (!$air) {
        $name = 'Standard Air';
        $rent = 0.00;
        $st = $conn->prepare("INSERT INTO " . T_ROOM_TYPES . " (dorm_id, type_name, default_rent) VALUES (?, ?, ?)");
        $st->bind_param('isd', $dorm_id, $name, $rent);
        $st->execute();
        $st->close();
        $air = find_type_by_keyword($conn, $dorm_id, 'Air');
    }

    return ['fan' => $fan, 'air' => $air];
}

function get_dorm_settings_bundle(mysqli $conn, int $dorm_id): array {
    ensure_dorm_settings($conn, $dorm_id);
    $types = ensure_default_room_types($conn, $dorm_id);

    $st = $conn->prepare("SELECT water_rate, electric_rate FROM " . T_SETTINGS . " WHERE dorm_id = ? LIMIT 1");
    $st->bind_param('i', $dorm_id);
    $st->execute();
    $row = $st->get_result()->fetch_assoc() ?: [];
    $st->close();

    return [
        'water_rate' => (float)($row['water_rate'] ?? 0),
        'electric_rate' => (float)($row['electric_rate'] ?? 0),
        'default_rent_fan' => (float)($types['fan']['default_rent'] ?? 0),
        'default_rent_air' => (float)($types['air']['default_rent'] ?? 0),
        'fan_type_id' => (int)($types['fan']['type_id'] ?? 0),
        'air_type_id' => (int)($types['air']['type_id'] ?? 0),
    ];
}

function get_dorm_summary(mysqli $conn, int $dorm_id): array {
    $roomSql = "
        SELECT 
            COUNT(*) AS total_rooms,
            SUM(CASE WHEN rt.type_name LIKE '%Fan%' THEN 1 ELSE 0 END) AS fan_count,
            SUM(CASE WHEN rt.type_name LIKE '%Air%' THEN 1 ELSE 0 END) AS air_count,
            SUM(CASE WHEN r.status = 'vacant' THEN 1 ELSE 0 END) AS vacant_count
        FROM " . T_ROOMS . " r
        LEFT JOIN " . T_ROOM_TYPES . " rt ON rt.type_id = r.type_id
        WHERE r.dorm_id = ?
    ";
    $st = $conn->prepare($roomSql);
    $st->bind_param('i', $dorm_id);
    $st->execute();
    $room = $st->get_result()->fetch_assoc() ?: [];
    $st->close();

    $st = $conn->prepare("SELECT COUNT(*) AS building_count FROM " . T_BUILDINGS . " WHERE dorm_id = ?");
    $st->bind_param('i', $dorm_id);
    $st->execute();
    $building = $st->get_result()->fetch_assoc() ?: [];
    $st->close();

    return [
        'total_rooms' => (int)($room['total_rooms'] ?? 0),
        'fan_count' => (int)($room['fan_count'] ?? 0),
        'air_count' => (int)($room['air_count'] ?? 0),
        'vacant_count' => (int)($room['vacant_count'] ?? 0),
        'building_count' => (int)($building['building_count'] ?? 0),
    ];
}

function get_or_create_building(mysqli $conn, int $dorm_id, string $building_name): int {
    $st = $conn->prepare("SELECT building_id FROM " . T_BUILDINGS . " WHERE dorm_id = ? AND building_name = ? LIMIT 1");
    $st->bind_param('is', $dorm_id, $building_name);
    $st->execute();
    $row = $st->get_result()->fetch_assoc();
    $st->close();
    if ($row) return (int)$row['building_id'];

    $st = $conn->prepare("INSERT INTO " . T_BUILDINGS . " (dorm_id, building_name) VALUES (?, ?)");
    $st->bind_param('is', $dorm_id, $building_name);
    $st->execute();
    $id = (int)$conn->insert_id;
    $st->close();
    return $id;
}

function normalize_building_names($rawNames): array {
    if (is_string($rawNames)) {
        $decoded = json_decode($rawNames, true);
        if (is_array($decoded)) $rawNames = $decoded;
    }
    if (!is_array($rawNames)) return [];

    $out = [];
    foreach ($rawNames as $name) {
        $name = trim((string)$name);
        if ($name !== '' && !in_array($name, $out, true)) {
            $out[] = $name;
        }
    }
    return $out;
}

if ($action === 'defaults') {
    $stmt = $conn->prepare("SELECT type_id, type_name, default_rent FROM rh_room_types WHERE dorm_id=? ORDER BY type_id ASC");
    $stmt->bind_param('i', $dorm_id);
    $stmt->execute();
    $result = $stmt->get_result();

    $fan = 0;
    $air = 0;
    $types = [];
    while ($row = $result->fetch_assoc()) {
        $kind = normalize_room_type_name($row['type_name'] ?? '');
        $row['kind'] = $kind;
        $row['type_id'] = (int)$row['type_id'];
        $row['default_rent'] = (float)($row['default_rent'] ?? 0);
        $types[] = $row;
        if ($kind === 'fan' && $fan <= 0) $fan = (int)round($row['default_rent']);
        if ($kind === 'air' && $air <= 0) $air = (int)round($row['default_rent']);
    }
    $stmt->close();

    out_ok([
        'settings' => [
            'default_rent_fan' => $fan,
            'default_rent_air' => $air,
        ],
        'types' => $types,
    ]);
}

if ($action === 'detail') {
    $room_id = (int)req('room_id', 0);
    if ($room_id <= 0) out_fail('missing room_id');

    [$baseSql] = room_select_sql($conn);
    $sql = $baseSql . " WHERE r.dorm_id=? AND r.room_id=? LIMIT 1";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param('ii', $dorm_id, $room_id);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$row) out_fail('not found', 404);

    $row['room_id'] = (int)$row['room_id'];
    $row['dorm_id'] = (int)$row['dorm_id'];
    $row['building_id'] = $row['building_id'] !== null ? (int)$row['building_id'] : null;
    $row['type_id'] = $row['type_id'] !== null ? (int)$row['type_id'] : null;
    $row['floor'] = (int)$row['floor'];
    $row['rent_price'] = (float)$row['rent_price'];
    $row['default_rent'] = (float)$row['default_rent'];
    $row['tenant_id'] = $row['tenant_id'] !== null ? (int)$row['tenant_id'] : null;
    $row['tenant_status'] = !empty($row['tenant_id']) ? 'active' : '';
    $row['start_date'] = null;
    $row['label'] = ($row['building'] ?? '') . ($row['room_number'] ?? '');

    out_ok(['data' => $row]);
}

if ($action === 'list') {
    $status = trim((string)req('status', ''));
    $type = trim((string)req('room_type', ''));
    $building = trim((string)req('building', ''));
    $floor = (int)req('floor', 0);

    [$baseSql, $hasBuildings, $hasRoomTypes] = room_select_sql($conn);
    $sql = $baseSql . ' WHERE r.dorm_id=?';
    $params = [$dorm_id];
    $types = 'i';

    if ($status !== '') {
        $sql .= ' AND r.status=?';
        $params[] = $status;
        $types .= 's';
    }

    if ($type !== '') {
        if ($hasRoomTypes) {
            if (in_array($type, ['fan', 'air'], true)) {
                $sql .= ' AND LOWER(rt.type_name) LIKE ?';
                $params[] = '%' . $type . '%';
            } else {
                $sql .= ' AND rt.type_name = ?';
                $params[] = $type;
            }
            $types .= 's';
        } elseif (has_column($conn, 'rh_rooms', 'room_type')) {
            $sql .= ' AND r.room_type = ?';
            $params[] = $type;
            $types .= 's';
        }
    }

    if ($building !== '') {
        if ($hasBuildings) {
            $sql .= ' AND b.building_name = ?';
        } elseif (has_column($conn, 'rh_rooms', 'building')) {
            $sql .= ' AND r.building = ?';
        }
        $params[] = $building;
        $types .= 's';
    }

    if ($floor > 0) {
        $sql .= ' AND r.floor = ?';
        $params[] = $floor;
        $types .= 'i';
    }

    $sql .= " ORDER BY COALESCE(building, ''), floor ASC,
        CASE WHEN room_number REGEXP '^[0-9]+$' THEN CAST(room_number AS UNSIGNED) ELSE 999999999 END,
        room_number ASC";

    $stmt = $conn->prepare($sql);
    $stmt->bind_param($types, ...$params);
    $stmt->execute();
    $result = $stmt->get_result();

    $rows = [];
    while ($row = $result->fetch_assoc()) {
        $item = [
            'room_id' => (int)$row['room_id'],
            'dorm_id' => (int)$row['dorm_id'],
            'building_id' => $row['building_id'] !== null ? (int)$row['building_id'] : null,
            'type_id' => $row['type_id'] !== null ? (int)$row['type_id'] : null,
            'room_number' => (string)($row['room_number'] ?? ''),
            'building' => (string)($row['building'] ?? ''),
            'floor' => (int)$row['floor'],
            'room_type' => (string)($row['room_type'] ?? ''),
            'rent_price' => (float)$row['rent_price'],
            'default_rent' => (float)$row['default_rent'],
            'status' => (string)($row['status'] ?? 'vacant'),
            'tenant_id' => $row['tenant_id'] !== null ? (int)$row['tenant_id'] : null,
            'tenant_status' => !empty($row['tenant_id']) ? 'active' : '',
            'start_date' => null,
            'full_name' => $row['full_name'] ?? null,
            'phone' => $row['phone'] ?? null,
        ];
        $item['label'] = $item['building'] . $item['room_number'];
        $rows[] = $item;
    }
    $stmt->close();

    out_ok(['data' => $rows, 'rooms' => $rows]);
}

if ($action === 'add') {
    $room_number = trim((string)req('room_number', ''));
    $building_id = (int)req('building_id', 0);
    $floor = (int)req('floor', 0);
    $room_type = trim((string)req('room_type', 'fan'));
    $rent_price = (float)req('rent_price', req('price', 0));
    $status = trim((string)req('status', 'vacant'));
    $tenant_id = req('tenant_id') ? (int)req('tenant_id') : null; // เพิ่มการรับค่าผู้เช่า

    if ($room_number === '' || $floor <= 0) out_fail('ข้อมูลไม่ครบ (room_number/floor)');
    if (!in_array($room_type, ['fan', 'air'], true)) out_fail('room_type ไม่ถูกต้อง');
    if (!in_array($status, ['vacant', 'occupied', 'maintenance'], true)) out_fail('status ไม่ถูกต้อง');

    [$type_id, $default_rent] = resolve_room_type_id($conn, $dorm_id, $room_type);
    if ($type_id <= 0) out_fail('ไม่พบประเภทห้องของหอนี้');
    if ($rent_price <= 0) $rent_price = $default_rent;

    // แก้คำสั่ง INSERT ให้บันทึก tenant_id
    $stmt = $conn->prepare(
        'INSERT INTO rh_rooms (dorm_id, building_id, type_id, room_number, floor, base_rent, status, tenant_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    );
    $stmt->bind_param('iiisidsi', $dorm_id, $building_id, $type_id, $room_number, $floor, $rent_price, $status, $tenant_id);
    $stmt->execute();
    $newId = (int)$conn->insert_id;
    $stmt->close();

    out_ok(['message' => 'เพิ่มห้องสำเร็จ', 'room_id' => $newId]);
}

if ($action === 'update') {
    $room_id = (int)req('room_id', 0);
    $rent_price = (float)req('rent_price', req('price', 0));
    $room_type = trim((string)req('room_type', ''));
    $status = trim((string)req('status', ''));
    $tenant_id = req('tenant_id') !== null ? (int)req('tenant_id') : null; // เพิ่มการรับค่าผู้เช่า

    if ($room_id <= 0) out_fail('room_id ไม่ถูกต้อง');
    if (!in_array($room_type, ['fan', 'air'], true)) out_fail('room_type ไม่ถูกต้อง');
    if (!in_array($status, ['vacant', 'occupied', 'maintenance'], true)) out_fail('status ไม่ถูกต้อง');

    [$type_id, $default_rent] = resolve_room_type_id($conn, $dorm_id, $room_type);
    if ($type_id <= 0) out_fail('ไม่พบประเภทห้องของหอนี้');
    if ($rent_price <= 0) $rent_price = $default_rent;

    // แก้คำสั่ง UPDATE ให้เปลี่ยนคนเช่าได้
    $stmt = $conn->prepare('UPDATE rh_rooms SET type_id=?, base_rent=?, status=?, tenant_id=? WHERE room_id=? AND dorm_id=?');
    $stmt->bind_param('idsiii', $type_id, $rent_price, $status, $tenant_id, $room_id, $dorm_id);
    $stmt->execute();
    $stmt->close();

    out_ok(['message' => 'อัปเดตสำเร็จ']);
}

if ($action === 'bulk_update') {
    $items = req('items', []);
    if (!is_array($items)) out_fail('items ต้องเป็น array');

    $conn->begin_transaction();
    try {
        $stmt = $conn->prepare('UPDATE rh_rooms SET type_id=?, base_rent=?, status=? WHERE room_id=? AND dorm_id=?');
        $updated = 0;

        foreach ($items as $it) {
            $room_id = (int)($it['room_id'] ?? 0);
            $room_type = trim((string)($it['room_type'] ?? ''));
            $rent_price = (float)($it['rent_price'] ?? ($it['price'] ?? 0));
            $status = trim((string)($it['status'] ?? 'vacant'));

            if ($room_id <= 0 || !in_array($room_type, ['fan', 'air'], true) || !in_array($status, ['vacant', 'occupied', 'maintenance'], true)) {
                continue;
            }

            [$type_id, $default_rent] = resolve_room_type_id($conn, $dorm_id, $room_type);
            if ($type_id <= 0) continue;
            if ($rent_price <= 0) $rent_price = $default_rent;

            $stmt->bind_param('idsii', $type_id, $rent_price, $status, $room_id, $dorm_id);
            $stmt->execute();
            $updated += max(0, $stmt->affected_rows);
        }

        $stmt->close();
        $conn->commit();
        out_ok(['message' => 'bulk_update ok', 'updated' => $updated]);
    } catch (Throwable $e) {
        $conn->rollback();
        out_fail('bulk_update fail: ' . $e->getMessage(), 500);
    }
}

if ($action === 'delete') {
    $room_id = (int)req('room_id', 0);
    if ($room_id <= 0) out_fail('room_id ไม่ถูกต้อง');

    $stmt = $conn->prepare('DELETE FROM rh_rooms WHERE room_id=? AND dorm_id=?');
    $stmt->bind_param('ii', $room_id, $dorm_id);
    $stmt->execute();
    $affected = $stmt->affected_rows;
    $stmt->close();

    if ($affected > 0) {
        out_ok(['message' => 'ลบสำเร็จ']);
    }
    out_fail('ไม่พบห้องนี้ในระบบ', 404);
}

if ($action === 'get') {
    $st = $conn->prepare("SELECT dorm_id, dorm_name, dorm_address, dorm_phone, dorm_code, status FROM " . T_DORMS . " WHERE dorm_id = ? LIMIT 1");
    $st->bind_param('i', $dorm_id);
    $st->execute();
    $dorm = $st->get_result()->fetch_assoc();
    $st->close();

    if (!$dorm) {
        out_fail('ไม่พบข้อมูลหอพัก', 404);
    }

    $dorm['dorm_status'] = $dorm['status'] ?? null;

    out_ok([
        'dorm' => $dorm,
        'settings' => get_dorm_settings_bundle($conn, $dorm_id),
        'summary' => get_dorm_summary($conn, $dorm_id),
    ]);
}

if ($action === 'update_rent') {
    $rent_fan = (float)req('rent_fan', 0);
    $rent_air = (float)req('rent_air', 0);
    $types = ensure_default_room_types($conn, $dorm_id);

    $conn->begin_transaction();
    try {
        if (!empty($types['fan']['type_id'])) {
            $tid = (int)$types['fan']['type_id'];
            $st = $conn->prepare("UPDATE " . T_ROOM_TYPES . " SET default_rent = ? WHERE type_id = ?");
            $st->bind_param('di', $rent_fan, $tid);
            $st->execute();
            $st->close();

            $st = $conn->prepare("UPDATE " . T_ROOMS . " SET base_rent = ? WHERE dorm_id = ? AND type_id = ? AND status = 'vacant'");
            $st->bind_param('dii', $rent_fan, $dorm_id, $tid);
            $st->execute();
            $st->close();
        }

        if (!empty($types['air']['type_id'])) {
            $tid = (int)$types['air']['type_id'];
            $st = $conn->prepare("UPDATE " . T_ROOM_TYPES . " SET default_rent = ? WHERE type_id = ?");
            $st->bind_param('di', $rent_air, $tid);
            $st->execute();
            $st->close();

            $st = $conn->prepare("UPDATE " . T_ROOMS . " SET base_rent = ? WHERE dorm_id = ? AND type_id = ? AND status = 'vacant'");
            $st->bind_param('dii', $rent_air, $dorm_id, $tid);
            $st->execute();
            $st->close();
        }

        $conn->commit();
        out_ok([
            'message' => 'บันทึกราคาเรียบร้อย',
            'settings' => get_dorm_settings_bundle($conn, $dorm_id),
            'summary' => get_dorm_summary($conn, $dorm_id),
        ]);
    } catch (Throwable $e) {
        $conn->rollback();
        out_fail('บันทึกราคาไม่สำเร็จ: ' . $e->getMessage(), 500);
    }
}

if ($action === 'update_rates') {
    $water = (float)req('water_rate', 0);
    $electric = (float)req('electric_rate', 0);
    ensure_dorm_settings($conn, $dorm_id);

    $st = $conn->prepare("UPDATE " . T_SETTINGS . " SET water_rate = ?, electric_rate = ? WHERE dorm_id = ?");
    $st->bind_param('ddi', $water, $electric, $dorm_id);
    $ok = $st->execute();
    $st->close();

    out_ok([
        'ok' => $ok,
        'message' => $ok ? 'อัปเดตค่าน้ำค่าไฟเรียบร้อย' : 'ไม่สามารถอัปเดตได้',
        'settings' => get_dorm_settings_bundle($conn, $dorm_id),
    ], $ok ? 200 : 500);
}

if ($action === 'generate') {
    $building_names = normalize_building_names(req('building_names', []));
    $floors = max(1, (int)req('floors', 1));
    $rooms_per_floor = max(1, (int)req('rooms_per_floor', 1));
    $default_type = strtolower(trim((string)req('default_type', 'fan')));
    $types = ensure_default_room_types($conn, $dorm_id);
    $selectedType = ($default_type === 'air') ? $types['air'] : $types['fan'];
    $type_id = (int)($selectedType['type_id'] ?? 0);
    $base_rent = (float)($selectedType['default_rent'] ?? 0);

    if (empty($building_names)) out_fail('กรุณาระบุชื่อตึกอย่างน้อย 1 ชื่อ', 400);
    if ($type_id <= 0) out_fail('ไม่พบประเภทห้องเริ่มต้น', 400);

    $created = 0;
    $conn->begin_transaction();
    try {
        $check = $conn->prepare("SELECT room_id FROM " . T_ROOMS . " WHERE dorm_id = ? AND building_id = ? AND room_number = ? LIMIT 1");
        $ins = $conn->prepare("INSERT INTO " . T_ROOMS . " (dorm_id, building_id, type_id, room_number, floor, base_rent, status, tenant_id) VALUES (?, ?, ?, ?, ?, ?, 'vacant', NULL)");

        foreach ($building_names as $building_name) {
            $building_id = get_or_create_building($conn, $dorm_id, $building_name);
            for ($floor = 1; $floor <= $floors; $floor++) {
                for ($room = 1; $room <= $rooms_per_floor; $room++) {
                    $room_number = $floor . str_pad((string)$room, 2, '0', STR_PAD_LEFT);
                    $check->bind_param('iis', $dorm_id, $building_id, $room_number);
                    $check->execute();
                    if ($check->get_result()->fetch_assoc()) {
                        continue;
                    }

                    $ins->bind_param('iiisid', $dorm_id, $building_id, $type_id, $room_number, $floor, $base_rent);
                    $ins->execute();
                    $created++;
                }
            }
        }

        $check->close();
        $ins->close();
        $conn->commit();
        out_ok([
            'message' => "สร้างห้องพักสำเร็จ {$created} ห้อง",
            'count' => $created,
            'summary' => get_dorm_summary($conn, $dorm_id),
            'settings' => get_dorm_settings_bundle($conn, $dorm_id),
        ]);
    } catch (Throwable $e) {
        $conn->rollback();
        out_fail('ไม่สามารถสร้างห้องได้: ' . $e->getMessage(), 500);
    }
}

if ($action === 'save') {
    $items = req('items', null);
    if (is_array($items)) {
        $action = 'bulk_update';
    } else {
        $hasDormFields = array_key_exists('dorm_name', $_POST) || array_key_exists('dorm_name', $_GET) || array_key_exists('dorm_name', read_json_body())
            || array_key_exists('dorm_address', $_POST) || array_key_exists('dorm_address', $_GET) || array_key_exists('dorm_address', read_json_body())
            || array_key_exists('dorm_phone', $_POST) || array_key_exists('dorm_phone', $_GET) || array_key_exists('dorm_phone', read_json_body())
            || array_key_exists('dorm_code', $_POST) || array_key_exists('dorm_code', $_GET) || array_key_exists('dorm_code', read_json_body());
        $hasRateFields = array_key_exists('water_rate', $_POST) || array_key_exists('water_rate', $_GET) || array_key_exists('water_rate', read_json_body())
            || array_key_exists('electric_rate', $_POST) || array_key_exists('electric_rate', $_GET) || array_key_exists('electric_rate', read_json_body());

        $conn->begin_transaction();
        try {
            if ($hasDormFields) {
                $dorm_name = trim((string)req('dorm_name', ''));
                $dorm_address = trim((string)req('dorm_address', ''));
                $dorm_phone = trim((string)req('dorm_phone', ''));
                $dorm_code = trim((string)req('dorm_code', ''));

                if ($dorm_name === '') {
                    $st = $conn->prepare("SELECT dorm_name FROM " . T_DORMS . " WHERE dorm_id = ? LIMIT 1");
                    $st->bind_param('i', $dorm_id);
                    $st->execute();
                    $row = $st->get_result()->fetch_assoc();
                    $st->close();
                    $dorm_name = (string)($row['dorm_name'] ?? '');
                }

                $st = $conn->prepare("UPDATE " . T_DORMS . " SET dorm_name = ?, dorm_address = ?, dorm_phone = ?, dorm_code = ? WHERE dorm_id = ?");
                $st->bind_param('ssssi', $dorm_name, $dorm_address, $dorm_phone, $dorm_code, $dorm_id);
                $st->execute();
                $st->close();
            }

            if ($hasRateFields) {
                ensure_dorm_settings($conn, $dorm_id);
                $water = (float)req('water_rate', 0);
                $electric = (float)req('electric_rate', 0);
                $st = $conn->prepare("UPDATE " . T_SETTINGS . " SET water_rate = ?, electric_rate = ? WHERE dorm_id = ?");
                $st->bind_param('ddi', $water, $electric, $dorm_id);
                $st->execute();
                $st->close();
            }

            $conn->commit();
            out_ok([
                'message' => 'บันทึกข้อมูลสำเร็จ',
                'settings' => get_dorm_settings_bundle($conn, $dorm_id),
                'summary' => get_dorm_summary($conn, $dorm_id),
            ]);
        } catch (Throwable $e) {
            $conn->rollback();
            out_fail('บันทึกไม่สำเร็จ: ' . $e->getMessage(), 500);
        }
    }
}

out_fail('Unknown action: ' . $action, 400);
?>