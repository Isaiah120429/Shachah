import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_screen.dart';
import 'profile_screen.dart';
import 'band_library_screen.dart';
import 'notification_service.dart';   // ✅ Import notification service

// Professional Black/White/Smoke Palette
const Color primaryBlack = Color(0xFF000000);
const Color primaryWhite = Color(0xFFFFFFFF);
const Color smokeGrey = Color(0xFFF5F5F5);
const Color darkSmoke = Color(0xFF2C2C2C);
const Color mediumGrey = Color(0xFF757575);
const Color lightGrey = Color(0xFFBDBDBD);
const Color almostBlack = Color(0xFF1E1E1E);

// Functional highlights – toned to fit the monochrome theme
const Color highlightSuccess = Color(0xFF4CAF50);
const Color highlightWarning = Color(0xFFFFA726);
const Color highlightError = Color(0xFFEF5350);
const Color highlightInfo = Color(0xFF78909C);

// Music Positions for the month
const List<String> musicPositions = [
  'Guitar 1 🎸',
  'Guitar 2 🎸',
  'Bass 🎸',
  'Rhythm 🎸',
  'Drums 🥁',
  'Keyboard 🎹',
];

class AssignedMusician {
  final String musicianId;
  final String musicianName;
  final String instrument;
  final bool confirmed;
  AssignedMusician({
    required this.musicianId,
    required this.musicianName,
    required this.instrument,
    this.confirmed = false,
  });
  factory AssignedMusician.fromMap(Map<String, dynamic> map) {
    return AssignedMusician(
      musicianId: map['musicianId'] ?? '',
      musicianName: map['musicianName'] ?? '',
      instrument: map['instrument'] ?? '',
      confirmed: map['confirmed'] ?? false,
    );
  }
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // Month navigation
  late DateTime currentDate;
  late String currentMonth;
  late int currentYear;
  late List<Map<String, dynamic>> availableDates;
  late List<ScheduleAssignmentForAdmin> assignments;
  late List<MemberForAdmin> members;
  bool _isLoading = true;
  
  Map<String, Map<String, dynamic>> notepadCache = {};
  List<Announcement> announcements = [];

  // Announcement selection state
  bool _isSelectionMode = false;
  final Set<String> _selectedAnnouncementIds = {};

  // Unread announcements tracking
  DateTime? _lastSeenTime;
  int _unreadCount = 0;
  bool _isMusicianListExpanded = false;

  // Stream subscriptions
  late StreamSubscription<QuerySnapshot> _assignmentsSubscription;
  late StreamSubscription<QuerySnapshot> _announcementsSubscription;

  @override
  void initState() {
    super.initState();
    _loadData().then((_) {
      _loadLastSeenTime();
      _listenToAssignmentsRealTime();
      _listenToAnnouncementsRealTime();
    });
  }

  @override
  void dispose() {
    _assignmentsSubscription.cancel();
    _announcementsSubscription.cancel();
    super.dispose();
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    await _loadData();
    setState(() => _isLoading = false);
  }

  Future<String> _getCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Unknown';
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data()?['name'] != null && doc.data()!['name'].isNotEmpty) {
        return doc.data()!['name'];
      }
      return user.email?.split('@').first ?? 'User';
    } catch (e) {
      return user.email?.split('@').first ?? 'User';
    }
  }

  Future<void> _loadLastSeenTime() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('adminLastSeenAnnouncement');
    if (saved != null) _lastSeenTime = DateTime.parse(saved);
  }

  Future<void> _saveCurrentViewTime() async {
    _lastSeenTime = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adminLastSeenAnnouncement', _lastSeenTime!.toIso8601String());
    _updateUnreadCount();
  }

  void _updateUnreadCount() {
    if (_lastSeenTime == null) {
      _unreadCount = announcements.length;
    } else {
      _unreadCount = announcements.where((a) => a.createdAt.isAfter(_lastSeenTime!)).length;
    }
    setState(() {});
  }

  void _listenToAssignmentsRealTime() {
    _assignmentsSubscription = FirebaseFirestore.instance
        .collection('assignments')
        .snapshots()
        .listen((snapshot) {
      List<ScheduleAssignmentForAdmin> updatedAssignments = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        String status = data['status'] ?? 'empty';
        Timestamp? sendDate = data['sendDate'] as Timestamp?;
        if (status == 'proposed' && sendDate != null) {
          final daysSinceSend = DateTime.now().difference(sendDate.toDate()).inDays;
          if (daysSinceSend >= 5) {
            FirebaseFirestore.instance.collection('assignments').doc(doc.id).update({'status': 'sealed'});
            status = 'sealed';
          }
        }
        updatedAssignments.add(ScheduleAssignmentForAdmin(
          dateKey: doc.id,
          date: data['date'] ?? '',
          time: data['time'] ?? '9:00 AM',
          assignedMemberId: data['assignedMemberId'] ?? '',
          assignedMemberName: data['assignedMemberName'] ?? 'Not Assigned',
          assignedMemberEmail: data['assignedMemberEmail'] ?? '',
          status: status,
          sendDate: sendDate,
        ));
        notepadCache[doc.id] = {
          'notepadContent': data['notepadContent'] ?? '',
          'notes': data['notes'] ?? '',
          'hasLineUp': data['hasLineUp'] ?? false,
        };
      }
      for (var date in availableDates) {
        if (!updatedAssignments.any((a) => a.dateKey == date['dateKey'])) {
          updatedAssignments.add(ScheduleAssignmentForAdmin(
            dateKey: date['dateKey'],
            date: date['date'],
            time: '9:00 AM',
            assignedMemberId: '',
            assignedMemberName: 'Not Assigned',
            assignedMemberEmail: '',
            status: 'empty',
            sendDate: null,
          ));
        }
      }
      setState(() => assignments = updatedAssignments);
    });
  }

  void _listenToAnnouncementsRealTime() {
    _announcementsSubscription = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      List<Announcement> updated = snapshot.docs.map((doc) {
        final data = doc.data();
        return Announcement(
          id: doc.id,
          title: data['title'] ?? '',
          content: data['content'] ?? '',
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(), // ✅ safe null handling
          createdBy: data['createdBy'] ?? '',
        );
      }).toList();
      final newOnes = updated.where((a) => !announcements.any((old) => old.id == a.id)).toList();
      setState(() {
        announcements = updated;
        _updateUnreadCount();
        if (_isSelectionMode) _exitSelectionMode();
      });
      if (mounted && newOnes.isNotEmpty && _selectedIndex != 3) {
        _showNewAnnouncementPopup(newOnes.first);
      }
    });
  }

  void _showNewAnnouncementPopup(Announcement announcement) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: almostBlack,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.notifications_active, color: highlightSuccess, size: 32),
              ),
              const SizedBox(height: 16),
              const Text('New Announcement', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(announcement.title, style: TextStyle(color: lightGrey, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: primaryBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  announcement.content.length > 100 ? '${announcement.content.substring(0, 100)}...' : announcement.content,
                  style: TextStyle(color: primaryWhite.withOpacity(0.7), fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: mediumGrey)),
                      child: const Text('Later'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedIndex = 3;
                          _saveCurrentViewTime();
                        });
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                      child: const Text('View Now'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
      _selectedAnnouncementIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedAnnouncementIds.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedAnnouncementIds.length == announcements.length) {
        _selectedAnnouncementIds.clear();
      } else {
        _selectedAnnouncementIds.addAll(announcements.map((a) => a.id));
      }
    });
  }

  Future<void> _deleteSelectedAnnouncements() async {
    if (_selectedAnnouncementIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: almostBlack,
        title: const Text('Delete Announcements', style: TextStyle(color: primaryWhite)),
        content: Text('Delete ${_selectedAnnouncementIds.length} announcement(s)?', style: TextStyle(color: lightGrey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: mediumGrey))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: highlightError), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: lightGrey)));
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (String id in _selectedAnnouncementIds) {
        batch.delete(FirebaseFirestore.instance.collection('announcements').doc(id));
      }
      await batch.commit();
      _exitSelectionMode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${_selectedAnnouncementIds.length} announcement(s)'), backgroundColor: highlightSuccess));
      }
      // ✅ Send push notification about bulk deletion
      await NotificationService.sendToAllUsers(
        title: "📢 Announcements Deleted",
        message: "Admin deleted ${_selectedAnnouncementIds.length} announcement(s).",
        data: {'type': 'announcement'},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: highlightError));
      }
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _createAssignmentAnnouncement(String memberName, String date) async {
    final realName = await _getCurrentUserName();
    await FirebaseFirestore.instance.collection('announcements').add({
      'title': '🎵 New Worship Leader Assignment',
      'content': '$memberName has been assigned as Worship Leader on $date.',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': realName,
    });
  }

  Future<void> _createRemovalAnnouncement(String memberName, String date) async {
    final realName = await _getCurrentUserName();
    await FirebaseFirestore.instance.collection('announcements').add({
      'title': '⚠️ Schedule Update',
      'content': '$memberName has been removed as Worship Leader on $date.',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': realName,
    });
  }

  Future<void> _saveAnnouncement(String title, String content) async {
    final realName = await _getCurrentUserName();
    final docRef = await FirebaseFirestore.instance.collection('announcements').add({
      'title': title,
      'content': content,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': realName,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement posted!'), backgroundColor: highlightSuccess),
      );
    }
    // ✅ Send push notification to all users
    await NotificationService.sendToAllUsers(
      title: "📢 New Announcement: $title",
      message: "$realName posted: ${content.length > 100 ? content.substring(0, 100) : content}",
      data: {'type': 'announcement', 'id': docRef.id},
    );
  }

  Future<void> _deleteAnnouncement(String id) async {
    await FirebaseFirestore.instance.collection('announcements').doc(id).delete();
    // ✅ Send push notification
    await NotificationService.sendToAllUsers(
      title: "🗑️ Announcement Deleted",
      message: "An announcement was removed by an admin.",
      data: {'type': 'announcement'},
    );
  }

  void _showAddAnnouncementDialog() {
    TextEditingController titleCtrl = TextEditingController();
    TextEditingController contentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: almostBlack,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [Icon(Icons.announcement, color: lightGrey, size: 24), SizedBox(width: 10), Text('Add Announcement', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 16),
              TextField(controller: titleCtrl, style: const TextStyle(color: primaryWhite), decoration: InputDecoration(labelText: 'Title', labelStyle: TextStyle(color: lightGrey), filled: true, fillColor: primaryBlack.withOpacity(0.5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
              const SizedBox(height: 12),
              TextField(controller: contentCtrl, maxLines: 8, style: const TextStyle(color: primaryWhite), decoration: InputDecoration(labelText: 'Content', labelStyle: TextStyle(color: lightGrey), filled: true, fillColor: primaryBlack.withOpacity(0.5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(foregroundColor: mediumGrey, side: BorderSide(color: mediumGrey)), child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(onPressed: () async { if (titleCtrl.text.trim().isNotEmpty && contentCtrl.text.trim().isNotEmpty) { await _saveAnnouncement(titleCtrl.text.trim(), contentCtrl.text.trim()); Navigator.pop(context); } }, style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess), child: const Text('Post'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditAnnouncementDialog(Announcement announcement) {
    TextEditingController titleCtrl = TextEditingController(text: announcement.title);
    TextEditingController contentCtrl = TextEditingController(text: announcement.content);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: almostBlack,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [Icon(Icons.edit_note, color: lightGrey, size: 24), SizedBox(width: 10), Text('Edit Announcement', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 16),
              TextField(controller: titleCtrl, style: const TextStyle(color: primaryWhite), decoration: InputDecoration(labelText: 'Title', labelStyle: TextStyle(color: lightGrey), filled: true, fillColor: primaryBlack.withOpacity(0.5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
              const SizedBox(height: 12),
              TextField(controller: contentCtrl, maxLines: 8, style: const TextStyle(color: primaryWhite), decoration: InputDecoration(labelText: 'Content', labelStyle: TextStyle(color: lightGrey), filled: true, fillColor: primaryBlack.withOpacity(0.5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(foregroundColor: mediumGrey, side: BorderSide(color: mediumGrey)), child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(onPressed: () async {
                    await FirebaseFirestore.instance.collection('announcements').doc(announcement.id).update({
                      'title': titleCtrl.text.trim(),
                      'content': contentCtrl.text.trim(),
                    });
                    // ✅ Send push notification about update
                    await NotificationService.sendToAllUsers(
                      title: "✏️ Announcement Updated",
                      message: "${await _getCurrentUserName()} updated: ${titleCtrl.text}",
                      data: {'type': 'announcement', 'id': announcement.id},
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Announcement updated!'), backgroundColor: highlightSuccess));
                  }, style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess), child: const Text('Update'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmationDialog(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: almostBlack,
        title: const Text('Delete Announcement', style: TextStyle(color: primaryWhite)),
        content: Text('Delete this announcement?', style: TextStyle(color: lightGrey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: mediumGrey))),
          ElevatedButton(onPressed: () async { await _deleteAnnouncement(id); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Announcement deleted!'), backgroundColor: highlightError)); }, style: ElevatedButton.styleFrom(backgroundColor: highlightError), child: const Text('Delete')),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    currentDate = DateTime.now();
    currentMonth = DateFormat('MMMM').format(currentDate);
    currentYear = currentDate.year;
    availableDates = _getAllSundays(currentYear, currentDate.month);
    await _loadMembersFromFirebase();
    setState(() => _isLoading = false);
  }

  Future<void> _loadMembersFromFirebase() async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('users').get();
      members = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return MemberForAdmin(id: doc.id, name: data['name'] ?? 'Unknown', email: data['email'] ?? '', isAdmin: data['isAdmin'] ?? false);
      }).toList();
    } catch (e) {
      members = [];
    }
  }

  List<Map<String, dynamic>> _getAllSundays(int year, int month) {
    List<Map<String, dynamic>> sundays = [];
    DateTime firstDay = DateTime(year, month, 1);
    int daysToAdd = (DateTime.sunday - firstDay.weekday) % 7;
    DateTime firstSunday = firstDay.add(Duration(days: daysToAdd));
    DateTime current = firstSunday;
    while (current.month == month) {
      sundays.add({
        'date': DateFormat('MMMM d, yyyy').format(current),
        'dateKey': DateFormat('yyyy-MM-dd').format(current),
        'time': '9:00 AM',
        'dayOfMonth': current.day,
      });
      current = current.add(const Duration(days: 7));
    }
    return sundays;
  }

  void _previousMonth() {
    setState(() => _isLoading = true);
    DateTime prev = DateTime(currentYear, currentDate.month - 1);
    currentYear = prev.year;
    currentDate = prev;
    currentMonth = DateFormat('MMMM').format(prev);
    availableDates = _getAllSundays(currentYear, prev.month);
    setState(() => _isLoading = false);
  }

  void _nextMonth() {
    setState(() => _isLoading = true);
    DateTime next = DateTime(currentYear, currentDate.month + 1);
    currentYear = next.year;
    currentDate = next;
    currentMonth = DateFormat('MMMM').format(next);
    availableDates = _getAllSundays(currentYear, next.month);
    setState(() => _isLoading = false);
  }

  String getAssignedMemberName(String dateKey) {
    if (assignments.isEmpty) return 'Not Assigned';
    try {
      final assignment = assignments.firstWhere((a) => a.dateKey == dateKey, orElse: () => ScheduleAssignmentForAdmin(dateKey: '', date: '', time: '', assignedMemberId: '', assignedMemberName: 'Not Assigned', assignedMemberEmail: '', status: 'empty', sendDate: null));
      return assignment.assignedMemberName;
    } catch (e) {
      return 'Not Assigned';
    }
  }

  String getAssignedMemberId(String dateKey) {
    if (assignments.isEmpty) return '';
    try {
      final assignment = assignments.firstWhere((a) => a.dateKey == dateKey, orElse: () => ScheduleAssignmentForAdmin(dateKey: '', date: '', time: '', assignedMemberId: '', assignedMemberName: '', assignedMemberEmail: '', status: 'empty', sendDate: null));
      return assignment.assignedMemberId;
    } catch (e) {
      return '';
    }
  }

 Future<void> _assignMember(String dateKey, String date, String time, String memberId, String memberName, String memberEmail) async {
  await FirebaseFirestore.instance.collection('assignments').doc(dateKey).set({
    'date': date,
    'time': time,
    'assignedMemberId': memberId,
    'assignedMemberName': memberName,
    'assignedMemberEmail': memberEmail,
    'hasLineUp': notepadCache[dateKey]?['hasLineUp'] ?? false,
    'notepadContent': notepadCache[dateKey]?['notepadContent'] ?? '',
    'notes': notepadCache[dateKey]?['notes'] ?? '',
    'updatedAt': FieldValue.serverTimestamp(),
  });
  await _createAssignmentAnnouncement(memberName, date);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ $memberName assigned as Worship Leader on $date'), backgroundColor: highlightSuccess));

  // ✅ Send push notification to the assigned member
  await NotificationService.sendToUser(
    userId: memberId,
    title: "🎤 Worship Leader Assignment",
    message: "You have been assigned as Worship Leader for $date at $time.",
    data: {'type': 'assignment', 'dateKey': dateKey},
  );

  // ✅ NEW: Send push notification to ALL users
  await NotificationService.sendToAllUsers(
    title: "📢 New Worship Leader Assignment",
    message: "$memberName has been assigned as Worship Leader on $date.",
    data: {'type': 'assignment_broadcast', 'dateKey': dateKey},
  );
}

Future<void> _unassignMember(String dateKey) async {
  final assignment = assignments.firstWhere((a) => a.dateKey == dateKey);
  final date = assignment.date;
  final removedName = assignment.assignedMemberName;
  final removedId = assignment.assignedMemberId;
  await FirebaseFirestore.instance.collection('assignments').doc(dateKey).set({
    'date': date,
    'time': assignment.time,
    'assignedMemberId': '',
    'assignedMemberName': 'Not Assigned',
    'assignedMemberEmail': '',
    'hasLineUp': false,
    'notepadContent': '',
    'notes': '',
    'updatedAt': FieldValue.serverTimestamp(),
  });
  notepadCache[dateKey] = {'notepadContent': '', 'notes': '', 'hasLineUp': false};
  if (assignment.assignedMemberId.isNotEmpty) {
    await _createRemovalAnnouncement(removedName, date);
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $removedName removed from $date. Lineup cleared.'), backgroundColor: highlightWarning));

  // ✅ Send push notification to the removed member (if any)
  if (removedId.isNotEmpty) {
    await NotificationService.sendToUser(
      userId: removedId,
      title: "⚠️ Assignment Removed",
      message: "You are no longer the Worship Leader for $date.",
      data: {'type': 'assignment', 'dateKey': dateKey},
    );
  }

  // ✅ NEW: Send push notification to ALL users
  await NotificationService.sendToAllUsers(
    title: "📢 Worship Leader Assignment Removed",
    message: "$removedName has been removed as Worship Leader on $date.",
    data: {'type': 'assignment_removed_broadcast', 'dateKey': dateKey},
  );
}

  void _showAssignDialog(String dateKey, String date, String time, String currentAssigneeId, String currentAssigneeName) {
  String? selectedMemberId = currentAssigneeId.isNotEmpty ? currentAssigneeId : null;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [primaryBlack, almostBlack, darkSmoke]),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: mediumGrey, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: darkSmoke.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                        child: Text(DateFormat('d').format(DateTime.parse(dateKey)), style: TextStyle(color: lightGrey, fontSize: 20, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 16),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(date, style: const TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)), Text(time, style: TextStyle(color: lightGrey, fontSize: 14))])),
                      if (currentAssigneeId.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(20)), child: Text('Assigned', style: TextStyle(color: highlightSuccess, fontSize: 12))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),
                if (currentAssigneeId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: almostBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: mediumGrey)),
                      child: Row(
                        children: [
                          const Icon(Icons.person, color: highlightSuccess),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Currently Assigned', style: TextStyle(color: mediumGrey, fontSize: 11)), Text(currentAssigneeName, style: const TextStyle(color: primaryWhite, fontSize: 16))])),
                          OutlinedButton.icon(onPressed: () { Navigator.pop(context); _unassignMember(dateKey); }, icon: const Icon(Icons.clear, size: 16), label: const Text('Remove'), style: OutlinedButton.styleFrom(foregroundColor: highlightError, side: const BorderSide(color: highlightError))),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Select Worship Leader', style: TextStyle(color: lightGrey, fontSize: 14, fontWeight: FontWeight.w600)), Text('${members.length} members', style: TextStyle(color: mediumGrey, fontSize: 11))])),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: members.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people_outline, size: 48, color: lightGrey.withOpacity(0.5)), const SizedBox(height: 12), Text('No registered members yet', style: TextStyle(color: lightGrey)), const SizedBox(height: 8), Text('Ask members to sign up first', style: TextStyle(color: mediumGrey, fontSize: 12))]))
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final member = members[index];
                            final isSelected = selectedMemberId == member.id;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(color: isSelected ? darkSmoke.withOpacity(0.5) : Colors.transparent, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSelected ? lightGrey : mediumGrey, width: 1.5)),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: mediumGrey, child: Text(member.name[0].toUpperCase(), style: const TextStyle(color: primaryWhite))),
                                title: Row(children: [Text(member.name, style: const TextStyle(color: primaryWhite)), if (member.isAdmin) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: lightGrey.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Text('Admin', style: TextStyle(color: lightGrey, fontSize: 8)))]),
                                subtitle: Text(member.email, style: TextStyle(color: mediumGrey, fontSize: 12)),
                                trailing: isSelected ? Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: highlightSuccess, borderRadius: BorderRadius.circular(20)), child: const Text('Selected', style: TextStyle(color: primaryWhite, fontSize: 11))) : ElevatedButton(onPressed: () => setSheetState(() => selectedMemberId = member.id), style: ElevatedButton.styleFrom(backgroundColor: darkSmoke, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: const Text('Assign')),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                if (selectedMemberId != null && selectedMemberId != currentAssigneeId)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(side: BorderSide(color: mediumGrey)), child: const Text('Cancel'))),
                        const SizedBox(width: 12),
                        Expanded(child: ElevatedButton(onPressed: () { final selected = members.firstWhere((m) => m.id == selectedMemberId); _assignMember(dateKey, date, time, selected.id, selected.name, selected.email); Navigator.pop(context); }, style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess), child: const Text('Confirm Assignment'))),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    ),
  );
}

  Widget _buildScheduleContent() {
    final currentMonthKeys = availableDates.map((d) => d['dateKey']).toSet();
    final filteredAssignments = assignments.where((a) => currentMonthKeys.contains(a.dateKey)).toList();
    filteredAssignments.sort((a, b) => a.dateKey.compareTo(b.dateKey));
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: lightGrey,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSimpleHeader(),
            const SizedBox(height: 20),
            _buildMonthNavigator(),
            const SizedBox(height: 16),
            Expanded(
              child: filteredAssignments.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_today, size: 64, color: mediumGrey), const SizedBox(height: 16), Text('No schedules for $currentMonth $currentYear', style: TextStyle(color: mediumGrey, fontSize: 16))]))
                  : ListView.builder(itemCount: filteredAssignments.length, itemBuilder: (context, index) => _buildScheduleCard(filteredAssignments[index])),
            ),
          ],
        ),
      ),
    );
  }

  // ========== SCHEDULE CARD ==========
  Widget _buildScheduleCard(ScheduleAssignmentForAdmin assignment) {
    final isAssigned = assignment.assignedMemberId.isNotEmpty;
    final cacheData = notepadCache[assignment.dateKey];
    final notepadContent = cacheData?['notepadContent'] ?? '';
    final notes = cacheData?['notes'] ?? '';

    String statusText;
    Color statusColor;
    if (assignment.status == 'empty') {
      statusText = 'Empty';
      statusColor = mediumGrey;
    } else if (assignment.status == 'proposed') {
      if (assignment.sendDate != null) {
        final daysLeft = 5 - DateTime.now().difference(assignment.sendDate!.toDate()).inDays;
        statusText = 'Proposed ($daysLeft days left)';
        statusColor = highlightWarning;
      } else {
        statusText = 'Proposed (draft)';
        statusColor = highlightInfo;
      }
    } else {
      statusText = 'Sealed';
      statusColor = highlightSuccess;
    }

    return GestureDetector(
      onTap: () => _showViewOnlyLineupDialog(assignment, notepadContent, notes),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isAssigned ? darkSmoke.withOpacity(0.6) : almostBlack,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isAssigned ? lightGrey : mediumGrey, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(width: 50, height: 50, decoration: BoxDecoration(color: isAssigned ? highlightSuccess.withOpacity(0.15) : darkSmoke, borderRadius: BorderRadius.circular(25)), child: Icon(isAssigned ? Icons.check_circle : Icons.person, color: isAssigned ? highlightSuccess : lightGrey, size: 24)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(assignment.date, style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 12, color: mediumGrey),
                            const SizedBox(width: 4),
                            Text(assignment.time, style: const TextStyle(color: mediumGrey, fontSize: 12)),
                            const SizedBox(width: 16),
                            const Icon(Icons.person, size: 12, color: mediumGrey),
                            const SizedBox(width: 4),
                            Text(isAssigned ? assignment.assignedMemberName : 'Not Assigned', style: TextStyle(color: isAssigned ? highlightSuccess : lightGrey, fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: statusColor.withOpacity(0.5), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(assignment.status == 'empty' ? Icons.hourglass_empty : (assignment.status == 'sealed' ? Icons.lock : Icons.edit), size: 10, color: statusColor),
                              const SizedBox(width: 4),
                              Text(statusText, style: TextStyle(color: statusColor, fontSize: 9)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isAssigned)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: primaryBlack.withOpacity(0.3), borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16))),
                child: Row(
                  children: [
                    Icon(Icons.edit_note, color: lightGrey, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(notepadContent.isEmpty ? 'No lineup added yet. Tap to view.' : 'Tap to view lineup', style: TextStyle(color: notepadContent.isEmpty ? lightGrey : primaryWhite.withOpacity(0.7), fontSize: 12))),
                    Icon(Icons.chevron_right, color: lightGrey, size: 16),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showViewOnlyLineupDialog(ScheduleAssignmentForAdmin assignment, String notepadContent, String notes) async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('assignments').doc(assignment.dateKey).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        notepadContent = data['notepadContent'] ?? '';
        notes = data['notes'] ?? '';
      }
    } catch (e) {}

    String statusText;
    Color statusColor;
    if (assignment.status == 'empty') {
      statusText = 'Empty';
      statusColor = mediumGrey;
    } else if (assignment.status == 'proposed') {
      if (assignment.sendDate != null) {
        final daysLeft = 5 - DateTime.now().difference(assignment.sendDate!.toDate()).inDays;
        statusText = 'Proposed ($daysLeft days left)';
        statusColor = highlightWarning;
      } else {
        statusText = 'Proposed (draft)';
        statusColor = highlightInfo;
      }
    } else {
      statusText = 'Sealed';
      statusColor = highlightSuccess;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [primaryBlack, almostBlack, darkSmoke]),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: mediumGrey, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: darkSmoke.withOpacity(0.5), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.visibility, color: lightGrey)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(assignment.assignedMemberName, style: const TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)), Text(assignment.date, style: TextStyle(color: lightGrey, fontSize: 14)), Text(assignment.time, style: TextStyle(color: mediumGrey, fontSize: 12))])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(assignment.status == 'empty' ? Icons.hourglass_empty : (assignment.status == 'sealed' ? Icons.lock : Icons.edit), size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(statusText, style: TextStyle(color: statusColor, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Song Line Up', style: TextStyle(color: primaryWhite, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: primaryBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: mediumGrey.withOpacity(0.5))),
                      child: notepadContent.isEmpty ? Center(child: Text('No lineup yet.', style: TextStyle(color: lightGrey, fontSize: 12))) : _buildClickableNotepadTextView(context, notepadContent),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Notes', style: TextStyle(color: primaryWhite, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: primaryBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: mediumGrey.withOpacity(0.5))), child: _buildClickableNotepadTextView(context, notes)),
                    ],
                  ],
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(20), child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: mediumGrey, minimumSize: const Size(double.infinity, 48)), child: const Text('Close'))),
          ],
        ),
      ),
    );
  }

  Widget _buildClickableNotepadTextView(BuildContext context, String text) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
        final hasUrl = urlRegex.hasMatch(line);
        if (hasUrl) {
          final parts = line.split(RegExp(r'(https?:\/\/[^\s]+)'));
          final urls = urlRegex.allMatches(line).map((m) => m.group(0)).whereType<String>().toList();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...parts.asMap().entries.map((entry) {
                  final part = entry.value;
                  if (part.isNotEmpty) return Text(part, style: const TextStyle(color: primaryWhite, fontSize: 12, height: 1.4));
                  return const SizedBox.shrink();
                }),
                ...urls.map((urlString) => GestureDetector(
                  onTap: () async {
                    final Uri uri = Uri.parse(urlString);
                    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open link: $urlString'), backgroundColor: highlightError)); }
                  },
                  child: Text(urlString, style: const TextStyle(color: Colors.blue, fontSize: 12, decoration: TextDecoration.underline, height: 1.4)),
                )),
              ],
            ),
          );
        } else if (line.contains('🎵') || line.contains('📝') || line.contains('✅')) {
          return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(line, style: TextStyle(color: lightGrey, fontSize: 12, fontWeight: FontWeight.w500)));
        } else if (line.trim().isEmpty) {
          return const SizedBox(height: 6);
        } else {
          return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(line, style: const TextStyle(color: primaryWhite, fontSize: 12, height: 1.4)));
        }
      }).toList(),
    );
  }

  Widget _buildUpdatesContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveCurrentViewTime());
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: lightGrey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildSimpleHeader(),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Announcements', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      ElevatedButton.icon(onPressed: _showAddAnnouncementDialog, icon: const Icon(Icons.add, size: 18), label: const Text('New'), style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)))),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: lightGrey),
                        onSelected: (value) {
                          if (value == 'select_all') { _enterSelectionMode(); _toggleSelectAll(); }
                          else if (value == 'delete_selected') { if (_selectedAnnouncementIds.isNotEmpty) {
                            _deleteSelectedAnnouncements();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No announcements selected'), backgroundColor: highlightWarning));
                          } }
                        },
                        itemBuilder: (context) => const [PopupMenuItem(value: 'select_all', child: Text('Select All')), PopupMenuItem(value: 'delete_selected', child: Text('Delete Selected', style: TextStyle(color: highlightError)))],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: announcements.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.announcement, size: 64, color: lightGrey.withOpacity(0.5)), const SizedBox(height: 16), Text('No announcements yet', style: TextStyle(color: lightGrey, fontSize: 16)), const SizedBox(height: 8), Text('Tap + to create an announcement', style: TextStyle(color: mediumGrey, fontSize: 12))]))
                    : ListView.builder(
                        itemCount: announcements.length,
                        itemBuilder: (context, index) {
                          final a = announcements[index];
                          final isSelected = _selectedAnnouncementIds.contains(a.id);
                          final isNew = _lastSeenTime == null || a.createdAt.isAfter(_lastSeenTime!);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(color: isSelected ? darkSmoke.withOpacity(0.5) : almostBlack, borderRadius: BorderRadius.circular(16), border: Border.all(color: isSelected ? lightGrey : mediumGrey, width: isSelected ? 2 : 1)),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: darkSmoke.withOpacity(0.5), borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
                                  child: Row(
                                    children: [
                                      if (_isSelectionMode) Checkbox(value: isSelected, onChanged: (checked) { setState(() { if (checked == true) {
                                        _selectedAnnouncementIds.add(a.id);
                                      } else {
                                        _selectedAnnouncementIds.remove(a.id);
                                      } }); }, activeColor: highlightSuccess, checkColor: primaryWhite),
                                      const Icon(Icons.announcement, color: lightGrey, size: 20),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [Expanded(child: Text(a.title, style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.bold))), if (isNew) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: Text('NEW', style: TextStyle(color: highlightSuccess, fontSize: 9, fontWeight: FontWeight.bold)))]),
                                            Text('Posted by ${a.createdBy} • ${DateFormat('MMM d, yyyy').format(a.createdAt)}', style: TextStyle(color: lightGrey.withOpacity(0.7), fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                      if (!_isSelectionMode) PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert, color: lightGrey),
                                        onSelected: (value) { if (value == 'edit') {
                                          _showEditAnnouncementDialog(a);
                                        } else if (value == 'delete') _showDeleteConfirmationDialog(a.id); },
                                        itemBuilder: (context) => const [PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])), PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: highlightError), SizedBox(width: 8), Text('Delete', style: TextStyle(color: highlightError))]))],
                                      ),
                                    ],
                                  ),
                                ),
                                if (!_isSelectionMode)
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(color: primaryBlack.withOpacity(0.3), borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16))),
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_note, color: lightGrey, size: 16),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(a.content, style: TextStyle(color: primaryWhite.withOpacity(0.7), fontSize: 13, height: 1.4))),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        floatingActionButton: _isSelectionMode && _selectedAnnouncementIds.isNotEmpty
            ? FloatingActionButton.extended(onPressed: _deleteSelectedAnnouncements, backgroundColor: highlightError, icon: const Icon(Icons.delete), label: Text('Delete (${_selectedAnnouncementIds.length})'))
            : null,
      ),
    );
  }

  Widget _buildBandLibraryContent() => const BandLibraryScreen();

  Widget _buildDrawer() {
    String initials = UserSession.userName?.isNotEmpty == true ? UserSession.userName![0].toUpperCase() : 'A';
    return Drawer(
      backgroundColor: almostBlack,
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryBlack, almostBlack, darkSmoke])),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 24),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: mediumGrey.withOpacity(0.5)))),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [mediumGrey, lightGrey]),
                      border: Border.all(color: lightGrey, width: 2),
                    ),
                    child: Center(child: Text(initials, style: const TextStyle(color: primaryWhite, fontSize: 24, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(UserSession.userName ?? 'Admin', style: const TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: darkSmoke, borderRadius: BorderRadius.circular(12)),
                          child: const Text('Administrator', style: TextStyle(color: lightGrey, fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildDrawerItem(icon: Icons.dashboard, title: 'Assign WL', index: 0, isSelected: _selectedIndex == 0),
            _buildDrawerItem(icon: Icons.people, title: 'Members', index: 1, isSelected: _selectedIndex == 1),
            _buildDrawerItem(icon: Icons.calendar_month, title: 'Schedule', index: 2, isSelected: _selectedIndex == 2),
            _buildDrawerItem(icon: Icons.announcement, title: 'Updates', index: 3, isSelected: _selectedIndex == 3, badge: _unreadCount > 0 ? '$_unreadCount' : null),
            _buildDrawerItem(icon: Icons.library_music, title: 'Band Library', index: 4, isSelected: _selectedIndex == 4),
            _buildDrawerItem(icon: Icons.settings, title: 'Settings', index: 5, isSelected: _selectedIndex == 5),
            const Spacer(),
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: highlightError.withOpacity(0.5))),
              child: ListTile(
                leading: Icon(Icons.logout, color: highlightError),
                title: Text('Sign Out', style: TextStyle(color: highlightError, fontWeight: FontWeight.w600)),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  UserSession.isLoggedIn = false;
                  UserSession.userId = null;
                  UserSession.userName = null;
                  UserSession.userEmail = null;
                  UserSession.userRole = null;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('userId');
                  await prefs.remove('userRole');
                  await prefs.remove('userName');
                  await prefs.remove('userEmail');
                  await prefs.remove('adminLastSeenAnnouncement');
                  if (mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const AuthScreen()),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({required IconData icon, required String title, required int index, required bool isSelected, String? badge}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: isSelected ? darkSmoke : Colors.transparent, border: isSelected ? Border.all(color: lightGrey.withOpacity(0.5)) : null),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? lightGrey : mediumGrey),
        title: Text(title, style: TextStyle(color: isSelected ? primaryWhite : mediumGrey, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
        trailing: badge != null ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: highlightError, borderRadius: BorderRadius.circular(20)), child: Text(badge, style: const TextStyle(color: primaryWhite, fontSize: 11, fontWeight: FontWeight.bold))) : null,
        onTap: () { setState(() => _selectedIndex = index); if (_isSelectionMode) _exitSelectionMode(); Navigator.pop(context); },
      ),
    );
  }

  Widget _buildAssignContent() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: lightGrey,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildSimpleHeader(),
              const SizedBox(height: 20),
              _buildMonthlyMusiciansList(),
              const SizedBox(height: 20),
              _buildMonthNavigator(),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Sunday Services', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)), Text('Tap card to assign WL', style: TextStyle(color: lightGrey, fontSize: 11))]),
              const SizedBox(height: 12),
              Expanded(
                child: availableDates.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_today, size: 64, color: mediumGrey), const SizedBox(height: 16), const Text('No Sundays in this month', style: TextStyle(color: mediumGrey))]))
                    : ListView.builder(itemCount: availableDates.length, itemBuilder: (context, index) { final date = availableDates[index]; return _buildAssignmentCard(date['date'], date['dateKey'], date['time'], date['dayOfMonth']); }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthlyMusiciansList() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('monthly_music_assignments').doc(DateFormat('yyyy-MM').format(currentDate)).snapshots(),
      builder: (context, snapshot) {
        Map<String, AssignedMusician>? musicians;
        int assignedCount = 0;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final musiciansMap = data['musicians'] as Map<String, dynamic>? ?? {};
          musicians = {};
          for (var entry in musiciansMap.entries) { musicians[entry.key] = AssignedMusician.fromMap(entry.value as Map<String, dynamic>); }
          assignedCount = musicians.values.where((m) => m.musicianId.isNotEmpty).length;
        }
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: darkSmoke.withOpacity(0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: mediumGrey.withOpacity(0.5), width: 1)),
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() => _isMusicianListExpanded = !_isMusicianListExpanded),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [Icon(_isMusicianListExpanded ? Icons.expand_less : Icons.expand_more, color: lightGrey, size: 20), const SizedBox(width: 8), Icon(Icons.music_note, color: lightGrey, size: 16), const SizedBox(width: 6), const Text('Musicians of this Month', style: TextStyle(color: primaryWhite, fontSize: 14, fontWeight: FontWeight.w500))]),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: assignedCount > 0 ? highlightSuccess.withOpacity(0.2) : highlightWarning.withOpacity(0.2), borderRadius: BorderRadius.circular(20)), child: Text('$assignedCount/${musicPositions.length} assigned', style: TextStyle(color: assignedCount > 0 ? highlightSuccess : highlightWarning, fontSize: 10))),
                    ],
                  ),
                ),
              ),
              if (_isMusicianListExpanded) ...[
                const SizedBox(height: 10),
                ...musicPositions.map((position) {
                  String assignedName = 'Not Assigned';
                  Color textColor = mediumGrey;
                  if (musicians != null && musicians.containsKey(position)) {
                    final musician = musicians[position]!;
                    if (musician.musicianId.isNotEmpty) { assignedName = musician.musicianName; textColor = highlightSuccess; }
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: primaryBlack.withOpacity(0.4), borderRadius: BorderRadius.circular(12), border: Border.all(color: mediumGrey.withOpacity(0.3))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: Text(position, style: TextStyle(color: lightGrey, fontSize: 13), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 12),
                          Flexible(child: Text(assignedName, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500), textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSimpleHeader() {
    String initials = UserSession.userName?.isNotEmpty == true ? UserSession.userName![0].toUpperCase() : 'A';
    return Row(
      children: [
        Container(width: 45, height: 45, decoration: BoxDecoration(gradient: LinearGradient(colors: [mediumGrey, lightGrey]), borderRadius: BorderRadius.circular(22.5)), child: Center(child: Text(initials, style: const TextStyle(color: primaryBlack, fontWeight: FontWeight.bold, fontSize: 18)))),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(UserSession.userName ?? 'Admin', style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.w600)), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: darkSmoke, borderRadius: BorderRadius.circular(12)), child: const Text('Admin', style: TextStyle(color: lightGrey, fontSize: 10)))]),
      ],
    );
  }

  Widget _buildMembersContent() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: lightGrey,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildSimpleHeader(),
              const SizedBox(height: 20),
              Expanded(
                child: members.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people_outline, size: 64, color: lightGrey), const SizedBox(height: 16), Text('No members yet', style: TextStyle(color: lightGrey, fontSize: 16)), const SizedBox(height: 8), Text('Members will appear here after signing up', style: TextStyle(color: mediumGrey, fontSize: 12))]))
                    : ListView.builder(
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final member = members[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: almostBlack, borderRadius: BorderRadius.circular(16), border: Border.all(color: mediumGrey, width: 1.5)),
                            child: Row(
                              children: [
                                CircleAvatar(backgroundColor: mediumGrey, radius: 25, child: Text(member.name[0].toUpperCase(), style: const TextStyle(color: primaryWhite, fontSize: 18))),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [Text(member.name, style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.w600)), if (member.isAdmin) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: lightGrey.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Text('Admin', style: TextStyle(color: lightGrey, fontSize: 10)))]),
                                      Text(member.email, style: const TextStyle(color: mediumGrey, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsContent() => const ProfileScreen();

  Widget _buildMonthNavigator() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: darkSmoke.withOpacity(0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: mediumGrey, width: 1.5)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: Icon(Icons.chevron_left, color: lightGrey), onPressed: _previousMonth, constraints: const BoxConstraints()),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(currentMonth, style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.bold)), Text(currentYear.toString(), style: const TextStyle(color: mediumGrey, fontSize: 12))]),
          IconButton(icon: Icon(Icons.chevron_right, color: lightGrey), onPressed: _nextMonth, constraints: const BoxConstraints()),
        ],
      ),
    );
  }

  Widget _buildAssignmentCard(String date, String dateKey, String time, int dayOfMonth) {
    String currentAssigneeId = '';
    String currentAssigneeName = 'Not Assigned';
    bool isAssigned = false;
    try {
      if (assignments.isNotEmpty) {
        currentAssigneeId = getAssignedMemberId(dateKey);
        currentAssigneeName = getAssignedMemberName(dateKey);
        isAssigned = currentAssigneeId.isNotEmpty;
      }
    } catch (e) {}
    DateTime sundayDate = DateTime.parse(dateKey);
    bool isToday = sundayDate.year == DateTime.now().year && sundayDate.month == DateTime.now().month && sundayDate.day == DateTime.now().day;
    bool isPast = sundayDate.isBefore(DateTime.now()) && !isToday;
    return GestureDetector(
      onTap: () => _showAssignDialog(dateKey, date, time, currentAssigneeId, currentAssigneeName),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isToday ? darkSmoke.withOpacity(0.6) : almostBlack, borderRadius: BorderRadius.circular(16), border: Border.all(color: isToday ? lightGrey : mediumGrey, width: 1.5)),
        child: Row(
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: isAssigned ? highlightSuccess.withOpacity(0.15) : darkSmoke, borderRadius: BorderRadius.circular(25)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(dayOfMonth.toString(), style: TextStyle(color: isAssigned ? highlightSuccess : lightGrey, fontSize: 18, fontWeight: FontWeight.bold)), const Text('SUN', style: TextStyle(color: mediumGrey, fontSize: 8))]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date, style: const TextStyle(color: primaryWhite, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 12, color: mediumGrey),
                      const SizedBox(width: 4),
                      Text(time, style: const TextStyle(color: mediumGrey, fontSize: 11)),
                      const SizedBox(width: 12),
                      const Icon(Icons.person, size: 12, color: mediumGrey),
                      const SizedBox(width: 4),
                      Text(isAssigned ? currentAssigneeName : 'Not Assigned', style: TextStyle(color: isAssigned ? highlightSuccess : lightGrey, fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  if (isToday) Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: darkSmoke, borderRadius: BorderRadius.circular(8)), child: Text('TODAY', style: TextStyle(color: lightGrey, fontSize: 9))),
                  if (isPast && !isAssigned) Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: highlightError.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Text('MISSED', style: TextStyle(color: highlightError, fontSize: 9))),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: lightGrey, size: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [primaryBlack, almostBlack, darkSmoke]),
        ),
        child: const Center(child: CircularProgressIndicator(color: lightGrey)),
      );
    }
    Widget bodyContent;
    switch (_selectedIndex) {
      case 0: bodyContent = _buildAssignContent(); break;
      case 1: bodyContent = _buildMembersContent(); break;
      case 2: bodyContent = _buildScheduleContent(); break;
      case 3: bodyContent = _buildUpdatesContent(); break;
      case 4: bodyContent = _buildBandLibraryContent(); break;
      case 5: bodyContent = _buildSettingsContent(); break;
      default: bodyContent = _buildAssignContent();
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [primaryBlack, almostBlack, darkSmoke]),
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_getAppBarTitle()),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: lightGrey,
          leading: Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu, color: lightGrey), onPressed: () => Scaffold.of(context).openDrawer())),
          actions: _selectedIndex == 3 && _isSelectionMode ? [TextButton(onPressed: _exitSelectionMode, child: const Text('Cancel', style: TextStyle(color: lightGrey)))] : null,
        ),
        drawer: _buildDrawer(),
        body: bodyContent,
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0: return 'Assign Worship Leader';
      case 1: return 'Members List';
      case 2: return 'All Schedules & Lineups';
      case 3: return 'Announcements';
      case 4: return 'Band Library';
      case 5: return 'Settings';
      default: return 'Admin Dashboard';
    }
  }
}

class MemberForAdmin {
  String id, name, email;
  bool isAdmin;
  MemberForAdmin({required this.id, required this.name, required this.email, this.isAdmin = false});
}

class ScheduleAssignmentForAdmin {
  String dateKey, date, time, assignedMemberId, assignedMemberName, assignedMemberEmail;
  String status;
  Timestamp? sendDate;
  ScheduleAssignmentForAdmin({
    required this.dateKey,
    required this.date,
    required this.time,
    required this.assignedMemberId,
    required this.assignedMemberName,
    required this.assignedMemberEmail,
    required this.status,
    this.sendDate,
  });
}

class Announcement {
  final String id, title, content, createdBy;
  final DateTime createdAt;
  Announcement({required this.id, required this.title, required this.content, required this.createdAt, required this.createdBy});
}