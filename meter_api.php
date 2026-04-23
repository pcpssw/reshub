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

// ---------------- รับค่า ----------------
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
$month   = (int)param("month", date("n"));
$year    = (int)param("year", date("Y"));

if ($dorm_id <= 0) fail("ไม่พบ dorm_id");

$prevMonth = $month - 1;
$prevYear  = $year;
if ($prevMonth <= 0) {
    $prevMonth = 12;
    $prevYear--;
}

# =====================================================
# ✅ GET
# =====================================================
if ($action === "get") {
    try {
        $sql = "
            SELECT
                r.room_id,
                r.room_number,
                r.tenant_id,
                COALESCE(u.full_name, '') AS full_name,
                COALESCE(b.building_name, '') AS building,
                COALESCE(pm.water_new, 0) AS prev_w,
                COALESCE(pm.elec_new, 0) AS prev_e,
                COALESCE(cm.water_new, 0) AS cur_w,
                COALESCE(cm.elec_new, 0) AS cur_e
            FROM rh_rooms r
            LEFT JOIN rh_users u ON u.user_id = r.tenant_id
            LEFT JOIN rh_buildings b ON b.building_id = r.building_id
            LEFT JOIN rh_meter pm
                ON pm.dorm_id = r.dorm_id
               AND pm.room_id = r.room_id
               AND pm.month = ?
               AND pm.year = ?
            LEFT JOIN rh_meter cm
                ON cm.dorm_id = r.dorm_id
               AND cm.room_id = r.room_id
               AND cm.month = ?
               AND cm.year = ?
            WHERE r.dorm_id = ?
            ORDER BY b.building_name, r.room_number
        ";

        $st = $conn->prepare($sql);
        $st->bind_param("iiiii", $prevMonth, $prevYear, $month, $year, $dorm_id);
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
                "current_electric_meter" => (int)$row["cur_e"],
            ];
        }

        ok(["rooms" => $rooms]);

    } catch (Throwable $e) {
        fail($e->getMessage(), 500);
    }
}

# =====================================================
# ✅ SAVE (แก้บัคแล้ว)
# =====================================================
if ($action === "save") {

    $items = param("items");
    if (!is_array($items) || empty($items)) fail("ไม่มีข้อมูล");

    try {
        $conn->begin_transaction();

        $stPrev = $conn->prepare("
            SELECT water_new, elec_new
            FROM rh_meter
            WHERE dorm_id=? AND room_id=? AND month=? AND year=?
        ");

        $stCur = $conn->prepare("
            SELECT reading_id, water_new, elec_new
            FROM rh_meter
            WHERE dorm_id=? AND room_id=? AND month=? AND year=?
        ");

        $stUpd = $conn->prepare("
            UPDATE rh_meter
            SET water_old=?, water_new=?, elec_old=?, elec_new=?
            WHERE reading_id=?
        ");

        $stIns = $conn->prepare("
            INSERT INTO rh_meter
            (dorm_id, room_id, month, year, water_old, water_new, elec_old, elec_new)
            VALUES (?,?,?,?,?,?,?,?)
        ");

        $saved = 0;

        foreach ($items as $it) {

            $room_id = (int)($it['room_id'] ?? 0);
            if ($room_id <= 0) continue;

            // 🔹 เดือนก่อน
            $stPrev->bind_param("iiii", $dorm_id, $room_id, $prevMonth, $prevYear);
            $stPrev->execute();
            $prev = $stPrev->get_result()->fetch_assoc();

            $prevW = $prev ? (int)$prev['water_new'] : 0;
            $prevE = $prev ? (int)$prev['elec_new'] : 0;

            // 🔹 เดือนนี้ (สำคัญ)
            $stCur->bind_param("iiii", $dorm_id, $room_id, $month, $year);
            $stCur->execute();
            $cur = $stCur->get_result()->fetch_assoc();

            // ✅ FIX: ใช้ค่าปัจจุบัน ถ้าไม่ได้ส่งมา
            $newW = array_key_exists('water_meter', $it)
                ? (int)$it['water_meter']
                : ($cur ? (int)$cur['water_new'] : $prevW);

            $newE = array_key_exists('electric_meter', $it)
                ? (int)$it['electric_meter']
                : ($cur ? (int)$cur['elec_new'] : $prevE);

            // 🔥 กันเลขย้อน
            if ($newW < $prevW) fail("น้ำย้อนหลังห้อง $room_id");
            if ($newE < $prevE) fail("ไฟย้อนหลังห้อง $room_id");

            if ($cur) {
                // 🔥 UPDATE
                $reading_id = (int)$cur['reading_id'];
                $stUpd->bind_param("iiiii", $prevW, $newW, $prevE, $newE, $reading_id);
                $stUpd->execute();
            } else {
                // ➕ INSERT
                $stIns->bind_param("iiiiiiii",
                    $dorm_id, $room_id, $month, $year,
                    $prevW, $newW, $prevE, $newE
                );
                $stIns->execute();
            }

            $saved++;
        }

        $conn->commit();
        ok(["saved" => $saved]);

    } catch (Throwable $e) {
        $conn->rollback();
        fail($e->getMessage(), 500);
    }
}

fail("Unknown action");
