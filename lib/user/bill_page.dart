import 'dart:convert';
import 'dart:io';

import 'package:docman/docman.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../config.dart';
import 'expense_summary_page.dart';

class BillPage extends StatefulWidget {
  const BillPage({super.key});

  @override
  State<BillPage> createState() => _BillPageState();
}

class _BillPageState extends State<BillPage> {
  static const double fTitle = 18.0;
  static const double fHeader = 15.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;
  static const double fCaption = 11.0;

  static const Color _bgColor = Color(0xFFF4EFE6);
  static const Color _cardColor = Colors.white;
  static const Color _textColor = Color(0xFF523D2D);
  static const Color _mutedColor = Color(0xFF7D6552);
  static const Color _lineColor = Color(0xFFD7CCC8);

  File? slip;

  bool _loading = true;
  bool _submitting = false;
  bool _pickingSlip = false;
  bool _noBill = false;

  String get apiUrl => AppConfig.url("bills_api.php");

  int _userId = 0;
  int _paymentId = 0;
  int month = DateTime.now().month;
  int year = DateTime.now().year;

  String roomText = "ไม่มีข้อมูล";
  double rent = 0, water = 0, electric = 0, total = 0;
  double waterUnit = 0, waterPricePerUnit = 0;
  double electricUnit = 0, electricPricePerUnit = 0;

  String status = "unpaid";
  String? slipFromServer;
  String? payDate;
  List<Map<String, dynamic>> bankAccounts = [];

  final _moneyFmt = NumberFormat("#,##0", "en_US");
  late DateFormat _thaiMonthFmt;

  bool get _hasServerSlip =>
      (slipFromServer != null && slipFromServer!.trim().isNotEmpty);

  bool get _isLockedPaid =>
      ["verified", "paid", "done", "pending"].contains(
        status.toLowerCase().trim(),
      );

  @override
  void initState() {
    super.initState();
    _initThaiLocaleThenLoad();
  }

  Future<void> _initThaiLocaleThenLoad() async {
    try {
      await initializeDateFormatting('th_TH', null);
    } catch (_) {}
    _thaiMonthFmt = DateFormat.MMMM('th_TH');
    if (mounted) {
      setState(() {});
      await _loadBill();
    }
  }

  Future<void> _loadBill() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _noBill = false;
      slip = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getInt("user_id") ??
          int.tryParse(prefs.getString("user_id") ?? "0") ??
          0;

      if (_userId <= 0) {
        setState(() => _noBill = true);
        return;
      }

      final res = await http
          .post(
            Uri.parse(apiUrl),
            body: {
              "action": "get",
              "user_id": _userId.toString(),
              "month": month.toString(),
              "year": year.toString(),
            },
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (data is Map && data["success"] == true) {
        final p = Map<String, dynamic>.from(data["data"] ?? {});
        setState(() {
          _paymentId = int.tryParse("${p["payment_id"]}") ?? 0;
          roomText = p["room_number"]?.toString() ?? "ไม่ทราบเลขห้อง";
          water = _toDouble(p["water_price"]);
          electric = _toDouble(p["electric_price"]);
          waterUnit = _toDouble(p["water_unit"]);
          waterPricePerUnit = _toDouble(p["water_rate"]);
          electricUnit = _toDouble(p["electric_unit"]);
          electricPricePerUnit = _toDouble(p["electric_rate"]);
          total = _toDouble(p["total_price"]);
          rent = total - water - electric;
          status = (p["status"] ?? "unpaid").toString();
          slipFromServer = p["slip_image"]?.toString();
          payDate = p["pay_date"]?.toString();
          bankAccounts = (p["accounts"] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];
          _noBill = false;
        });
      } else {
        setState(() => _noBill = true);
      }
    } catch (_) {
      setState(() => _noBill = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _toDouble(dynamic v) =>
      double.tryParse(v.toString().replaceAll(",", "")) ?? 0;

  void _toast(String msg) {}

  String _statusText(String s) {
    final v = s.toLowerCase().trim();
    if (v == "verified" || v == "paid" || v == "done") return "ชำระแล้ว";
    if (v == "pending") return "รอตรวจสอบ";
    return "ยังไม่ชำระ";
  }

  Color _statusColor(String s) {
    final v = s.toLowerCase().trim();
    if (v == "verified" || v == "paid" || v == "done") return Colors.green;
    if (v == "pending") return Colors.orange;
    return Colors.redAccent;
  }

  String _thaiMonthText() =>
      "${_thaiMonthFmt.format(DateTime(year, month, 1))} ${year + 543}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0.5,
        title: const Text(
          "บิลค่าเช่า",
          style: TextStyle(
            color: _textColor,
            fontSize: fHeader,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          // ✅ ปุ่มสรุปรายปี สไตล์ OutlinedButton
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            child: OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExpensePage()), // เชื่อมไปยัง ExpensePage (หน้าสรุปรายปี)
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color.fromARGB(255, 172, 170, 170), width: 1.2), // เปลี่ยนสีที่นี่
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text(
                "สรุปรายปี",
                style: TextStyle(
                  color: _textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: _textColor,
                  strokeWidth: 2,
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadBill,
                color: _textColor,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
                  children: [
                    _buildMonthPicker(),
                    const SizedBox(height: 10),
                    if (_noBill) _buildNoDataView() else _buildMainBillCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildMainBillCard() {
    final Color statusColor = _statusColor(status);
    final String statusText = _statusText(status);
    final bool isPaid =
        ["verified", "paid", "done"].contains(status.toLowerCase());
    final String imageUrl = _hasServerSlip ? AppConfig.url(slipFromServer!) : "";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _lineColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: const BoxDecoration(
              color: _textColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        const TextSpan(
                          text: "ห้อง ",
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        TextSpan(
                          text: roomText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isPaid
                            ? Icons.check_circle_rounded
                            : Icons.access_time_filled_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _summaryTile("ค่าเช่า", "${_moneyFmt.format(rent)} ฿"),
                const SizedBox(height: 8),
                _summaryTile(
                  "ค่าน้ำ",
                  "${_moneyFmt.format(water)} ฿",
                  sub:
                      "${waterUnit.toStringAsFixed(0)} หน่วย × ${_moneyFmt.format(waterPricePerUnit)} ฿/หน่วย",
                ),
                const SizedBox(height: 8),
                _summaryTile(
                  "ค่าไฟ",
                  "${_moneyFmt.format(electric)} ฿",
                  sub:
                      "${electricUnit.toStringAsFixed(0)} หน่วย × ${_moneyFmt.format(electricPricePerUnit)} ฿/หน่วย",
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _bgColor.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _lineColor),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "รวมสุทธิ",
                          style: TextStyle(
                            color: _textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        "${_moneyFmt.format(total)} ฿",
                        style: const TextStyle(
                          color: _textColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _buildPaymentChannelButton(),
                const SizedBox(height: 14),
                if (_hasServerSlip || slip != null) ...[
                  Stack(
                    children: [
                      InkWell(
                        onTap: () {
                          if (_hasServerSlip) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SlipPreviewPage(imageUrl: imageUrl),
                              ),
                            );
                          }
                        },
                        child: Container(
                          height: 250,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _lineColor),
                            color: Colors.grey.shade50,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: _hasServerSlip
                                ? Image.network(imageUrl, fit: BoxFit.contain)
                                : Image.file(slip!, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      if (status.toLowerCase() == "pending" && _hasServerSlip)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () async {
                              if (await _showConfirmDeleteDialog()) {
                                _deleteServerSlip();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.8),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      if (slip != null && !_hasServerSlip)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => slip = null),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.8),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ] else if (!_isLockedPaid) ...[
                  InkWell(
                    onTap: pickSlip,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 165,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _lineColor),
                        color: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.18),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.add_a_photo_rounded,
                            color: Color.fromARGB(255, 114, 84, 59),
                            size: 42,
                          ),
                          SizedBox(height: 8),
                          Text(
                            "แตะเพื่อเลือกรูปสลิป",
                            style: TextStyle(
                              fontSize: 13,
                               color: Color.fromARGB(255, 114, 84, 59),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (slip != null && !_isLockedPaid) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submitSlip,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _textColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _submitting ? "กำลังส่งข้อมูล..." : "ยืนยันการชำระเงิน",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentChannelButton() {
    return InkWell(
      onTap: () {
        if (bankAccounts.isEmpty) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BankDetailPage(bankAccounts: bankAccounts),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _lineColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.account_balance_rounded, color: _textColor, size: 18),
            SizedBox(width: 8),
            Text(
              "ดูช่องทางการโอน",
              style: TextStyle(
                color: _textColor,
                fontSize: fBody,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _lineColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: _textColor,
            ),
            onPressed: () {
              setState(() {
                if (month == 1) {
                  month = 12;
                  year--;
                } else {
                  month--;
                }
              });
              _loadBill();
            },
          ),
          Text(
            _thaiMonthText(),
            style: const TextStyle(
              fontSize: fBody,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: _textColor,
            ),
            onPressed: () {
              setState(() {
                if (month == 12) {
                  month = 1;
                  year++;
                } else {
                  month++;
                }
              });
              _loadBill();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataView() {
    final monthName = _thaiMonthFmt.format(DateTime(year, month, 1));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_a_photo_rounded,
            size: 80,
            color: _mutedColor.withOpacity(0.1),
          ),
          const SizedBox(height: 24),
          Text(
            "ยังไม่มีข้อมูลบิล",
            style: TextStyle(
              fontSize: fHeader,
              fontWeight: FontWeight.bold,
              color: _textColor.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "ประจำเดือน $monthName พ.ศ. ${year + 543}",
            style: TextStyle(fontSize: fDetail, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(String title, String price, {String? sub}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _lineColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: fBody,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                  ),
                ),
                if (sub != null && sub.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: fCaption, color: Colors.grey),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            price,
            style: const TextStyle(
              fontSize: fBody,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> pickSlip() async {
    if (_pickingSlip || _isLockedPaid) return;

    setState(() => _pickingSlip = true);
    try {
      final files = await DocMan.pick.visualMedia(
        mimeTypes: const ['image/*'],
        extensions: const ['jpg', 'jpeg', 'png', 'webp'],
        localOnly: true,
        useVisualMediaPicker: true,
        limit: 1,
        imageQuality: 70,
      );

      if (files.isNotEmpty) {
        setState(() => slip = files.first);
      }
    } catch (e) {
      debugPrint('pick slip error: $e');
    } finally {
      if (mounted) setState(() => _pickingSlip = false);
    }
  }

  Future<void> _submitSlip() async {
    if (slip == null || _submitting) return;
    if (await _showConfirmSendDialog()) {
      setState(() => _submitting = true);
      try {
        final request = http.MultipartRequest("POST", Uri.parse(apiUrl));
        request.fields['action'] = "pay";
        request.fields['user_id'] = _userId.toString();
        request.fields['payment_id'] = _paymentId.toString();
        request.files.add(
          await http.MultipartFile.fromPath('slip', slip!.path),
        );
        final response = await http.Response.fromStream(await request.send());
        if (jsonDecode(response.body)["success"] == true) {
          _loadBill();
        }
      } catch (_) {
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
    }
  }

  Future<void> _deleteServerSlip() async {
    try {
      final res = await http.post(
        Uri.parse(apiUrl),
        body: {
          "action": "delete_slip",
          "user_id": _userId.toString(),
          "payment_id": _paymentId.toString(),
        },
      );
      if (jsonDecode(res.body)["success"] == true) {
        _loadBill();
      }
    } catch (_) {}
  }

  Future<bool> _showConfirmDeleteDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  const Text(
                    "ยืนยันการลบ",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "คุณต้องการลบหลักฐานการโอน\nใช่หรือไม่?",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: fDetail, color: Colors.grey),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _textColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: const Text(
                            "ยืนยันลบ",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _lineColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: const Text(
                            "ยกเลิก",
                            style: TextStyle(
                              color: _textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ) ??
        false;
  }

  Future<bool> _showConfirmSendDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.blueAccent,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "ยืนยันการส่งสลิป",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "คุณตรวจสอบความถูกต้อง\nของรูปภาพสลิปเรียบร้อยแล้วใช่หรือไม่?",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: fDetail, color: Colors.grey),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _textColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
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
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _lineColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: const Text(
                            "ยกเลิก",
                            style: TextStyle(
                              color: _textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ) ??
        false;
  }
}

class BankDetailPage extends StatelessWidget {
  final List<Map<String, dynamic>> bankAccounts;
  const BankDetailPage({super.key, required this.bankAccounts});

  Color _getBankColor(String? bankName) {
    final name = bankName?.toLowerCase() ?? "";
    if (name.contains("กสิกร")) return const Color(0xFF13804E);
    if (name.contains("ไทยพาณิชย์") || name.contains("scb")) {
      return const Color(0xFF4E2E7F);
    }
    if (name.contains("กรุงเทพ")) return const Color(0xFF1E4598);
    if (name.contains("กรุงไทย")) return const Color(0xFF00A1E0);
    if (name.contains("กรุงศรี")) return const Color(0xFFB59300);
    if (name.contains("ttb") || name.contains("ทหารไทย")) {
      return const Color(0xFFE65A28);
    }
    if (name.contains("ออมสิน")) return const Color(0xFFD81B60);
    return const Color(0xFF523D2D);
  }

  @override
  Widget build(BuildContext context) {
    const Color textColor = Color(0xFF523D2D);
    const Color bgColor = Color(0xFFF4EFE6);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: const Text(
          "ช่องทางการโอนเงิน",
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: textColor, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: bankAccounts.isEmpty
            ? const Center(
                child: Text(
                  "ยังไม่มีข้อมูลบัญชี",
                  style: TextStyle(color: textColor),
                ),
              )
            : ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                itemCount: bankAccounts.length,
                itemBuilder: (ctx, i) {
                  final a = bankAccounts[i];
                  final bankColor = _getBankColor(a["bank_name"]);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: bankColor.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: bankColor.withOpacity(0.06),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: bankColor,
                                child: const Icon(
                                  Icons.account_balance,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                a["bank_name"] ?? "",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: bankColor,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: a["account_no"] ?? "",
                                    ),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("คัดลอกเลขบัญชีแล้ว"),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: bankColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.copy_rounded,
                                    size: 18,
                                    color: bankColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                "เลขที่บัญชี",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                a["account_no"] ?? "",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: bankColor,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "ชื่อบัญชี: ${a["account_name"] ?? ""}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class SlipPreviewPage extends StatelessWidget {
  final String imageUrl;
  const SlipPreviewPage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("สลิป", style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Center(
          child: InteractiveViewer(
            child: Image.network(imageUrl),
          ),
        ),
      ),
    );
  }
}