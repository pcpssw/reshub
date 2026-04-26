class RepairModel {
  final int repairId;
  final String type;      // ชื่อประเภทภาษาไทย (เช่น ไฟฟ้า, ประปา)
  final String room;      // ชื่อตึก - เลขห้อง
  final String status;    // pending, working, done
  final String statusTh;  // รอดำเนินการ, กำลังดำเนินการ, เสร็จสิ้น
  final String detail;
  final String image;
  final String createdAt;
  final String fullName;  // ชื่อผู้แจ้ง (สำหรับ Admin)
  final String phone;     // เบอร์โทร (สำหรับ Admin)

  RepairModel({
    required this.repairId,
    required this.type,
    required this.room,
    required this.status,
    String? statusTh,     // รับค่า optional
    required this.detail,
    required this.image,
    required this.createdAt,
    this.fullName = '',
    this.phone = '',
  }) : // ถ้าไม่ได้ส่ง statusTh มา ให้ใช้ฟังก์ชันช่วยแปลงจาก status ภาษาอังกฤษ
       statusTh = statusTh ?? _convertToThaiStatus(status);

  // ฟังก์ชันช่วยแปลงสถานะเป็นภาษาไทยอัตโนมัติ
  static String _convertToThaiStatus(String s) {
    final status = s.toLowerCase().trim();
    if (status.contains('working')) return 'กำลังดำเนินการ';
    if (status.contains('done')) return 'เสร็จสิ้น';
    return 'รอดำเนินการ';
  }

  factory RepairModel.fromJson(Map<String, dynamic> json) {
    // รวมชื่อตึกและเลขห้องให้สวยงาม
    String bName = json['building_name']?.toString() ?? '';
    String rNum = json['room_number']?.toString() ?? '';
    String combinedRoom = "$bName $rNum".trim();
    if (combinedRoom.isEmpty) combinedRoom = json['room']?.toString() ?? '-';

    return RepairModel(
      repairId: int.tryParse(json['repair_id']?.toString() ?? '0') ?? 0,
      type: json['type_name'] ?? json['repair_type']?.toString() ?? 'ทั่วไป',
      room: combinedRoom,
      status: json['status']?.toString() ?? 'pending',
      statusTh: json['status_th']?.toString(), // ปล่อยให้ Constructor จัดการถ้าเป็น null
      detail: json['detail']?.toString() ?? '',
      image: json['repair_image'] ?? json['image_path']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
    );
  }
}