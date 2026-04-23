import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

// =========================================================
// 🏢 1. หน้าหลัก: รายชื่อผู้ใช้งาน (PlatformUserListPage)
// =========================================================
class PlatformUserListPage extends StatefulWidget {
  const PlatformUserListPage({super.key});

  @override
  State<PlatformUserListPage> createState() => _PlatformUserListPageState();
}

class _PlatformUserListPageState extends State<PlatformUserListPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _isAdding = false;
  List<dynamic> _allUsers = [];
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  final _formKey = GlobalKey<FormState>();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();
  bool saving = false;
  bool obscure = true;

  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cTextMain = Color(0xFF2A1F17);
  static const Color cDark = Color(0xFF523D2D);

  // อิงขนาดจาก TenantListAdminPage
  static const double fHeader = 15.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;
  static const double fCaption = 11.0;
  static const double fSubCard = 12.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    fetchUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
    confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchUsers() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final url = Uri.parse("${AppConfig.baseUrl}/dashboard_api.php");
      final res = await http
          .post(url, body: {"action": "listUsers"})
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["success"] == true) {
          setState(() => _allUsers = data["data"] ?? []);
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => saving = true);

    try {
      final res = await http.post(
        Uri.parse("${AppConfig.baseUrl}/dashboard_api.php"),
        body: {
          "action": "addAdmin",
          "full_name": nameCtrl.text.trim(),
          "username": userCtrl.text.trim(),
          "password": passCtrl.text,
          "phone": phoneCtrl.text.trim(),
        },
      );

      final data = jsonDecode(res.body);
      if (data["success"]) {
        setState(() => _isAdding = false);
        fetchUsers();
        _clearForm();
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _clearForm() {
    nameCtrl.clear();
    phoneCtrl.clear();
    userCtrl.clear();
    passCtrl.clear();
    confirmPassCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isAdding,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isAdding) {
          setState(() => _isAdding = false);
        }
      },
      child: _isAdding ? _buildAddAdminPage() : _buildUserListPage(),
    );
  }

  Widget _buildUserListPage() {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 50,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: cTextMain,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "รายชื่อผู้ใช้งาน",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: cTextMain,
            fontSize: fHeader,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_tabController.index == 1)
            IconButton(
              icon: const Icon(
                Icons.person_add_alt_1_rounded,
                color: cDark,
                size: 24,
              ),
              onPressed: () => setState(() => _isAdding = true),
            ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: cTextMain,
              unselectedLabelColor: Colors.grey,
              indicatorColor: cTextMain,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: fDetail,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: fDetail,
              ),
              tabs: const [
                Tab(text: "ผู้ดูแลหอพัก"),
                Tab(text: "ผู้ดูแลระบบ"),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBox(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: cDark),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildUserList(false),
                      _buildUserList(true),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddAdminPage() {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 50,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: cTextMain,
          ),
          onPressed: () => setState(() => _isAdding = false),
        ),
        title: const Text(
          "เพิ่มผู้ดูแลระบบ",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: cTextMain,
            fontSize: fHeader,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildSectionCard(
                title: "ข้อมูลผู้ดูแลระบบ",
                icon: Icons.admin_panel_settings_rounded,
                children: [
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: nameCtrl,
                    style: const TextStyle(
                      fontSize: fBody,
                      color: cTextMain,
                    ),
                    decoration: _dec("ชื่อ-นามสกุล", Icons.person_outline),
                    validator: (v) => v!.isEmpty ? "กรุณากรอกชื่อ" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(
                      fontSize: fBody,
                      color: cTextMain,
                    ),
                    decoration: _dec(
                      "เบอร์โทรศัพท์",
                      Icons.phone_android_rounded,
                    ),
                    validator: (v) => v!.isEmpty ? "กรุณากรอกเบอร์" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: userCtrl,
                    style: const TextStyle(
                      fontSize: fBody,
                      color: cTextMain,
                    ),
                    decoration: _dec(
                      "Username",
                      Icons.alternate_email_rounded,
                    ),
                    validator: (v) =>
                        v!.isEmpty ? "กรุณากรอก Username" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passCtrl,
                    obscureText: obscure,
                    style: const TextStyle(
                      fontSize: fBody,
                      color: cTextMain,
                    ),
                    decoration: _dec(
                      "รหัสผ่าน",
                      Icons.lock_outline_rounded,
                      suffix: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                          color: cDark,
                        ),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                    validator: (v) =>
                        v!.length < 4 ? "รหัสต้อง 4 ตัวขึ้นไป" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: confirmPassCtrl,
                    obscureText: obscure,
                    style: const TextStyle(
                      fontSize: fBody,
                      color: cTextMain,
                    ),
                    decoration: _dec(
                      "ยืนยันรหัสผ่าน",
                      Icons.lock_reset_rounded,
                    ),
                    validator: (v) =>
                        v != passCtrl.text ? "รหัสไม่ตรงกัน" : null,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: saving ? null : _saveAdmin,
                  child: saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Text(
                          "บันทึกข้อมูล",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: fHeader,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(
            fontSize: fBody,
            fontWeight: FontWeight.bold,
            color: cTextMain,
          ),
          decoration: InputDecoration(
            hintText: "ค้นหาชื่อ หรือเบอร์โทร...",
            hintStyle: const TextStyle(
              fontSize: fDetail,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 20,
              color: cDark,
            ),
            filled: true,
            fillColor: cBg.withOpacity(0.3),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserList(bool isSystemAdmin) {
    final list = _allUsers.where((u) {
      final bool isMatchRole = isSystemAdmin
          ? u['platform_role'] == 'platform_admin'
          : (u['dorm_name'] != null && u['dorm_name'].toString().isNotEmpty);

      final String fullName = (u['full_name'] ?? "").toString().toLowerCase();
      final String phone = (u['phone'] ?? "").toString().toLowerCase();
      final String q = _searchQuery.toLowerCase();

      return isMatchRole && (fullName.contains(q) || phone.contains(q));
    }).toList();

    return RefreshIndicator(
      onRefresh: fetchUsers,
      color: cDark,
      child: list.isEmpty
          ? ListView(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: const Center(
                    child: Text(
                      "ไม่พบข้อมูล",
                      style: TextStyle(
                        color: cDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: list.length,
              itemBuilder: (context, index) => _buildCard(list[index]),
            ),
    );
  }

  Widget _buildCard(Map u) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlatformUserDetailPage(userData: u),
            ),
          );
          if (result == true) fetchUsers();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: cDark.withOpacity(0.10),
                child: Icon(
                  u['platform_role'] == 'platform_admin'
                      ? Icons.stars_rounded
                      : Icons.admin_panel_settings_rounded,
                  color: cDark,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u['full_name'] ?? "-",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cTextMain,
                        fontSize: fHeader,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "โทร : ${u['phone'] ?? '-'}",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: fSubCard,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: cAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cAccent.withOpacity(0.6),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cDark, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: fHeader,
                  fontWeight: FontWeight.w900,
                  color: cTextMain,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        fontSize: fDetail,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: Icon(icon, color: cDark, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: cAccent.withOpacity(0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: cDark, width: 2),
      ),
    );
  }
}

// =========================================================
// 👤 2. หน้าแสดงรายละเอียดโปรไฟล์ (PlatformUserDetailPage)
// =========================================================
class PlatformUserDetailPage extends StatelessWidget {
  final Map userData;
  const PlatformUserDetailPage({super.key, required this.userData});

  static const Color cBg = Color(0xFFF5F0E6);
  static const Color cTextMain = Color(0xFF4E342E);
  static const Color cDark = Color(0xFF5D4037);
  static const Color cAccent = Color(0xFFE0D7C6);

  static const double fHeader = 15.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;
  static const double fCaption = 11.0;

  Future<void> _deleteUser(BuildContext context) async {
    try {
      final res = await http.post(
        Uri.parse("${AppConfig.baseUrl}/dashboard_api.php"),
        body: {
          "action": "deleteUser",
          "user_id": userData['user_id'].toString(),
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        if (!context.mounted) return;
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Delete Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = userData['platform_role'] == 'platform_admin';

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 50,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: cTextMain,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isAdmin ? "ข้อมูลผู้ดูแลระบบ" : "ข้อมูลผู้ดูแลหอพัก",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: cTextMain,
            fontSize: fHeader,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 25),
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: cAccent,
                    child: const Icon(
                      Icons.person_rounded,
                      size: 65,
                      color: cDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    userData['full_name'] ?? "-",
                    style: const TextStyle(
                      fontSize: fHeader,
                      fontWeight: FontWeight.w900,
                      color: cTextMain,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFC8E6C9)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.assignment_ind_rounded,
                          size: 14,
                          color: Color(0xFF2E7D32),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isAdmin ? "ผู้ดูแลระบบ" : "ผู้ดูแลหอพัก",
                          style: const TextStyle(
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.bold,
                            fontSize: fCaption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            _buildSectionHeader("ข้อมูลส่วนตัว"),
            _buildInfoCard(
              Icons.account_circle_outlined,
              "username",
              userData['username'] ?? "-",
            ),
            _buildInfoCard(
              Icons.person_outline_rounded,
              "ชื่อ - นามสกุล",
              userData['full_name'] ?? "-",
            ),
            _buildInfoCard(
              Icons.phone_android_rounded,
              "เบอร์โทรศัพท์",
              userData['phone'] ?? "-",
            ),
            const SizedBox(height: 15),
            _buildSectionHeader(isAdmin ? "รายละเอียดหน้าที่" : "สิทธิ์การเข้าถึง"),
            _buildInfoCard(
              Icons.business_rounded,
              "ชื่อหอพัก",
              userData['dorm_name'] ?? "ระบบส่วนกลาง",
            ),
            _buildInfoCard(
              Icons.shield_outlined,
              "ระดับสิทธิ์",
              isAdmin ? "ผู้ดูแลระบบ" : "ผู้ดูแลหอพัก",
            ),
            const SizedBox(height: 35),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmDelete(context),
                  label: const Text(
                    "ลบออกจากระบบ",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: fHeader,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5252),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: fBody,
            fontWeight: FontWeight.w900,
            color: Color(0xFF6D4C41),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8D6E63), size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: fCaption,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: fBody,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF4E342E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          "ยืนยันการลบ",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: fHeader,
          ),
        ),
        content: const Text(
          "คุณต้องการลบผู้ใช้งานรายนี้ใช่หรือไม่?",
          style: TextStyle(
            fontSize: fBody,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "ยกเลิก",
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: fDetail,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteUser(context);
            },
            child: const Text(
              "ยืนยันลบ",
              style: TextStyle(
                color: Color(0xFFFF5252),
                fontWeight: FontWeight.bold,
                fontSize: fDetail,
              ),
            ),
          ),
        ],
      ),
    );
  }
}