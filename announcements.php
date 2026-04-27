<?php
ob_start();
header("Content-Type: application/json; charset=utf-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

error_reporting(E_ALL);
ini_set('display_errors', 0);

require_once __DIR__ . "/db.php";
$conn->set_charset("utf8mb4");

function jexit($arr, $code = 200) {
    http_response_code($code);
    if (ob_get_length()) {
        ob_clean();
    }
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}

function getBaseUrl() {
    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || (($_SERVER['SERVER_PORT'] ?? '') == 443);
    $scheme = $https ? 'https' : 'http';
    $host = $_SERVER['HTTP_HOST'] ?? 'localhost';

    $scriptName = $_SERVER['SCRIPT_NAME'] ?? '';
    $dir = rtrim(str_replace('\\', '/', dirname($scriptName)), '/');

    return $scheme . '://' . $host . ($dir ? $dir . '/' : '/');
}

function normalizeImageUrl($imagePath) {
    $imagePath = trim((string)$imagePath);
    if ($imagePath === '') return '';

    if (preg_match('~^https?://~i', $imagePath)) {
        return $imagePath;
    }

    return getBaseUrl() . ltrim(str_replace("\\", "/", $imagePath), '/');
}

function deleteLocalImageIfExists($imagePath) {
    $imagePath = trim((string)$imagePath);
    if ($imagePath === '') return;

    $cleanPath = str_replace("\\", "/", $imagePath);
    $fullPath = __DIR__ . "/" . ltrim($cleanPath, '/');

    if (file_exists($fullPath) && is_file($fullPath)) {
        @unlink($fullPath);
    }
}

function getOldImagePath($conn, $announceId) {
    $stmt = $conn->prepare("SELECT image FROM rh_announcements WHERE announce_id=? LIMIT 1");
    $stmt->bind_param("i", $announceId);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    return $row['image'] ?? '';
}

function saveUploadedImage($fileKey = 'image') {
    if (!isset($_FILES[$fileKey])) {
        return [false, null, "ไม่พบไฟล์รูปภาพ"];
    }

    if ($_FILES[$fileKey]['error'] !== UPLOAD_ERR_OK) {
        return [false, null, "อัปโหลดรูปภาพไม่สำเร็จ"];
    }

    $allowedExt = ['jpg', 'jpeg', 'png', 'webp'];
    $originalName = $_FILES[$fileKey]['name'] ?? '';
    $ext = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));

    if (!in_array($ext, $allowedExt, true)) {
        return [false, null, "อนุญาตเฉพาะไฟล์ jpg, jpeg, png, webp"];
    }

    $dir = "uploads/announcements/";
    $absoluteDir = __DIR__ . "/" . $dir;

    if (!is_dir($absoluteDir)) {
        if (!@mkdir($absoluteDir, 0777, true) && !is_dir($absoluteDir)) {
            return [false, null, "ไม่สามารถสร้างโฟลเดอร์อัปโหลดได้"];
        }
    }

    $newName = $dir . "ann_" . uniqid('', true) . "." . $ext;
    $targetPath = __DIR__ . "/" . $newName;

    if (!move_uploaded_file($_FILES[$fileKey]['tmp_name'], $targetPath)) {
        return [false, null, "ไม่สามารถบันทึกไฟล์รูปภาพได้"];
    }

    return [true, $newName, null];
}

$action = $_REQUEST['action'] ?? '';

// -------------------- ACTION: LIST --------------------
if ($action === 'list') {
    $dormId = (int)($_GET['dorm_id'] ?? 0);
    if ($dormId <= 0) {
        jexit(["ok" => false, "message" => "dorm_id ไม่ถูกต้อง"], 400);
    }

    $sql = "SELECT announce_id, dorm_id, title, detail, image, is_pinned, status, created_at
            FROM rh_announcements
            WHERE dorm_id=?
            ORDER BY is_pinned DESC, announce_id DESC";

    $stmt = $conn->prepare($sql);
    $stmt->bind_param("i", $dormId);
    $stmt->execute();
    $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    foreach ($rows as &$row) {
        $row['image'] = normalizeImageUrl($row['image'] ?? '');
        $row['is_pinned'] = (int)($row['is_pinned'] ?? 0);
        $row['status'] = (strtolower((string)($row['status'] ?? 'active')) === 'hidden') ? 'hidden' : 'active';
    }

    jexit(["ok" => true, "data" => $rows ?: []]);
}

// -------------------- ACTION: DELETE --------------------
if ($action === 'delete') {
    $id = (int)($_POST['announce_id'] ?? 0);
    if ($id <= 0) {
        jexit(["ok" => false, "message" => "announce_id ไม่ถูกต้อง"], 400);
    }

    $oldImage = getOldImagePath($conn, $id);
    if ($oldImage !== '') {
        deleteLocalImageIfExists($oldImage);
    }

    $stmt = $conn->prepare("DELETE FROM rh_announcements WHERE announce_id=?");
    $stmt->bind_param("i", $id);
    $ok = $stmt->execute();
    $stmt->close();

    jexit([
        "ok" => $ok,
        "message" => $ok ? "ลบข้อมูลเรียบร้อย" : "ไม่สามารถลบข้อมูลได้"
    ]);
}

// -------------------- ACTION: UPDATE VISIBILITY --------------------
if ($action === 'update_visibility') {
    $id = (int)($_POST['announce_id'] ?? 0);
    $status = trim((string)($_POST['status'] ?? 'active'));

    if ($id <= 0) {
        jexit(["ok" => false, "message" => "announce_id ไม่ถูกต้อง"], 400);
    }

    if ($status !== 'active' && $status !== 'hidden') {
        $status = 'active';
    }

    $stmt = $conn->prepare("UPDATE rh_announcements SET status=? WHERE announce_id=?");
    $stmt->bind_param("si", $status, $id);
    $ok = $stmt->execute();
    $stmt->close();

    jexit([
        "ok" => $ok,
        "message" => $ok ? "อัปเดตสถานะเรียบร้อย" : "ไม่สามารถอัปเดตสถานะได้",
        "status" => $status
    ]);
}

// -------------------- ACTION: ADD / UPDATE --------------------
if ($action === 'add' || $action === 'update') {
    $id = (int)($_POST['announce_id'] ?? 0);
    $dormId = (int)($_POST['dorm_id'] ?? 0);
    $title = trim((string)($_POST['title'] ?? ''));
    $detail = trim((string)($_POST['detail'] ?? ''));
    $pinned = (int)($_POST['is_pinned'] ?? 0);
    $delImg = (int)($_POST['delete_image'] ?? 0);
    $status = trim((string)($_POST['status'] ?? 'active'));

    if ($status !== 'active' && $status !== 'hidden') {
        $status = 'active';
    }

    if ($dormId <= 0) {
        jexit(["ok" => false, "message" => "dorm_id ไม่ถูกต้อง"], 400);
    }

    if ($title === '') {
        jexit(["ok" => false, "message" => "กรุณากรอกหัวข้อประกาศ"], 400);
    }

    // ตัวแปรเช็คสถานะการอัปโหลดรูป
    $hasNewImage = false;
    $imagePath = ''; // เปลี่ยนจาก null เป็นสตริงว่าง

    // ตรวจสอบว่ามีการแนบไฟล์มาจริงๆ และขนาดมากกว่า 0
    if (isset($_FILES['image']) && $_FILES['image']['size'] > 0 && $_FILES['image']['error'] === UPLOAD_ERR_OK) {
        [$uploadOk, $uploadedPath, $uploadError] = saveUploadedImage('image');

        if (!$uploadOk) {
            jexit(["ok" => false, "message" => $uploadError], 400);
        }

        $imagePath = $uploadedPath;
        $hasNewImage = true; // ยืนยันว่ามีรูปใหม่เข้ามา

        // ถ้าเป็นการอัปเดต ให้ลบรูปเก่าทิ้ง
        if ($action === 'update' && $id > 0) {
            $oldImage = getOldImagePath($conn, $id);
            if ($oldImage !== '') {
                deleteLocalImageIfExists($oldImage);
            }
        }
    }

    if ($action === 'add') {
        $sql = "INSERT INTO rh_announcements 
                (dorm_id, title, detail, image, is_pinned, status, created_at)
                VALUES (?, ?, ?, ?, ?, ?, NOW())";
        $stmt = $conn->prepare($sql);
        $stmt->bind_param("isssis", $dormId, $title, $detail, $imagePath, $pinned, $status);
    } else {
        if ($id <= 0) {
            jexit(["ok" => false, "message" => "announce_id ไม่ถูกต้อง"], 400);
        }

        if ($hasNewImage) {
            // กรณีที่ 1: มีการอัปโหลดรูปใหม่เข้ามา (อัปเดตข้อมูล + เปลี่ยนรูป)
            $sql = "UPDATE rh_announcements 
                    SET title=?, detail=?, is_pinned=?, status=?, image=?
                    WHERE announce_id=?";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param("ssissi", $title, $detail, $pinned, $status, $imagePath, $id);
            
        } elseif ($delImg === 1) {
            // กรณีที่ 2: กดลบรูปทิ้ง (อัปเดตข้อมูล + ล้างค่ารูปลง DB เป็นค่าว่าง)
            $oldImage = getOldImagePath($conn, $id);
            if ($oldImage !== '') {
                deleteLocalImageIfExists($oldImage);
            }

            $emptyImg = '';
            $sql = "UPDATE rh_announcements 
                    SET title=?, detail=?, is_pinned=?, status=?, image=?
                    WHERE announce_id=?";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param("ssissi", $title, $detail, $pinned, $status, $emptyImg, $id);
            
        } else {
            // กรณีที่ 3: ไม่ได้แก้รูปเลย (อัปเดตแค่ข้อมูลตัวหนังสือ)
            $sql = "UPDATE rh_announcements 
                    SET title=?, detail=?, is_pinned=?, status=?
                    WHERE announce_id=?";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param("ssisi", $title, $detail, $pinned, $status, $id);
        }
    }

    $ok = $stmt->execute();
    $stmt->close();

    jexit([
        "ok" => $ok,
        "message" => $ok ? "บันทึกข้อมูลเรียบร้อย" : "เกิดข้อผิดพลาดในการบันทึกข้อมูล",
        "image" => $hasNewImage ? normalizeImageUrl($imagePath) : null // ส่ง path รูปใหม่กลับไป (ถ้ามี)
    ]);
}

jexit(["ok" => false, "message" => "Invalid action"], 400);