import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config.dart';
import 'room_model.dart';

class RoomDetailPage extends StatefulWidget {
  final int dormId;
  final Room room;

  const RoomDetailPage({
    super.key,
    required this.dormId,
    required this.room,
  });

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cTextMain = Color(0xFF2A1F17);
  static const Color cSoft = Color(0xFFEEE6DA);
  static const Color cBorder = Color(0xFFCBBBA7);
  static const Color cDanger = Color(0xFFC62828);

  static const double fHeader = 15.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;
  static const double fCaption = 11.0;

  late TextEditingController rentController;
  late RoomType type;
  late RoomStatus status;
  
  bool saving = false;
  late Room _room;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    rentController = TextEditingController(text: _room.rent.toString());
    type = _room.type;
    status = _room.status;
  }

  @override
  void dispose() {
    rentController.dispose();
    super.dispose();
  }

  Future<void> _deleteRoom() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon ส่วนหัว วงกลมสีแดง
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.redAccent,
                  size: 45,
                ),
              ),
              const SizedBox(height: 20),
              // หัวข้อ สีน้ำตาลเข้ม
              const Text(
                "ยืนยันการลบห้อง",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF523D2D), // cTeddy
                ),
              ),
              const SizedBox(height: 10),
              // เนื้อหาคำถาม พร้อมเว้นระยะบรรทัด (height: 1.5)
              Text(
                "คุณแน่ใจใช่ไหมที่จะลบห้อง\n${_room.roomNo} ใช่หรือไม่?",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 30),
              // แถวปุ่มกด
              Row(
                children: [
                  // ปุ่มยืนยัน (ElevatedButton สีน้ำตาลเข้ม)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF523D2D), // cTeddy
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: const Text(
                        "ยืนยัน",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // ปุ่มกลับ (OutlinedButton ขอบสีครีมทอง)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDCD2C1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        "ยกเลิก",
                        style: TextStyle(
                          color: Color(0xFF523D2D), // cTeddy
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // เช็คค่าที่ส่งกลับมา ถ้าไม่ใช่ true ให้จบทันที
    if (confirm != true) return;

    setState(() => saving = true);
    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("rooms_api.php")),
        body: {
          "action": "delete",
          "dorm_id": widget.dormId.toString(),
          "room_id": _room.roomId.toString(),
        },
      );
      final data = jsonDecode(res.body);
      if (data["ok"] == true && mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _saveChanges() async {
    if (saving) return;
    final newRent = int.tryParse(rentController.text.trim());
    if (newRent == null || newRent <= 0) return;

    setState(() => saving = true);
    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("rooms_api.php")),
        body: {
          "action": "update",
          "dorm_id": widget.dormId.toString(),
          "room_id": _room.roomId.toString(),
          "rent_price": rentController.text.trim(),
          "room_type": type.dbValue,
          "status": status.dbValue,
        },
      );
      final data = jsonDecode(res.body);
      if (data["ok"] == true && mounted) Navigator.pop(context, true);
    } catch (_) {
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 60,
        elevation: 0.5,
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: cTextMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "รายละเอียดห้อง ${_room.roomNo}",
          style: const TextStyle(
            color: cTextMain,
            fontWeight: FontWeight.w900,
            fontSize: fHeader,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildPriceInput(),
                const SizedBox(height: 24),
                _buildSectionTitle("ข้อมูลห้องพัก"),
                _buildInfoCard(),
                const SizedBox(height: 24),
                _buildSectionTitle("ข้อมูลผู้เช่า"),
                _buildTenantCard(_room.tenant),
              ],
            ),
          ),
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: SizedBox(
              height: 55,
              child: OutlinedButton(
                onPressed: saving ? null : _deleteRoom,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: cDanger, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  "ลบห้อง",
                  style: TextStyle(color: cDanger, fontWeight: FontWeight.bold, fontSize: fBody),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: SizedBox(
              height: 55,
              child: ElevatedButton(
                onPressed: saving ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cIcon,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        "บันทึก",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: fBody),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceInput() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
      ),
      child: Column(
        children: [
          Row(
            children: const [
              Icon(Icons.payments_rounded, size: 20, color: cIcon),
              SizedBox(width: 12),
              Text("ค่าเช่าต่อเดือน", style: TextStyle(fontWeight: FontWeight.w600, fontSize: fDetail)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: rentController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            // ลดขนาดตัวเลขลงเหลือ 22 ให้ดูพอดี
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cTextMain),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              suffixText: "บาท",
              filled: true,
              fillColor: cBg.withOpacity(0.6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rowInfoStatic("อาคาร", _room.building, Icons.business),
          const Divider(height: 24, color: cBg),
          Row(
            children: [
              Expanded(child: _rowInfoStatic("ชั้น", "${_room.floor}", Icons.layers)),
              const SizedBox(width: 1, height: 30, child: VerticalDivider(color: cBorder)),
              Expanded(child: _rowInfoStatic("เลขห้อง", _room.roomNo, Icons.tag)),
            ],
          ),
          const Divider(height: 32, color: cBg, thickness: 2),
          const Text("ประเภทห้องพัก", style: TextStyle(fontWeight: FontWeight.w800, fontSize: fBody)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _typeBtn(RoomType.air, "แอร์", Icons.ac_unit)),
              const SizedBox(width: 12),
              Expanded(child: _typeBtn(RoomType.fan, "พัดลม", Icons.wind_power)),
            ],
          ),
          const SizedBox(height: 24),
          const Text("สถานะห้องพัก", style: TextStyle(fontWeight: FontWeight.w800, fontSize: fBody)),
          const SizedBox(height: 12),
          _statusBtn(RoomStatus.available, "ว่าง", Icons.check_circle_outline),
          const SizedBox(height: 8),
          _statusBtn(RoomStatus.occupied, "ไม่ว่าง", Icons.person_off_outlined),
          const SizedBox(height: 8),
          _statusBtn(RoomStatus.maintenance, "ซ่อม", Icons.build_circle_outlined),
        ],
      ),
    );
  }

  Widget _typeBtn(RoomType t, String label, IconData icon) {
    bool isSel = type == t;
    return GestureDetector(
      onTap: () => setState(() => type = t),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSel ? cIcon : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSel ? cIcon : cBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSel ? Colors.white : cIcon),
            Text(label, style: TextStyle(color: isSel ? Colors.white : cTextMain, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _statusBtn(RoomStatus s, String label, IconData icon) {
    bool isSel = status == s;
    return GestureDetector(
      onTap: () => setState(() => status = s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSel ? cIcon : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSel ? cIcon : cBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSel ? Colors.white : cIcon, size: 20),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: isSel ? Colors.white : cTextMain, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (isSel) const Icon(Icons.check, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildTenantCard(TenantInfo? tenant) {
    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: tenant == null 
        ? const Center(child: Text("ไม่มีข้อมูลผู้เช่า", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)))
        : Column(
            children: [
              _rowInfoStatic("ชื่อผู้เช่า", tenant.name ?? "-", Icons.person),
              const SizedBox(height: 12),
              _rowInfoStatic("เบอร์โทร", tenant.phone ?? "-", Icons.phone),
            ],
          ),
    );
  }

  Widget _rowInfoStatic(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cIcon),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: fCaption, color: Colors.black54)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: fBody)),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: fHeader)),
    );
  }
}