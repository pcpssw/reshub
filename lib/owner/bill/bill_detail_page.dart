import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config.dart';
import 'bill_owner_page.dart'; // import เพื่อดึงโมเดล BillItem มาใช้งานร่วมกัน

class BillDetailPage extends StatefulWidget {
  final BillItem item; // เปลี่ยนจาก dynamic เป็น BillItem เพื่อความปลอดภัยของข้อมูล
  final bool isAdmin;

  const BillDetailPage({
    super.key,
    required this.item,
    this.isAdmin = false,
  });

  @override
  State<BillDetailPage> createState() => _BillDetailPageState();
}

class _BillDetailPageState extends State<BillDetailPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cTextMain = Color(0xFF2A1F17);

  static const double fTitle = 16.0;
  static const double fHeader = 15.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;
  static const double fCaption = 11.0;

  late BillItem it; // กำหนด Type ให้ชัดเจนเพื่อป้องกันปัญหาตอนดึง property มาโชว์
  late String statusKey;
  bool loading = true; 
  bool saving = false;
  int userId = 0;

  @override
  void initState() {
    super.initState();
    it = widget.item;
    _updateStatusKey();
    _init();
  }

  void _updateStatusKey() {
    statusKey = (it.statusKey).toLowerCase().trim();
    const validStatuses = ["paid", "unpaid", "overdue", "no_tenant", "pending"];
    if (!validStatuses.contains(statusKey)) {
      statusKey = "unpaid";
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getInt("user_id") ?? 0;
    await _refreshDetail();
  }

  double _safeDouble(dynamic value) {
    if (value == null) return 0.0;
    return double.tryParse(value.toString()) ?? 0.0;
  }

  TextStyle _kanit({double? size, FontWeight? weight, Color? color}) {
    return GoogleFonts.kanit(
      fontSize: size,
      fontWeight: weight ?? FontWeight.normal,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50,
        title: Text("รายละเอียดบิล", style: _kanit(size: fHeader, color: cTextMain)),
        centerTitle: true,
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: cTextMain,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: cTextMain, strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _refreshDetail,
              color: cTextMain,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRoomInfoCard(),
                    const SizedBox(height: 16),
                    Text("สรุปค่าใช้จ่าย", style: _kanit(size: fBody, color: cTextMain)),
                    const SizedBox(height: 8),
                    _buildBillSummaryCard(),
                    const SizedBox(height: 16),
                    Text("หลักฐานการชำระเงิน", style: _kanit(size: fBody, color: cTextMain)),
                    const SizedBox(height: 8),
                    _buildSlipBox(),
                    const SizedBox(height: 24),
                    _buildActionSection(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRoomInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cTextMain, borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("ห้อง ${it.roomNumber}", style: _kanit(color: Colors.white, size: fTitle, weight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("ผู้เช่า: ${it.fullName ?? 'ไม่ระบุชื่อ'}", style: _kanit(color: Colors.white.withOpacity(0.8), size: fDetail)),
        ],
      ),
    );
  }

  Widget _buildBillSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
      ),
      child: Column(
        children: [
          _rowItem("ค่าเช่าห้อง", it.rent),
          if (it.commonFee > 0) _rowItem("ค่าส่วนกลาง", it.commonFee),
          _rowItemWithDetail("ค่าน้ำ", it.waterBill, it.waterUnit, it.waterPricePerUnit),
          _rowItemWithDetail("ค่าไฟ", it.elecBill, it.elecUnit, it.elecPricePerUnit),
          const Divider(height: 20, thickness: 0.5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("รวมสุทธิ", style: _kanit(size: fBody, color: cIcon)),
              Text("${it.calculatedTotal.toStringAsFixed(0)} บาท", style: _kanit(size: fTitle, weight: FontWeight.bold, color: cTextMain)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowItem(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: _kanit(color: cIcon, size: fDetail)),
        Text("${_safeDouble(value).toStringAsFixed(0)} บาท", style: _kanit(size: fDetail, color: cTextMain)),
      ],
    ),
  );

  Widget _rowItemWithDetail(String label, dynamic totalValue, dynamic unit, dynamic price) {
    double tV = _safeDouble(totalValue);
    double u = _safeDouble(unit);
    double p = _safeDouble(price);
    
    if (tV == 0) tV = u * p;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                style: _kanit(color: cIcon, size: fDetail),
                children: [
                  TextSpan(text: label),
                  TextSpan(
                    text: " (${u.toStringAsFixed(0)} หน่วย x ${p.toStringAsFixed(0)} บาท)",
                    style: _kanit(color: Colors.grey.shade600, size: fCaption),
                  ),
                ],
              ),
            ),
          ),
          Text("${tV.toStringAsFixed(0)} บาท", style: _kanit(size: fDetail, color: cTextMain)),
        ],
      ),
    );
  }

  Widget _buildSlipBox() {
    final imgUrl = _toImageUrl((it.slipImage ?? "").trim());
    return GestureDetector(
      onTap: imgUrl.isEmpty ? null : () => _openImageViewer(imgUrl),
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cAccent.withOpacity(0.5)),
        ),
        child: imgUrl.isEmpty
            ? Center(child: Text("ยังไม่มีสลิปชำระเงิน", style: _kanit(color: Colors.grey, size: fDetail)))
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(imgUrl, fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40)),
                ),
              ),
      ),
    );
  }

  Widget _buildActionSection() {
    if (widget.isAdmin) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("จัดการสถานะบิล", style: _kanit(size: fBody, color: cTextMain)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: (statusKey == "pending" || statusKey == "overdue") ? "unpaid" : statusKey,
            style: _kanit(size: fBody, color: cTextMain),
            decoration: InputDecoration(
              isDense: true, filled: true, fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cAccent, width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cTextMain, width: 1.5)),
            ),
            items: [
              DropdownMenuItem(value: "paid", child: Text("ชำระแล้ว", style: _kanit(size: fBody))),
              DropdownMenuItem(value: "unpaid", child: Text("ค้างชำระ", style: _kanit(size: fBody))),
            ],
            onChanged: (v) => setState(() => statusKey = v ?? statusKey),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: saving ? null : _saveStatus,
              style: ElevatedButton.styleFrom(backgroundColor: cTextMain, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              child: saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text("บันทึก", style: _kanit(color: Colors.white, size: fBody)),
            ),
          ),
        ],
      );
    } else {
      // 🌟 เช็กก่อนว่าแอดมินส่งบิลหรือยัง ถ้ายังไม่มี paymentId หรือเป็น 0 แปลว่ายังไม่ได้กดส่งบิล
      if (it.paymentId == null || it.paymentId == 0) {
        const Color fallbackColor = Color(0xFFF57C00); // ใช้สีส้ม/เหลืองนวลให้เข้ากับดีไซน์ธีม
        return Container(
          width: double.infinity, padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: fallbackColor.withOpacity(0.1), 
            borderRadius: BorderRadius.circular(15), 
            border: Border.all(color: fallbackColor.withOpacity(0.4))
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_empty_rounded, color: fallbackColor, size: 26),
              const SizedBox(width: 12),
              Text("อยู่ระหว่างจัดเตรียมบิล (ยังไม่ส่ง)", style: _kanit(color: fallbackColor, weight: FontWeight.bold, size: fBody)),
            ],
          ),
        );
      }

      // 🔹 ถ้าส่งบิลเข้าสู่ระบบแล้ว ค่อยแสดงผลสถานะจริงตามปกติ
      Color statusColor = statusKey == "paid" ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
      String statusText = "ค้างชำระ";
      if (statusKey == "paid") statusText = "ชำระเงินเรียบร้อยแล้ว";
      if (statusKey == "pending") statusText = "รอตรวจสอบการชำระเงิน";
      if (statusKey == "overdue") statusText = "เลยกำหนดชำระเงิน";
      
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: statusColor.withOpacity(0.4))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(statusKey == "paid" ? Icons.check_circle_outline : Icons.info_outline, color: statusColor, size: 26),
            const SizedBox(width: 12),
            Text(statusText, style: _kanit(color: statusColor, weight: FontWeight.bold, size: fBody)),
          ],
        ),
      );
    }
  }

  String _toImageUrl(String raw) => raw.isEmpty ? "" : (raw.startsWith("http") ? raw : AppConfig.url(raw));

  Future<void> _refreshDetail() async {
    setState(() => loading = true);
    try {
      final Map<String, String> bodyParams = {};
      
      if (it.paymentId != null && it.paymentId! > 0) {
        bodyParams["action"] = "getPaymentById";
        bodyParams["payment_id"] = it.paymentId.toString();
      } else {
        bodyParams["action"] = "get";
        bodyParams["user_id"] = widget.isAdmin ? (it.tenantId ?? userId).toString() : userId.toString();
        bodyParams["month"] = it.month.toString();
        bodyParams["year"] = it.year.toString();
      }

      final res = await http.post(Uri.parse(AppConfig.url("bills_api.php")), body: bodyParams);
      final data = jsonDecode(res.body);
      
      if (data["ok"] == true && data["data"] != null) {
        setState(() {
          // ใช้ Factory แปลงข้อมูล Map กลับมาเป็นคลาสวัตถุ BillItem เสมอ ข้อมูลจะไม่แครชเมื่อรีเฟรช
          it = BillItem.fromJson(Map<String, dynamic>.from(data["data"])); 
          _updateStatusKey();
        });
      }
    } catch (e) { 
      debugPrint("Refresh Error: ${e.toString()}"); 
    } finally { 
      setState(() => loading = false); 
    }
  }

  Future<void> _saveStatus() async {
    setState(() => saving = true);
    try {
      final res = await http.post(Uri.parse(AppConfig.url("bills_api.php")),
        body: {
          "action": "set_status",
          "dorm_id": it.dormId.toString(),
          "room_id": it.roomId.toString(),
          "month": it.month.toString(),
          "year": it.year.toString(),
          "status_key": statusKey,
          "user_id": userId.toString(),
        },
      );
      if (jsonDecode(res.body)["ok"] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("บันทึกสำเร็จ")));
        Navigator.pop(context, true);
      }
    } catch (e) { debugPrint(e.toString()); }
    finally { setState(() => saving = false); }
  }

  void _openImageViewer(String imgUrl) {
    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: Colors.black, insetPadding: EdgeInsets.zero,
      child: Stack(alignment: Alignment.topRight, children: [
        InteractiveViewer(child: Center(child: Image.network(imgUrl))),
        IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context)),
      ]),
    ));
  }
}