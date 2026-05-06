import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'auth_screen.dart';
import 'profile_screen.dart';
import 'band_library_screen.dart';

// Color Palette
const Color smokyBlack = Color(0xFF110703);
const Color licorice = Color(0xFF230F08);
const Color blackBean = Color(0xFF34170D);
const Color kobicha = Color(0xFF6E3C19);
const Color chamoisee = Color(0xFFA7795E);
const Color highlightSuccess = Color(0xFF558B2F);
const Color highlightWarning = Color(0xFFD4A017);
const Color highlightError = Color(0xFFC62828);
const Color highlightInfo = Color(0xFF5D6D7E);

// Music Positions for the month
const List<String> musicPositions = [
  'Guitar 1 🎸',
  'Guitar 2 🎸',
  'Bass 🎸',
  'Rhythm 🥁',
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
  
  // Month navigation (shared between Assign and Schedule tabs)
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

  // Stream subscriptions
  late StreamSubscription<QuerySnapshot> _assignmentsSubscription;
  late StreamSubscription<QuerySnapshot> _announcementsSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadLastSeenTime();
    _listenToAssignmentsRealTime();
    _listenToAnnouncementsRealTime();
    _setupOneSignal();
  }

  @override
  void dispose() {
    _assignmentsSubscription.cancel();
    _announcementsSubscription.cancel();
    super.dispose();
  }

  // Refresh function for pull-to-refresh
  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });
    await _loadData();
    setState(() {
      _isLoading = false;
    });
  }

  void _setupOneSignal() {
    OneSignal.Notifications.addClickListener((event) {
      print("📱 Notification clicked: ${event.notification.title}");
      final additionalData = event.notification.additionalData;
      final type = additionalData?['type'];
      
      if (type == 'assignment') {
        print("🎵 Navigate to Schedule tab");
        setState(() => _selectedIndex = 2);
      } else if (type == 'announcement') {
        print("📢 Navigate to Updates tab");
        setState(() => _selectedIndex = 3);
      }
    });
    print("✅ OneSignal listener setup complete");
  }

  Future<void> _sendPushNotification(String title, String message, String type) async {
    const String appId = "6eed93c0-d444-4990-9c6d-cc151a557578";
    const String apiKey = "os_v2_app_n3wzhqguirezbhdnzqkruvlvpccdd4gdjw5e3onkmjwi2cdilvitmvr4euh7gcwac45ofj3dyk6or6mn5jwqexc5esk5xnlkrdu3tgy";
    
    try {
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $apiKey',
        },
        body: jsonEncode({
          'app_id': appId,
          'headings': {'en': title},
          'contents': {'en': message},
          'data': {'type': type},
          'included_segments': ['All'],
        }),
      );
      
      if (response.statusCode == 200) {
        print("✅ Push notification sent: $title");
      } else {
        print("❌ Failed to send: ${response.body}");
      }
    } catch (e) {
      print("❌ Error: $e");
    }
  }

  Future<String> _getCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Unknown';
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data()?['name'] != null && doc.data()!['name'].toString().isNotEmpty) {
        return doc.data()!['name'];
      } else {
        return user.email?.split('@').first ?? 'User';
      }
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
      setState(() {
        assignments = updatedAssignments;
      });
    });
  }

  void _listenToAnnouncementsRealTime() {
    _announcementsSubscription = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      List<Announcement> updatedAnnouncements = snapshot.docs.map((doc) {
        final data = doc.data();
        return Announcement(
          id: doc.id,
          title: data['title'] ?? '',
          content: data['content'] ?? '',
          createdAt: (data['createdAt'] as Timestamp).toDate(),
          createdBy: data['createdBy'] ?? '',
        );
      }).toList();
      
      final newOnes = updatedAnnouncements.where((a) => !announcements.any((old) => old.id == a.id)).toList();
      
      setState(() {
        announcements = updatedAnnouncements;
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
        backgroundColor: licorice,
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
              const Text('New Announcement', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(announcement.title, style: TextStyle(color: chamoisee, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: smokyBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  announcement.content.length > 100 ? '${announcement.content.substring(0, 100)}...' : announcement.content,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: kobicha)),
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
        backgroundColor: licorice,
        title: const Text('Delete Announcements', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete ${_selectedAnnouncementIds.length} announcement(s)?',
          style: TextStyle(color: chamoisee),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: highlightError),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: chamoisee)),
    );

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (String id in _selectedAnnouncementIds) {
        batch.delete(FirebaseFirestore.instance.collection('announcements').doc(id));
      }
      await batch.commit();
      _exitSelectionMode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${_selectedAnnouncementIds.length} announcement(s)'), backgroundColor: highlightSuccess),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting announcements: $e'), backgroundColor: highlightError),
        );
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
    await FirebaseFirestore.instance.collection('announcements').add({
      'title': title,
      'content': content,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': realName,
    });
    await _sendPushNotification('📢 New Announcement', title, 'announcement');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement posted!'), backgroundColor: highlightSuccess),
      );
    }
  }

  Future<void> _deleteAnnouncement(String id) async {
    await FirebaseFirestore.instance.collection('announcements').doc(id).delete();
  }

  void _showAddAnnouncementDialog() {
    TextEditingController titleCtrl = TextEditingController();
    TextEditingController contentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: licorice,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.announcement, color: chamoisee, size: 24),
                  SizedBox(width: 10),
                  Text('Add Announcement', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Title',
                  labelStyle: TextStyle(color: chamoisee),
                  filled: true,
                  fillColor: smokyBlack.withOpacity(0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 8,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Content',
                  labelStyle: TextStyle(color: chamoisee),
                  filled: true,
                  fillColor: smokyBlack.withOpacity(0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.grey, side: BorderSide(color: kobicha)),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (titleCtrl.text.trim().isNotEmpty && contentCtrl.text.trim().isNotEmpty) {
                          await _saveAnnouncement(titleCtrl.text.trim(), contentCtrl.text.trim());
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                      child: const Text('Post'),
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

  void _showEditAnnouncementDialog(Announcement announcement) {
    TextEditingController titleCtrl = TextEditingController(text: announcement.title);
    TextEditingController contentCtrl = TextEditingController(text: announcement.content);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: licorice,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.edit_note, color: chamoisee, size: 24),
                  SizedBox(width: 10),
                  Text('Edit Announcement', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Title',
                  labelStyle: TextStyle(color: chamoisee),
                  filled: true,
                  fillColor: smokyBlack.withOpacity(0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 8,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Content',
                  labelStyle: TextStyle(color: chamoisee),
                  filled: true,
                  fillColor: smokyBlack.withOpacity(0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.grey, side: BorderSide(color: kobicha)),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await FirebaseFirestore.instance.collection('announcements').doc(announcement.id).update({
                          'title': titleCtrl.text.trim(),
                          'content': contentCtrl.text.trim(),
                        });
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Announcement updated!'), backgroundColor: highlightSuccess),
                        );
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                      child: const Text('Update'),
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

  void _showDeleteConfirmationDialog(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: licorice,
        title: const Text('Delete Announcement', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete this announcement?', style: TextStyle(color: chamoisee)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              await _deleteAnnouncement(id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Announcement deleted!'), backgroundColor: highlightError),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: highlightError),
            child: const Text('Delete'),
          ),
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
        return MemberForAdmin(
          id: doc.id,
          name: data['name'] ?? 'Unknown',
          email: data['email'] ?? '',
          isAdmin: data['isAdmin'] ?? false,
        );
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

  // ✅ SAFE getters with null check
  String getAssignedMemberName(String dateKey) {
    if (assignments.isEmpty) return 'Not Assigned';
    try {
      final assignment = assignments.firstWhere(
        (a) => a.dateKey == dateKey,
        orElse: () => ScheduleAssignmentForAdmin(
          dateKey: '', date: '', time: '', assignedMemberId: '', assignedMemberName: 'Not Assigned', assignedMemberEmail: '', status: 'empty', sendDate: null,
        ),
      );
      return assignment.assignedMemberName;
    } catch (e) {
      return 'Not Assigned';
    }
  }

  String getAssignedMemberId(String dateKey) {
    if (assignments.isEmpty) return '';
    try {
      final assignment = assignments.firstWhere(
        (a) => a.dateKey == dateKey,
        orElse: () => ScheduleAssignmentForAdmin(
          dateKey: '', date: '', time: '', assignedMemberId: '', assignedMemberName: '', assignedMemberEmail: '', status: 'empty', sendDate: null,
        ),
      );
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
    await _sendPushNotification('🎵 New Worship Leader Assignment', '$memberName assigned as Worship Leader on $date', 'assignment');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ $memberName assigned as Worship Leader on $date'), backgroundColor: highlightSuccess),
    );
  }

  Future<void> _unassignMember(String dateKey) async {
    final assignment = assignments.firstWhere((a) => a.dateKey == dateKey);
    final date = assignment.date;
    final removedName = assignment.assignedMemberName;
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
      await _sendPushNotification('⚠️ Schedule Update', '$removedName removed as Worship Leader on $date', 'assignment');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ $removedName removed from $date. Lineup cleared.'), backgroundColor: highlightWarning),
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
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [smokyBlack, blackBean, kobicha]),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: chamoisee, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                        child: Text(DateFormat('d').format(DateTime.parse(dateKey)), style: TextStyle(color: chamoisee, fontSize: 20, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(date, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(time, style: TextStyle(color: chamoisee, fontSize: 14)),
                        ]),
                      ),
                      if (currentAssigneeId.isNotEmpty)
                        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                          child: Text('Assigned', style: TextStyle(color: highlightSuccess, fontSize: 12))),
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
                      decoration: BoxDecoration(color: licorice.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: kobicha)),
                      child: Row(
                        children: [
                          const Icon(Icons.person, color: highlightSuccess),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Currently Assigned', style: TextStyle(color: Colors.grey, fontSize: 11)),
                            Text(currentAssigneeName, style: const TextStyle(color: Colors.white, fontSize: 16)),
                          ])),
                          OutlinedButton.icon(
                            onPressed: () { Navigator.pop(context); _unassignMember(dateKey); },
                            icon: const Icon(Icons.clear, size: 16),
                            label: const Text('Remove'),
                            style: OutlinedButton.styleFrom(foregroundColor: highlightError, side: const BorderSide(color: highlightError)),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Worship Leader', style: TextStyle(color: chamoisee, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('${members.length} members', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: members.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.people_outline, size: 48, color: chamoisee.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text('No registered members yet', style: TextStyle(color: chamoisee)),
                          const SizedBox(height: 8),
                          Text('Ask members to sign up first', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ]))
                      : ListView.builder(
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final member = members[index];
                            final isSelected = selectedMemberId == member.id;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? kobicha.withOpacity(0.3) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSelected ? chamoisee : kobicha, width: 1.5),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: kobicha, child: Text(member.name[0].toUpperCase())),
                                title: Row(children: [
                                  Text(member.name, style: const TextStyle(color: Colors.white)),
                                  if (member.isAdmin) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: chamoisee.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                                      child: Text('Admin', style: TextStyle(color: chamoisee, fontSize: 8))),
                                ]),
                                subtitle: Text(member.email, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                trailing: isSelected
                                    ? Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: highlightSuccess, borderRadius: BorderRadius.circular(20)),
                                        child: const Text('Selected', style: TextStyle(color: Colors.white, fontSize: 11)))
                                    : ElevatedButton(
                                        onPressed: () => setSheetState(() => selectedMemberId = member.id),
                                        style: ElevatedButton.styleFrom(backgroundColor: kobicha, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                                        child: const Text('Assign', style: TextStyle(fontSize: 11)),
                                      ),
                              ),
                            );
                          },
                        ),
                ),
                if (selectedMemberId != null && selectedMemberId != currentAssigneeId)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(side: BorderSide(color: kobicha)), child: const Text('Cancel'))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final selected = members.firstWhere((m) => m.id == selectedMemberId);
                              _assignMember(dateKey, date, time, selected.id, selected.name, selected.email);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                            child: const Text('Confirm Assignment'),
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
    );
  }

  Widget _buildScheduleContent() {
    final currentMonthKeys = availableDates.map((d) => d['dateKey']).toSet();
    final filteredAssignments = assignments.where((a) => currentMonthKeys.contains(a.dateKey)).toList();
    filteredAssignments.sort((a, b) => a.dateKey.compareTo(b.dateKey));

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: chamoisee,
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
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_today, size: 64, color: chamoisee),
                          const SizedBox(height: 16),
                          Text('No schedules for $currentMonth $currentYear', style: TextStyle(color: chamoisee, fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredAssignments.length,
                      itemBuilder: (context, index) {
                        final assignment = filteredAssignments[index];
                        return _buildScheduleCard(assignment);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard(ScheduleAssignmentForAdmin assignment) {
    final isAssigned = assignment.assignedMemberId.isNotEmpty;
    final cacheData = notepadCache[assignment.dateKey];
    final hasLineUp = cacheData?['hasLineUp'] ?? false;
    final notepadContent = cacheData?['notepadContent'] ?? '';
    final notes = cacheData?['notes'] ?? '';

    String statusText;
    Color statusColor;
    if (assignment.status == 'empty') {
      statusText = 'Empty';
      statusColor = Colors.grey;
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
      onTap: () => _showViewOnlyLineupDialog(assignment, notepadContent, notes, hasLineUp),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isAssigned ? kobicha.withOpacity(0.15) : licorice.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isAssigned ? chamoisee : kobicha, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: isAssigned ? highlightSuccess.withOpacity(0.15) : kobicha.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Icon(isAssigned ? Icons.check_circle : Icons.person, color: isAssigned ? highlightSuccess : chamoisee, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(assignment.date, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(assignment.time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(width: 16),
                            const Icon(Icons.person, size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              isAssigned ? assignment.assignedMemberName : 'Not Assigned',
                              style: TextStyle(color: isAssigned ? highlightSuccess : chamoisee, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
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
                              Icon(
                                assignment.status == 'empty' ? Icons.hourglass_empty : (assignment.status == 'sealed' ? Icons.lock : Icons.edit),
                                size: 10,
                                color: statusColor,
                              ),
                              const SizedBox(width: 4),
                              Text(statusText, style: TextStyle(color: statusColor, fontSize: 9)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasLineUp)
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                      child: Text('Lineup Ready', style: TextStyle(color: highlightSuccess, fontSize: 10))),
                ],
              ),
            ),
            if (isAssigned)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: smokyBlack.withOpacity(0.3), borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16))),
                child: Row(
                  children: [
                    Icon(Icons.edit_note, color: chamoisee, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        notepadContent.isEmpty ? 'No lineup added yet. Tap to view.' : 'Tap to view lineup',
                        style: TextStyle(color: notepadContent.isEmpty ? chamoisee : Colors.white70, fontSize: 12),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: chamoisee, size: 16),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showViewOnlyLineupDialog(ScheduleAssignmentForAdmin assignment, String notepadContent, String notes, bool hasLineUp) async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('assignments').doc(assignment.dateKey).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        notepadContent = data['notepadContent'] ?? '';
        notes = data['notes'] ?? '';
        hasLineUp = data['hasLineUp'] ?? false;
      }
    } catch (e) {}

    String statusText;
    Color statusColor;
    if (assignment.status == 'empty') {
      statusText = 'Empty';
      statusColor = Colors.grey;
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
          gradient: LinearGradient(colors: [smokyBlack, blackBean, kobicha]),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: chamoisee, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.visibility, color: chamoisee)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(assignment.assignedMemberName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(assignment.date, style: TextStyle(color: chamoisee, fontSize: 14)),
                      Text(assignment.time, style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 12)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          assignment.status == 'empty' ? Icons.hourglass_empty : (assignment.status == 'sealed' ? Icons.lock : Icons.edit),
                          size: 12,
                          color: statusColor,
                        ),
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
                    const Text('Song Line Up', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: smokyBlack.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kobicha.withOpacity(0.5)),
                      ),
                      child: notepadContent.isEmpty
                          ? Center(child: Text('No lineup yet.', style: TextStyle(color: chamoisee, fontSize: 12)))
                          : _buildClickableNotepadTextView(context, notepadContent),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Notes', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: smokyBlack.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kobicha.withOpacity(0.5)),
                        ),
                        child: _buildClickableNotepadTextView(context, notes),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: kobicha, minimumSize: const Size(double.infinity, 48)),
                child: const Text('Close'),
              ),
            ),
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
                  if (part.isNotEmpty) {
                    return Text(part, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4));
                  }
                  return const SizedBox.shrink();
                }),
                ...urls.map((urlString) {
                  return GestureDetector(
                    onTap: () async {
                      final Uri uri = Uri.parse(urlString);
                      try {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Could not open link: $urlString'), backgroundColor: highlightError),
                          );
                        }
                      }
                    },
                    child: Text(
                      urlString,
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        height: 1.4,
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        } else if (line.contains('🎵') || line.contains('📝') || line.contains('✅')) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(line, style: TextStyle(color: chamoisee, fontSize: 12, fontWeight: FontWeight.w500)),
          );
        } else if (line.trim().isEmpty) {
          return const SizedBox(height: 6);
        } else {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(line, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4)),
          );
        }
      }).toList(),
    );
  }

  Widget _buildUpdatesContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveCurrentViewTime());
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: chamoisee,
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
                  const Text('Announcements', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _showAddAnnouncementDialog,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: highlightSuccess,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: chamoisee),
                        onSelected: (value) {
                          if (value == 'select_all') {
                            _enterSelectionMode();
                            _toggleSelectAll();
                          } else if (value == 'delete_selected') {
                            if (_selectedAnnouncementIds.isNotEmpty) {
                              _deleteSelectedAnnouncements();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('No announcements selected'), backgroundColor: highlightWarning),
                              );
                            }
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'select_all', child: Text('Select All')),
                          PopupMenuItem(value: 'delete_selected', child: Text('Delete Selected', style: TextStyle(color: highlightError))),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: announcements.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.announcement, size: 64, color: chamoisee.withOpacity(0.5)),
                            const SizedBox(height: 16),
                            Text('No announcements yet', style: TextStyle(color: chamoisee, fontSize: 16)),
                            const SizedBox(height: 8),
                            Text('Tap + to create an announcement', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: announcements.length,
                        itemBuilder: (context, index) {
                          final a = announcements[index];
                          final isSelected = _selectedAnnouncementIds.contains(a.id);
                          final isNew = _lastSeenTime == null || a.createdAt.isAfter(_lastSeenTime!);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? kobicha.withOpacity(0.3) : licorice.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isSelected ? chamoisee : kobicha, width: isSelected ? 2 : 1),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kobicha.withOpacity(0.3),
                                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                                  ),
                                  child: Row(
                                    children: [
                                      if (_isSelectionMode)
                                        Checkbox(
                                          value: isSelected,
                                          onChanged: (checked) {
                                            setState(() {
                                              if (checked == true) {
                                                _selectedAnnouncementIds.add(a.id);
                                              } else {
                                                _selectedAnnouncementIds.remove(a.id);
                                              }
                                            });
                                          },
                                          activeColor: highlightSuccess,
                                          checkColor: Colors.white,
                                        ),
                                      const Icon(Icons.announcement, color: chamoisee, size: 20),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(child: Text(a.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                                                if (isNew)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                                                    child: Text('NEW', style: TextStyle(color: highlightSuccess, fontSize: 9, fontWeight: FontWeight.bold)),
                                                  ),
                                              ],
                                            ),
                                            Text(
                                              'Posted by ${a.createdBy} • ${DateFormat('MMM d, yyyy').format(a.createdAt)}',
                                              style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!_isSelectionMode)
                                        PopupMenuButton<String>(
                                          icon: Icon(Icons.more_vert, color: chamoisee),
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              _showEditAnnouncementDialog(a);
                                            } else if (value == 'delete') {
                                              _showDeleteConfirmationDialog(a.id);
                                            }
                                          },
                                          itemBuilder: (context) => const [
                                            PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
                                            PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: highlightError), SizedBox(width: 8), Text('Delete', style: TextStyle(color: highlightError))])),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                                if (!_isSelectionMode)
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: smokyBlack.withOpacity(0.3),
                                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_note, color: chamoisee, size: 16),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(a.content, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4))),
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
            ? FloatingActionButton.extended(
                onPressed: _deleteSelectedAnnouncements,
                backgroundColor: highlightError,
                icon: const Icon(Icons.delete),
                label: Text('Delete (${_selectedAnnouncementIds.length})'),
              )
            : null,
      ),
    );
  }

  Widget _buildBandLibraryContent() => const BandLibraryScreen();

  Widget _buildDrawer() {
    String initials = UserSession.userName?.isNotEmpty == true ? UserSession.userName![0].toUpperCase() : 'A';
    return Drawer(
      backgroundColor: licorice,
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [smokyBlack, blackBean, licorice])),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 24),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: kobicha.withOpacity(0.5)))),
              child: Row(
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [kobicha, chamoisee]), border: Border.all(color: chamoisee, width: 2)),
                    child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(UserSession.userName ?? 'Admin', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                          child: const Text('Administrator', style: TextStyle(color: chamoisee, fontSize: 11)),
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
            _buildDrawerItem(
              icon: Icons.announcement,
              title: 'Updates',
              index: 3,
              isSelected: _selectedIndex == 3,
              badge: _unreadCount > 0 ? '$_unreadCount' : null,
            ),
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
                  if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AuthScreen()));
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isSelected ? kobicha.withOpacity(0.3) : Colors.transparent,
        border: isSelected ? Border.all(color: chamoisee.withOpacity(0.5)) : null,
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? chamoisee : Colors.grey),
        title: Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
        trailing: badge != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: highlightError, borderRadius: BorderRadius.circular(20)),
                child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              )
            : null,
        onTap: () {
          setState(() => _selectedIndex = index);
          if (_isSelectionMode) _exitSelectionMode();
          Navigator.pop(context);
        },
      ),
    );
  }

  // ✅ ==================== ASSIGN TAB WITH PULL-TO-REFRESH ====================
  Widget _buildAssignContent() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: chamoisee,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Sunday Services', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Tap card to assign WL', style: TextStyle(color: chamoisee, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: availableDates.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.calendar_today, size: 64, color: chamoisee),
                        const SizedBox(height: 16),
                        const Text('No Sundays in this month', style: TextStyle(color: Colors.grey)),
                      ]))
                    : ListView.builder(
                        itemCount: availableDates.length,
                        itemBuilder: (context, index) {
                          final date = availableDates[index];
                          return _buildAssignmentCard(date['date'], date['dateKey'], date['time'], date['dayOfMonth']);
                        },
                      ),
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
          for (var entry in musiciansMap.entries) {
            musicians[entry.key] = AssignedMusician.fromMap(entry.value as Map<String, dynamic>);
          }
          assignedCount = musicians.values.where((m) => m.musicianId.isNotEmpty).length;
        }
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: licorice.withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: kobicha.withOpacity(0.5))),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [Icon(Icons.music_note, color: chamoisee, size: 16), const SizedBox(width: 6),
                    const Text('Band Members for this Month', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500))]),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: assignedCount > 0 ? highlightSuccess.withOpacity(0.2) : highlightWarning.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                    child: Text('$assignedCount/${musicPositions.length} assigned', style: TextStyle(color: assignedCount > 0 ? highlightSuccess : highlightWarning, fontSize: 10))),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: musicPositions.map((position) {
                  String assignedName = 'Not Assigned';
                  Color textColor = Colors.grey;
                  if (musicians != null && musicians.containsKey(position)) {
                    final musician = musicians[position]!;
                    if (musician.musicianId.isNotEmpty) {
                      assignedName = musician.musicianName;
                      textColor = highlightSuccess;
                    }
                  }
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(color: smokyBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(10), border: Border.all(color: kobicha.withOpacity(0.3))),
                      child: Column(
                        children: [
                          Text(position, style: TextStyle(color: chamoisee, fontSize: 9), textAlign: TextAlign.center),
                          const SizedBox(height: 4),
                          Text(assignedName, style: TextStyle(color: textColor, fontSize: 9), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
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
        Container(
          width: 45, height: 45,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [kobicha, chamoisee]), borderRadius: BorderRadius.circular(22.5)),
          child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(UserSession.userName ?? 'Admin', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
              child: const Text('Admin', style: TextStyle(color: chamoisee, fontSize: 10))),
          ],
        ),
      ],
    );
  }

  // ✅ MEMBERS TAB WITH PULL-TO-REFRESH
  Widget _buildMembersContent() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: chamoisee,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildSimpleHeader(),
              const SizedBox(height: 20),
              Expanded(
                child: members.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.people_outline, size: 64, color: chamoisee),
                        const SizedBox(height: 16),
                        Text('No members yet', style: TextStyle(color: chamoisee, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text('Members will appear here after signing up', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ]))
                    : ListView.builder(
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final member = members[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: licorice.withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: kobicha, width: 1.5)),
                            child: Row(
                              children: [
                                CircleAvatar(backgroundColor: kobicha, radius: 25, child: Text(member.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18))),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text(member.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                                        if (member.isAdmin) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(color: chamoisee.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                                            child: Text('Admin', style: TextStyle(color: chamoisee, fontSize: 10))),
                                      ]),
                                      Text(member.email, style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
      decoration: BoxDecoration(color: licorice.withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: kobicha, width: 1.5)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: Icon(Icons.chevron_left, color: chamoisee), onPressed: _previousMonth, constraints: const BoxConstraints()),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(currentMonth, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(currentYear.toString(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
          IconButton(icon: Icon(Icons.chevron_right, color: chamoisee), onPressed: _nextMonth, constraints: const BoxConstraints()),
        ],
      ),
    );
  }

  // ✅ SAFE assignment card with null handling
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
    } catch (e) {
      // Use defaults if assignments not ready
    }
    
    DateTime sundayDate = DateTime.parse(dateKey);
    bool isToday = sundayDate.year == DateTime.now().year && sundayDate.month == DateTime.now().month && sundayDate.day == DateTime.now().day;
    bool isPast = sundayDate.isBefore(DateTime.now()) && !isToday;
    
    return GestureDetector(
      onTap: () => _showAssignDialog(dateKey, date, time, currentAssigneeId, currentAssigneeName),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isToday ? kobicha.withOpacity(0.2) : licorice.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isToday ? chamoisee : kobicha, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: isAssigned ? highlightSuccess.withOpacity(0.15) : kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(25)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(dayOfMonth.toString(), style: TextStyle(color: isAssigned ? highlightSuccess : chamoisee, fontSize: 18, fontWeight: FontWeight.bold)),
                const Text('SUN', style: TextStyle(color: Colors.grey, fontSize: 8)),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(time, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      const SizedBox(width: 12),
                      const Icon(Icons.person, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(isAssigned ? currentAssigneeName : 'Not Assigned', style: TextStyle(color: isAssigned ? highlightSuccess : chamoisee, fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  if (isToday) Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(8)), child: Text('TODAY', style: TextStyle(color: chamoisee, fontSize: 9))),
                  if (isPast && !isAssigned) Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: highlightError.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Text('MISSED', style: TextStyle(color: highlightError, fontSize: 9))),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: chamoisee, size: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/music.png'), fit: BoxFit.cover)),
        child: const Center(child: CircularProgressIndicator(color: chamoisee)),
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
      decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/music.png'), fit: BoxFit.cover)),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_getAppBarTitle()),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: chamoisee,
          leading: Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu, color: chamoisee), onPressed: () => Scaffold.of(context).openDrawer())),
          actions: _selectedIndex == 3 && _isSelectionMode
              ? [TextButton(onPressed: _exitSelectionMode, child: const Text('Cancel', style: TextStyle(color: chamoisee)))]
              : null,
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