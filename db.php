<?php

$host = "203.158.223.154";
$user = "reshub";
$pass = "CET2026kkw";
$dbname = "reshub"; 

$conn = new mysqli($host, $user, $pass, $dbname);
$conn->set_charset("utf8mb4");

if ($conn->connect_error) {
    die(json_encode(["success" => false, "message" => "Connection failed"]));
}