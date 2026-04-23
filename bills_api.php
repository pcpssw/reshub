<?php
ob_start();
ini_set('display_errors', '0');
ini_set('html_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

register_shutdown_function(function () {
    $e = error_get_last();
    if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR], true)) {
        if (!headers_sent()) {
            header('Content-Type: application/json; charset=utf-8');
            http_response_code(500);
        }
        if (ob_get_length()) ob_clean();
        echo json_encode([
            'ok' => false,
            'success' => false,
            'message' => 'PHP Fatal: ' . $e['message']
        ], JSON_UNESCAPED_UNICODE);
    }
});

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db.php';
mysqli_set_charset($conn, 'utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function jok(array $data = [], int $code = 200): void {
    if (ob_get_length()) ob_clean();
    http_response_code($code);
    echo json_encode(array_merge(['ok' => true, 'success' => true], $data), JSON_UNESCAPED_UNICODE);
    exit;
}

function jfail(string $message, int $code = 400, array $extra = []): void {
    if (ob_get_length()) ob_clean();
    http_response_code($code);
    echo json_encode(array_merge(['ok' => false, 'success' => false, 'message' => $message], $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

function reqv(string $key, $default = null) {
    static $json = null;
    if (isset($_POST[$key])) return $_POST[$key];
    if (isset($_GET[$key])) return $_GET[$key];
    if ($json === null) {
        $raw = file_get_contents('php://input');
        $json = json_decode($raw, true);
        if (!is_array($json)) $json = [];
    }
    return $json[$key] ?? $default;
}

function has_column(mysqli $conn, string $table, string $column): bool {
    $table = $conn->real_escape_string($table);
    $column = $conn->real_escape_string($column);
    $res = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$column'");
    return $res && $res->num_rows > 0;
}

function slips_file_path(): string {
    return __DIR__ . '/payment_slips.json';
}

function load_slip_map(): array {
    $file = slips_file_path();
    if (!file_exists($file)) return [];
    $txt = @file_get_contents($file);
    $arr = json_decode($txt, true);
    return is_array($arr) ? $arr : [];
}

function save_slip_map(array $map): void {
    @file_put_contents(slips_file_path(), json_encode($map, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
}

function get_slip_path_for_payment(int $paymentId): ?string {
    $map = load_slip_map();
    if (isset($map[$paymentId]['path']) && is_string($map[$paymentId]['path'])) {
        return $map[$paymentId]['path'];
    }
    return null;
}

function set_slip_path_for_payment(int $paymentId, string $path): void {
    $map = load_slip_map();
    $map[$paymentId] = [
        'path' => $path,
        'updated_at' => date('c'),
    ];
    save_slip_map($map);
}

function delete_slip_path_for_payment(int $paymentId): ?string {
    $map = load_slip_map();
    $old = null;
    if (isset($map[$paymentId]['path'])) $old = $map[$paymentId]['path'];
    unset($map[$paymentId]);
    save_slip_map($map);
    return $old;
}

function due_date_str($year, $month, $billing_day): string {
    $lastDay = cal_days_in_month(CAL_GREGORIAN, max(1, min(12, intval($month))), intval($year));
    $day = max(1, min($lastDay, intval($billing_day)));
    return sprintf('%04d-%02d-%02d', intval($year), intval($month), $day);
}

function map_status($payment_status, $month, $year, $hasTenant, $billing_day = 5): array {
    if (!$hasTenant) {
        return ['key' => 'no_tenant', 'label' => 'ห้องว่าง', 'color' => '#9E9E9E'];
    }

    $ps = strtolower(trim((string)$payment_status));
    if ($ps === 'verified' || $ps === 'paid') {
        return ['key' => 'paid', 'label' => 'ชำระแล้ว', 'color' => '#4CAF50'];
    }

    $due = due_date_str($year, $month, $billing_day) . ' 23:59:59';
    if (strtotime(date('Y-m-d H:i:s')) > strtotime($due)) {
        return ['key' => 'overdue', 'label' => 'เลยกำหนด', 'color' => '#FF9800'];
    }

    return ['key' => 'unpaid', 'label' => 'ค้างชำระ', 'color' => '#F44336'];
}

function getDormSettings(mysqli $conn, int $dorm_id): array {
    $st = $conn->prepare('SELECT water_rate, electric_rate FROM rh_dorm_settings WHERE dorm_id=? LIMIT 1');
    $st->bind_param('i', $dorm_id);
    $st->execute();
    $row = $st->get_result()->fetch_assoc() ?: [];
    $st->close();

    return [
        'water_rate' => floatval($row['water_rate'] ?? 0),
        'electric_rate' => floatval($row['electric_rate'] ?? 0),
        'billing_day' => 5,
    ];
}

function calc_bill_parts($baseRent, $waterOld, $waterNew, $elecOld, $elecNew, $waterRate, $electricRate): array {
    $waterUnit = max(0, intval($waterNew) - intval($waterOld));
    $elecUnit = max(0, intval($elecNew) - intval($elecOld));
    $waterBill = $waterUnit * floatval($waterRate);
    $elecBill = $elecUnit * floatval($electricRate);
    $utilityTotal = $waterBill + $elecBill;
    $commonFee = 0.0;
    $total = floatval($baseRent) + $utilityTotal + $commonFee;

    return [
        'rent' => floatval($baseRent),
        'water_unit' => $waterUnit,
        'elec_unit' => $elecUnit,
        'water_bill' => $waterBill,
        'elec_bill' => $elecBill,
        'utility_total' => $utilityTotal,
        'common_fee' => $commonFee,
        'total' => $total,
    ];
}

function latest_meter_join_sql(): string {
    return "
        LEFT JOIN rh_meter m
               ON m.reading_id = (
                    SELECT mm.reading_id
                    FROM rh_meter mm
                    WHERE mm.dorm_id = r.dorm_id
                      AND mm.room_id = r.room_id
                      AND (
                            (mm.year = ? AND mm.month = ?)
                            OR ((mm.year * 100 + mm.month) <= (? * 100 + ?))
                          )
                    ORDER BY
                        CASE WHEN mm.year = ? AND mm.month = ? THEN 0 ELSE 1 END,
                        mm.year DESC, mm.month DESC
                    LIMIT 1
               )
    ";
}

function notify_dorm_admins(mysqli $conn, int $dormId, string $message, int $typeId = 2, int $refId = 0): void {
    $sql = "SELECT user_id FROM rh_dorm_memberships WHERE dorm_id = ? AND approve_status = 'approved' AND role_code IN ('a','o')";
    $st = $conn->prepare($sql);
    if (!$st) return;
    $st->bind_param('i', $dormId);
    $st->execute();
    $res = $st->get_result();
    $ins = $conn->prepare('INSERT INTO rh_notifications (user_id, dorm_id, type_id, ref_id, message, is_read) VALUES (?, ?, ?, ?, ?, 0)');
    if ($ins) {
        while ($row = $res->fetch_assoc()) {
            $uid = (int)$row['user_id'];
            $ins->bind_param('iiiis', $uid, $dormId, $typeId, $refId, $message);
            $ins->execute();
        }
        $ins->close();
    }
    $st->close();
}

function find_user_room(mysqli $conn, int $user_id): ?array {
    $st = $conn->prepare('SELECT room_id, dorm_id, room_number FROM rh_rooms WHERE tenant_id = ? ORDER BY room_id DESC LIMIT 1');
    if (!$st) return null;
    $st->bind_param('i', $user_id);
    $st->execute();
    $row = $st->get_result()->fetch_assoc();
    $st->close();
    if ($row) return $row;

    $st2 = $conn->prepare("SELECT m.dorm_id, r.room_id, r.room_number
                           FROM rh_dorm_memberships m
                           LEFT JOIN rh_rooms r ON r.tenant_id = m.user_id AND r.dorm_id = m.dorm_id
                           WHERE m.user_id = ? AND m.approve_status = 'approved'
                           ORDER BY r.room_id DESC, m.membership_id DESC
                           LIMIT 1");
    if (!$st2) return null;
    $st2->bind_param('i', $user_id);
    $st2->execute();
    $row2 = $st2->get_result()->fetch_assoc();
    $st2->close();
    return $row2 ?: null;
}

function handle_generic_upload(mysqli $conn): void {
    if (!isset($_FILES['image'])) {
        jfail('ไม่พบไฟล์ image', 400);
    }

    $target_dir = 'uploads/';
    $targetAbsDir = __DIR__ . '/' . $target_dir;
    if (!is_dir($targetAbsDir)) @mkdir($targetAbsDir, 0755, true);

    $original = basename($_FILES['image']['name'] ?? '');
    $ext = strtolower(pathinfo($original, PATHINFO_EXTENSION));
    if ($ext === '') $ext = 'jpg';
    $newName = 'img_' . date('Ymd_His') . '_' . bin2hex(random_bytes(4)) . '.' . preg_replace('/[^a-z0-9]/i', '', $ext);
    $targetRel = $target_dir . $newName;
    $targetAbs = __DIR__ . '/' . $targetRel;

    $tmpPath = $_FILES['image']['tmp_name'] ?? '';
    if ($tmpPath === '' || !move_uploaded_file($tmpPath, $targetAbs)) {
        jfail('ย้ายไฟล์ไม่สำเร็จ', 500);
    }

    $savedToDb = false;
    $dbError = null;
    try {
        $chk = $conn->query("SHOW TABLES LIKE 'dormitory_images'");
        if ($chk && $chk->num_rows > 0) {
            $stmt = $conn->prepare('INSERT INTO dormitory_images (file_name, upload_date) VALUES (?, NOW())');
            $stmt->bind_param('s', $newName);
            $savedToDb = $stmt->execute();
            $stmt->close();
        }
    } catch (Throwable $e) {
        $dbError = $e->getMessage();
    }

    jok([
        'status' => 'success',
        'message' => 'บันทึกเรียบร้อย',
        'file_name' => $newName,
        'path' => $targetRel,
        'saved_to_db' => $savedToDb,
        'db_error' => $dbError,
    ]);
}

$action = trim((string)reqv('action', ''));
if ($action === '' && isset($_FILES['image'])) {
    $action = 'upload';
}
if ($action === '') {
    $action = 'list';
}

$hasSlipColumn = has_column($conn, 'rh_payments', 'slip_image');
$hasPaymentDateColumn = has_column($conn, 'rh_payments', 'payment_date');

if ($action === 'upload') {
    handle_generic_upload($conn);
}

if ($action === 'get') {
    $user_id = intval(reqv('user_id', 0));
    $month   = intval(reqv('month', 0));
    $year    = intval(reqv('year', 0));

    if ($user_id <= 0 || $month <= 0 || $year <= 0) {
        jfail('ข้อมูลไม่ครบ', 400);
    }

    $room = find_user_room($conn, $user_id);
    if (!$room || empty($room['room_id']) || empty($room['dorm_id'])) {
        jfail('คุณยังไม่ได้ผูกห้องพักในหอนี้', 200, ['debug' => ['user_id' => $user_id]]);
    }

    $dorm_id = (int)$room['dorm_id'];
    $room_id = (int)$room['room_id'];
    $room_number = (string)($room['room_number'] ?? '-');

    $accounts = [];
    $stB = $conn->prepare('SELECT bank_name, account_name, account_no FROM rh_bank_accounts WHERE dorm_id = ? ORDER BY bank_id ASC');
    $stB->bind_param('i', $dorm_id);
    $stB->execute();
    $resB = $stB->get_result();
    while ($b = $resB->fetch_assoc()) $accounts[] = $b;
    $stB->close();

    $selectSlip = $hasSlipColumn ? 'p.slip_image,' : 'NULL AS slip_image,';
    $sql = "SELECT
                p.payment_id,
                p.user_id,
                p.room_id,
                p.total_amount,
                p.status,
                $selectSlip
                COALESCE(met.water_old, 0) AS water_old,
                COALESCE(met.water_new, 0) AS water_new,
                COALESCE(met.elec_old, 0) AS elec_old,
                COALESCE(met.elec_new, 0) AS elec_new,
                COALESCE(s.water_rate, 0) AS water_rate,
                COALESCE(s.electric_rate, 0) AS electric_rate
            FROM rh_payments p
            LEFT JOIN rh_meter met ON met.room_id = p.room_id AND met.month = p.month AND met.year = p.year
            LEFT JOIN rh_dorm_settings s ON s.dorm_id = p.dorm_id
            WHERE p.month = ?
              AND p.year = ?
              AND (
                    (p.user_id = ?)
                    OR (p.room_id = ?)
                  )
            ORDER BY CASE WHEN p.user_id = ? THEN 0 ELSE 1 END, p.payment_id DESC
            LIMIT 1";
    $st = $conn->prepare($sql);
    $st->bind_param('iiiii', $month, $year, $user_id, $room_id, $user_id);
    $st->execute();
    $p = $st->get_result()->fetch_assoc();
    $st->close();

    if (!$p) {
        jfail("ยังไม่มีบิลสำหรับเดือน $month/$year", 200, [
            'room_number' => $room_number,
            'accounts' => $accounts,
            'debug' => [
                'user_id' => $user_id,
                'room_id' => $room_id,
                'dorm_id' => $dorm_id,
                'month' => $month,
                'year' => $year,
            ]
        ]);
    }

    $waterUnit = max(0, (float)$p['water_new'] - (float)$p['water_old']);
    $elecUnit = max(0, (float)$p['elec_new'] - (float)$p['elec_old']);

    $slip_image = !empty($p['slip_image']) ? $p['slip_image'] : get_slip_path_for_payment((int)$p['payment_id']);

    $rawStatus = strtolower(trim((string)$p['status']));
    if ($rawStatus === 'verified') {
        $uiStatus = 'paid';
    } elseif ($rawStatus === 'pending') {
        $uiStatus = $slip_image ? 'pending' : 'unpaid';
    } else {
        $uiStatus = 'unpaid';
    }

    jok([
        'data' => [
            'payment_id'     => (int)$p['payment_id'],
            'room_number'    => $room_number,
            'water_unit'     => $waterUnit,
            'water_rate'     => (float)$p['water_rate'],
            'water_price'    => $waterUnit * (float)$p['water_rate'],
            'electric_unit'  => $elecUnit,
            'electric_rate'  => (float)$p['electric_rate'],
            'electric_price' => $elecUnit * (float)$p['electric_rate'],
            'total_price'    => (float)$p['total_amount'],
            'status'         => $uiStatus,
            'slip_image'     => $slip_image,
            'accounts'       => $accounts,
        ],
        'debug' => [
            'user_id' => $user_id,
            'room_id' => $room_id,
            'dorm_id' => $dorm_id,
            'payment_user_id' => (int)($p['user_id'] ?? 0),
            'payment_room_id' => (int)($p['room_id'] ?? 0),
        ]
    ]);
}

if ($action === 'pay') {
    $user_id = intval(reqv('user_id', 0));
    $payment_id = intval(reqv('payment_id', 0));
    if ($payment_id <= 0) jfail('ไม่พบ payment_id', 400);
    if (!isset($_FILES['slip'])) jfail('กรุณาแนบไฟล์สลิป', 400);

    $stC = $conn->prepare("SELECT p.payment_id, p.dorm_id, p.room_id, r.room_number
                           FROM rh_payments p
                           JOIN rh_rooms r ON r.room_id = p.room_id
                           WHERE p.payment_id = ?
                             AND (p.user_id = ? OR r.tenant_id = ?)
                           LIMIT 1");
    $stC->bind_param('iii', $payment_id, $user_id, $user_id);
    $stC->execute();
    $info = $stC->get_result()->fetch_assoc();
    $stC->close();

    if (!$info) jfail('ไม่พบข้อมูลบิลของผู้ใช้คนนี้', 404);

    $uploadDirRel = 'uploads/slips/';
    $uploadDirAbs = __DIR__ . '/' . $uploadDirRel;
    if (!is_dir($uploadDirAbs)) @mkdir($uploadDirAbs, 0755, true);

    $ext = strtolower(pathinfo($_FILES['slip']['name'] ?? '', PATHINFO_EXTENSION));
    if ($ext === '') $ext = 'jpg';
    $newName = 'slip_' . $payment_id . '_' . time() . '.' . preg_replace('/[^a-z0-9]/i', '', $ext);
    $pathRel = $uploadDirRel . $newName;
    $pathAbs = __DIR__ . '/' . $pathRel;

    if (!move_uploaded_file($_FILES['slip']['tmp_name'], $pathAbs)) {
        jfail('ไม่สามารถอัปโหลดไฟล์ได้', 500);
    }

    $oldPath = get_slip_path_for_payment($payment_id);
    if ($oldPath && file_exists(__DIR__ . '/' . $oldPath)) @unlink(__DIR__ . '/' . $oldPath);
    set_slip_path_for_payment($payment_id, $pathRel);

    if ($hasSlipColumn && $hasPaymentDateColumn) {
        $stU = $conn->prepare("UPDATE rh_payments SET slip_image = ?, status = 'pending', payment_date = NOW() WHERE payment_id = ?");
        $stU->bind_param('si', $pathRel, $payment_id);
        $stU->execute();
        $stU->close();
    } elseif ($hasSlipColumn) {
        $stU = $conn->prepare("UPDATE rh_payments SET slip_image = ?, status = 'pending' WHERE payment_id = ?");
        $stU->bind_param('si', $pathRel, $payment_id);
        $stU->execute();
        $stU->close();
    } else {
        $stU = $conn->prepare("UPDATE rh_payments SET status = 'pending' WHERE payment_id = ?");
        $stU->bind_param('i', $payment_id);
        $stU->execute();
        $stU->close();
    }

    notify_dorm_admins($conn, (int)$info['dorm_id'], 'ห้อง ' . $info['room_number'] . ' แจ้งชำระเงินแล้ว', 2, $payment_id);

    jok(['message' => 'ส่งหลักฐานการชำระเงินเรียบร้อย', 'slip_image' => $pathRel]);
}

if ($action === 'delete_slip') {
    $payment_id = intval(reqv('payment_id', 0));
    $user_id = intval(reqv('user_id', 0));
    if ($payment_id <= 0) jfail('ไม่พบ payment_id', 400);

    $st = $conn->prepare("SELECT p.payment_id, p.status, p.dorm_id
                          FROM rh_payments p
                          JOIN rh_rooms r ON r.room_id = p.room_id
                          WHERE p.payment_id = ?
                            AND (p.user_id = ? OR r.tenant_id = ?)
                          LIMIT 1");
    $st->bind_param('iii', $payment_id, $user_id, $user_id);
    $st->execute();
    $info = $st->get_result()->fetch_assoc();
    $st->close();

    if (!$info) jfail('ไม่พบข้อมูลบิล', 404);

    $old = delete_slip_path_for_payment($payment_id);
    if ($old && file_exists(__DIR__ . '/' . $old)) @unlink(__DIR__ . '/' . $old);

    if ($hasSlipColumn) {
        $stU = $conn->prepare("UPDATE rh_payments SET slip_image = NULL, status = 'rejected' WHERE payment_id = ?");
        $stU->bind_param('i', $payment_id);
        $stU->execute();
        $stU->close();
    } else {
        $stU = $conn->prepare("UPDATE rh_payments SET status = 'rejected' WHERE payment_id = ?");
        $stU->bind_param('i', $payment_id);
        $stU->execute();
        $stU->close();
    }

    jok(['message' => 'ยกเลิกสลิปเรียบร้อย']);
}

if ($action === 'getPaymentById') {
    $payment_id = intval(reqv('payment_id', 0));
    if ($payment_id <= 0) jfail('ไม่พบ payment_id');

    $selectSlip = $hasSlipColumn ? 'p.slip_image,' : 'NULL AS slip_image,';
    $selectPayDate = $hasPaymentDateColumn ? 'p.payment_date,' : 'NULL AS payment_date,';

    $st = $conn->prepare("SELECT
            p.payment_id,
            p.user_id,
            p.dorm_id,
            p.room_id,
            p.month,
            p.year,
            p.total_amount,
            p.status,
            $selectSlip
            $selectPayDate
            p.room_id AS payment_room_id
        FROM rh_payments p
        WHERE p.payment_id=?
        LIMIT 1");
    $st->bind_param('i', $payment_id);
    $st->execute();
    $payment = $st->get_result()->fetch_assoc();
    $st->close();

    if (!$payment) jfail('ไม่พบบิล');

    $dorm_id = intval($payment['dorm_id']);
    $room_id = intval($payment['room_id']);
    $month = intval($payment['month']);
    $year = intval($payment['year']);

    $settings = getDormSettings($conn, $dorm_id);

    $sql = "SELECT
            r.room_id,
            r.dorm_id,
            r.room_number,
            r.floor,
            r.base_rent,
            r.tenant_id,
            b.building_name,
            u.full_name,
            u.phone,
            p.payment_id,
            p.status AS payment_status,
            p.total_amount,
            " . ($hasSlipColumn ? 'p.slip_image,' : 'NULL AS slip_image,') . "
            " . ($hasPaymentDateColumn ? 'p.payment_date,' : 'NULL AS payment_date,') . "
            m.water_old,
            m.water_new,
            m.elec_old,
            m.elec_new
        FROM rh_rooms r
        LEFT JOIN rh_buildings b ON b.building_id = r.building_id
        LEFT JOIN rh_users u ON u.user_id = r.tenant_id
        LEFT JOIN rh_payments p
               ON p.dorm_id = r.dorm_id
              AND p.room_id = r.room_id
              AND p.month = ?
              AND p.year = ?
        " . latest_meter_join_sql() . "
        WHERE r.dorm_id = ?
          AND r.room_id = ?
        LIMIT 1";

    $stmt = $conn->prepare($sql);
    $stmt->bind_param(
        'iiiiiiiiii',
        $month, $year,
        $year, $month,
        $year, $month,
        $year, $month,
        $dorm_id, $room_id
    );
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$row) jfail('ไม่พบข้อมูลบิล');

    $parts = calc_bill_parts(
        $row['base_rent'] ?? 0,
        $row['water_old'] ?? 0,
        $row['water_new'] ?? 0,
        $row['elec_old'] ?? 0,
        $row['elec_new'] ?? 0,
        $settings['water_rate'],
        $settings['electric_rate']
    );

    $hasTenant = !empty($row['tenant_id']);
    $stt = map_status($row['payment_status'] ?? '', $month, $year, $hasTenant, $settings['billing_day']);

    $slipImage = !empty($row['slip_image'])
        ? (string)$row['slip_image']
        : get_slip_path_for_payment((int)($row['payment_id'] ?? $payment_id));

    $payDate = $row['payment_date'] ?? null;

    jok([
        'data' => [
            'payment_id' => intval($row['payment_id'] ?? 0),
            'room_id' => intval($row['room_id']),
            'dorm_id' => intval($row['dorm_id']),
            'room_number' => (string)($row['room_number'] ?? ''),
            'building' => (string)($row['building_name'] ?? ''),
            'floor' => intval($row['floor'] ?? 0),
            'tenant_id' => empty($row['tenant_id']) ? null : intval($row['tenant_id']),
            'full_name' => $row['full_name'] ?? null,
            'phone' => $row['phone'] ?? null,
            'month' => $month,
            'year' => $year,
            'due_date' => due_date_str($year, $month, $settings['billing_day']),
            'payment_status' => (string)($row['payment_status'] ?? 'pending'),
            'status_key' => $stt['key'],
            'status_label' => $stt['label'],
            'status_color' => $stt['color'],
            'rent' => $parts['rent'],
            'utility_total' => $parts['utility_total'],
            'common_fee' => $parts['common_fee'],
            'total' => floatval($row['total_amount'] ?? $parts['total']),
            'slip_image' => $slipImage,
            'pay_date' => $payDate,
            'water_bill' => $parts['water_bill'],
            'elec_bill' => $parts['elec_bill'],
            'water_unit' => $parts['water_unit'],
            'water_price_per_unit' => floatval($settings['water_rate']),
            'elec_unit' => $parts['elec_unit'],
            'elec_price_per_unit' => floatval($settings['electric_rate']),
        ]
    ]);
}

if ($action === 'bulk_send') {
    $dorm_id = intval(reqv('dorm_id', 0));
    $month = intval(reqv('month', date('n')));
    $year = intval(reqv('year', date('Y')));

    if ($dorm_id <= 0) jfail('dorm_id ไม่ถูกต้อง');

    $settings = getDormSettings($conn, $dorm_id);

    $sqlRooms = "SELECT r.room_id, r.room_number, r.base_rent, r.tenant_id
        FROM rh_rooms r
        WHERE r.dorm_id = ?
          AND r.tenant_id IS NOT NULL
          AND r.status = 'occupied'
        ORDER BY r.room_number ASC";
    $stR = $conn->prepare($sqlRooms);
    $stR->bind_param('i', $dorm_id);
    $stR->execute();
    $rooms = $stR->get_result();

    if ($rooms->num_rows === 0) {
        $stR->close();
        jfail('ไม่พบห้องที่มีผู้เช่าอยู่');
    }

    $created = 0;
    $skipped = 0;

    while ($r = $rooms->fetch_assoc()) {
        $room_id = intval($r['room_id']);
        $user_id = intval($r['tenant_id']);
        $baseRent = floatval($r['base_rent']);

        $check = $conn->prepare('SELECT payment_id FROM rh_payments WHERE dorm_id=? AND room_id=? AND user_id=? AND month=? AND year=? LIMIT 1');
        $check->bind_param('iiiii', $dorm_id, $room_id, $user_id, $month, $year);
        $check->execute();
        $exists = $check->get_result()->fetch_assoc();
        $check->close();

        if ($exists) {
            $skipped++;
            continue;
        }

        $stM = $conn->prepare('SELECT water_old, water_new, elec_old, elec_new FROM rh_meter WHERE dorm_id=? AND room_id=? AND month=? AND year=? LIMIT 1');
        $stM->bind_param('iiii', $dorm_id, $room_id, $month, $year);
        $stM->execute();
        $m = $stM->get_result()->fetch_assoc() ?: [];
        $stM->close();

        $parts = calc_bill_parts(
            $baseRent,
            $m['water_old'] ?? 0,
            $m['water_new'] ?? 0,
            $m['elec_old'] ?? 0,
            $m['elec_new'] ?? 0,
            $settings['water_rate'],
            $settings['electric_rate']
        );

        $ins = $conn->prepare("INSERT INTO rh_payments (user_id, dorm_id, room_id, month, year, total_amount, status)
            VALUES (?, ?, ?, ?, ?, ?, 'pending')");
        $ins->bind_param('iiiiid', $user_id, $dorm_id, $room_id, $month, $year, $parts['total']);
        $ins->execute();
        $paymentId = (int)$ins->insert_id;
        $ins->close();

        $created++;

        $message = 'บิลเดือน ' . sprintf('%02d/%04d', $month, $year) . ' ยอดรวม ' . number_format($parts['total'], 2) . ' บาท';
        $noti = $conn->prepare('INSERT INTO rh_notifications (user_id, dorm_id, type_id, ref_id, message, is_read) VALUES (?, ?, 2, ?, ?, 0)');
        $noti->bind_param('iiis', $user_id, $dorm_id, $paymentId, $message);
        $noti->execute();
        $noti->close();
    }

    $stR->close();
    jok([
        'message' => "ส่งบิลสำเร็จ {$created} ห้อง",
        'created' => $created,
        'skipped' => $skipped,
    ]);
}

if ($action === 'list') {
    $dorm_id = intval(reqv('dorm_id', 0));
    $month = intval(reqv('month', date('n')));
    $year = intval(reqv('year', date('Y')));
    $statusFilter = trim((string)reqv('status', 'all'));

    if ($dorm_id <= 0) jfail('ระบุ dorm_id');

    $settings = getDormSettings($conn, $dorm_id);

    $sql = "SELECT
            r.room_id,
            r.dorm_id,
            r.room_number,
            r.floor,
            r.base_rent,
            r.tenant_id,
            b.building_name,
            u.full_name,
            u.phone,
            p.payment_id,
            p.status AS payment_status,
            p.total_amount,
            " . ($hasSlipColumn ? 'p.slip_image,' : 'NULL AS slip_image,') . "
            " . ($hasPaymentDateColumn ? 'p.payment_date,' : 'NULL AS payment_date,') . "
            m.water_old,
            m.water_new,
            m.elec_old,
            m.elec_new
        FROM rh_rooms r
        LEFT JOIN rh_buildings b ON b.building_id = r.building_id
        LEFT JOIN rh_users u ON u.user_id = r.tenant_id
        LEFT JOIN rh_payments p
               ON p.dorm_id = r.dorm_id
              AND p.room_id = r.room_id
              AND p.month = ?
              AND p.year = ?
        " . latest_meter_join_sql() . "
        WHERE r.dorm_id = ?
        ORDER BY COALESCE(b.building_name, ''), r.floor ASC, r.room_number ASC";

    $stmt = $conn->prepare($sql);
    $stmt->bind_param(
        'iiiiiiiii',
        $month, $year,
        $year, $month,
        $year, $month,
        $year, $month,
        $dorm_id
    );
    $stmt->execute();
    $res = $stmt->get_result();

    $rows = [];
    while ($row = $res->fetch_assoc()) {
        $parts = calc_bill_parts(
            $row['base_rent'] ?? 0,
            $row['water_old'] ?? 0,
            $row['water_new'] ?? 0,
            $row['elec_old'] ?? 0,
            $row['elec_new'] ?? 0,
            $settings['water_rate'],
            $settings['electric_rate']
        );

        $hasTenant = !empty($row['tenant_id']);
        $stt = map_status($row['payment_status'] ?? '', $month, $year, $hasTenant, $settings['billing_day']);

        if ($statusFilter !== 'all' && $statusFilter !== '' && $stt['key'] !== $statusFilter) {
            continue;
        }

        $slipImage = !empty($row['slip_image'])
            ? (string)$row['slip_image']
            : (!empty($row['payment_id']) ? get_slip_path_for_payment((int)$row['payment_id']) : null);

        $payDate = $row['payment_date'] ?? null;

        $rows[] = [
            'room_id' => intval($row['room_id']),
            'dorm_id' => intval($row['dorm_id']),
            'room_number' => (string)($row['room_number'] ?? ''),
            'building' => (string)($row['building_name'] ?? 'A'),
            'floor' => intval($row['floor'] ?? 0),
            'tenant_id' => empty($row['tenant_id']) ? null : intval($row['tenant_id']),
            'full_name' => $row['full_name'] ?? null,
            'phone' => $row['phone'] ?? null,
            'month' => $month,
            'year' => $year,
            'due_date' => due_date_str($year, $month, $settings['billing_day']),
            'payment_id' => empty($row['payment_id']) ? null : intval($row['payment_id']),
            'payment_status' => (string)($row['payment_status'] ?? 'pending'),
            'status_key' => $stt['key'],
            'status_label' => $stt['label'],
            'status_color' => $stt['color'],
            'rent' => $parts['rent'],
            'utility_total' => $parts['utility_total'],
            'common_fee' => $parts['common_fee'],
            'total' => floatval($row['total_amount'] ?? $parts['total']),
            'slip_image' => $slipImage,
            'pay_date' => $payDate,
            'water_bill' => $parts['water_bill'],
            'elec_bill' => $parts['elec_bill'],
            'water_unit' => $parts['water_unit'],
            'water_price_per_unit' => floatval($settings['water_rate']),
            'elec_unit' => $parts['elec_unit'],
            'elec_price_per_unit' => floatval($settings['electric_rate']),
        ];
    }
    $stmt->close();

    jok(['data' => $rows]);
}

if ($action === 'set_status') {
    $dorm_id = intval(reqv('dorm_id', 0));
    $room_id = intval(reqv('room_id', 0));
    $month = intval(reqv('month', 0));
    $year = intval(reqv('year', 0));
    $status_key = trim((string)reqv('status_key', ''));

    if ($dorm_id <= 0 || $room_id <= 0 || $month <= 0 || $year <= 0) {
        jfail('ข้อมูลไม่ครบ');
    }

    $statusMap = [
        'paid' => 'verified',
        'unpaid' => 'pending',
        'overdue' => 'pending',
        'no_tenant' => 'pending',
    ];
    $newStatus = $statusMap[$status_key] ?? 'pending';

    $st = $conn->prepare('SELECT payment_id, user_id FROM rh_payments WHERE dorm_id=? AND room_id=? AND month=? AND year=? ORDER BY payment_id DESC LIMIT 1');
    $st->bind_param('iiii', $dorm_id, $room_id, $month, $year);
    $st->execute();
    $payment = $st->get_result()->fetch_assoc();
    $st->close();

    if (!$payment) jfail('ไม่พบบิล');

    $up = $conn->prepare('UPDATE rh_payments SET status=? WHERE payment_id=?');
    $up->bind_param('si', $newStatus, $payment['payment_id']);
    if (!$up->execute()) {
        $up->close();
        jfail('อัปเดตไม่สำเร็จ');
    }
    $up->close();

    if (!empty($payment['user_id'])) {
        $message = ($newStatus === 'verified')
            ? 'บิลเดือน ' . sprintf('%02d/%04d', $month, $year) . ' ได้รับการยืนยันแล้ว'
            : 'บิลเดือน ' . sprintf('%02d/%04d', $month, $year) . ' ถูกปรับสถานะเป็นค้างชำระ';
        $paymentIdForNoti = (int)$payment['payment_id'];
        $noti = $conn->prepare('INSERT INTO rh_notifications (user_id, dorm_id, type_id, ref_id, message, is_read) VALUES (?, ?, 2, ?, ?, 0)');
        $noti->bind_param('iiis', $payment['user_id'], $dorm_id, $paymentIdForNoti, $message);
        $noti->execute();
        $noti->close();
    }

    jok(['message' => 'อัปเดตสำเร็จ ✅']);
}

jfail('ไม่พบ Action', 400);
