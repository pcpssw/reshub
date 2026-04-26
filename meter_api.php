<?php
header("Content-Type: application/json; charset=utf-8");
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

register_shutdown_function(function () {
    $e = error_get_last();
    if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
        http_response_code(500);
        echo json_encode([
            "ok" => false,
            "message" => "Fatal Error: {$e['message']}"
        ], JSON_UNESCAPED_UNICODE);
    }
});

function ok($extra = []) {
    echo json_encode(array_merge(["ok" => true], $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

function fail($msg, $code = 400) {
    http_response_code($code);
    echo json_encode(["ok" => false, "message" => $msg], JSON_UNESCAPED_UNICODE);
    exit;
}

require_once "db.php";
mysqli_set_charset($conn, "utf8mb4");
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

$raw = file_get_contents("php://input");
$inputJson = json_decode($raw, true) ?: [];

function param($k, $default = "") {
    global $inputJson;
    if (isset($_GET[$k])) return $_GET[$k];
    if (isset($_POST[$k])) return $_POST[$k];
    if (isset($inputJson[$k])) return $inputJson[$k];
    return $default;
}

$action  = (string)param("action", "get");
$dorm_id = (int)param("dorm_id", 0);
$month   = (int)param("month", (int)date("n"));
$year    = (int)param("year", (int)date("Y"));

if ($dorm_id <= 0) fail("ไม่พบ dorm_id");

// --- 1. ACTION: GET ---
if ($action === "get") {
    try {
        $sql = "
            SELECT
                r.room_id, r.room_number, r.tenant_id,
                COALESCE(u.full_name, '') AS full_name,
                COALESCE(b.building_name, '') AS building,
                COALESCE((
                    SELECT water_new FROM rh_meter 
                    WHERE room_id = r.room_id 
                    AND NOT (month = ? AND year = ? AND user_id = r.tenant_id)
                    ORDER BY year DESC, month DESC, reading_id DESC LIMIT 1
                ), 0) AS prev_w,
                COALESCE((
                    SELECT elec_new FROM rh_meter 
                    WHERE room_id = r.room_id 
                    AND NOT (month = ? AND year = ? AND user_id = r.tenant_id)
                    ORDER BY year DESC, month DESC, reading_id DESC LIMIT 1
                ), 0) AS prev_e,
                COALESCE(cm.water_new, 0) AS cur_w,
                COALESCE(cm.elec_new, 0) AS cur_e
            FROM rh_rooms r
            LEFT JOIN rh_users u ON u.user_id = r.tenant_id
            LEFT JOIN rh_buildings b ON b.building_id = r.building_id
            LEFT JOIN rh_meter cm
                ON cm.room_id = r.room_id
               AND cm.month = ?
               AND cm.year = ?
               AND cm.user_id = r.tenant_id
            WHERE r.dorm_id = ?
            ORDER BY b.building_name, r.room_number
        ";
        $st = $conn->prepare($sql);
        $st->bind_param("iiiiiii", $month, $year, $month, $year, $month, $year, $dorm_id);
        $st->execute();
        $rs = $st->get_result();
        $rooms = [];
        while ($row = $rs->fetch_assoc()) {
            $rooms[] = [
                "room_id" => (int)$row["room_id"],
                "room_number" => (string)$row["room_number"],
                "building" => (string)$row["building"],
                "tenant_id" => empty($row["tenant_id"]) ? null : (int)$row["tenant_id"],
                "full_name" => (string)$row["full_name"],
                "prev_water_meter" => (int)$row["prev_w"],
                "prev_electric_meter" => (int)$row["prev_e"],
                "current_water_meter" => (int)$row["cur_w"],
                "current_electric_meter" => (int)$row["cur_e"]
            ];
        }
        ok(["rooms" => $rooms]);
    } catch (Throwable $e) { fail($e->getMessage(), 500); }
}

// --- 2. ACTION: SAVE ---
elseif ($action === "save") {
    $items = param("items");
    if (!is_array($items) || empty($items)) fail("ไม่มีข้อมูลที่จะบันทึก");
    try {
        $conn->begin_transaction();
        foreach ($items as $it) {
            $room_id = (int)($it['room_id'] ?? 0);
            if ($room_id <= 0) continue;
            
            $stTenant = $conn->prepare("SELECT tenant_id FROM rh_rooms WHERE room_id=? LIMIT 1");
            $stTenant->bind_param("i", $room_id);
            $stTenant->execute();
            $tid = $stTenant->get_result()->fetch_assoc()['tenant_id'] ?? 0;
            if ($tid <= 0) continue;

            $stPrev = $conn->prepare("SELECT water_new, elec_new FROM rh_meter WHERE room_id=? AND NOT (month=? AND year=? AND user_id=?) ORDER BY year DESC, month DESC, reading_id DESC LIMIT 1");
            $stPrev->bind_param("iiii", $room_id, $month, $year, $tid);
            $stPrev->execute();
            $prev = $stPrev->get_result()->fetch_assoc();
            
            $prevW = (int)($prev ? $prev['water_new'] : 0);
            $prevE = (int)($prev ? $prev['elec_new'] : 0);
            $newW = (int)($it['water_meter'] ?? 0);
            $newE = (int)($it['electric_meter'] ?? 0);

            $stCur = $conn->prepare("SELECT reading_id FROM rh_meter WHERE room_id=? AND month=? AND year=? AND user_id=?");
            $stCur->bind_param("iiii", $room_id, $month, $year, $tid);
            $stCur->execute();
            $curData = $stCur->get_result()->fetch_assoc();

            if ($curData) {
                $stUpd = $conn->prepare("UPDATE rh_meter SET water_old=?, water_new=?, elec_old=?, elec_new=? WHERE reading_id=?");
                $stUpd->bind_param("iiiii", $prevW, $newW, $prevE, $newE, $curData['reading_id']);
                $stUpd->execute();
            } else {
                $stIns = $conn->prepare("INSERT INTO rh_meter (dorm_id, room_id, month, year, water_old, water_new, elec_old, elec_new, user_id) VALUES (?,?,?,?,?,?,?,?,?)");
                $stIns->bind_param("iiiiiiiii", $dorm_id, $room_id, $month, $year, $prevW, $newW, $prevE, $newE, $tid);
                $stIns->execute();
            }
        }
        $conn->commit();
        ok(["saved" => count($items)]);
    } catch (Throwable $e) { $conn->rollback(); fail($e->getMessage(), 500); }
}
fail("Action '$action' ไม่ถูกต้อง");