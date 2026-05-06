import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Color Palette
const Color smokyBlack = Color(0xFF110703);
const Color licorice = Color(0xFF230F08);
const Color blackBean = Color(0xFF34170D);
const Color kobicha = Color(0xFF6E3C19);
const Color chamoisee = Color(0xFFA7795E);

class AdminScheduleScreen extends StatelessWidget {
  final String adminId;
  final String adminName;
  
  const AdminScheduleScreen({
    super.key,
    required this.adminId,
    required this.adminName,
  });

  @override
  Widget build(BuildContext context) {
    return _AdminScheduleContent(adminId: adminId, adminName: adminName);
  }
}

class _AdminScheduleContent extends StatefulWidget {
  final String adminId;
  final String adminName;
  
  const _AdminScheduleContent({
    required this.adminId,
    required this.adminName,
  });

  @override
  State<_AdminScheduleContent> createState() => __AdminScheduleContentState();
}

class __AdminScheduleContentState extends State<_AdminScheduleContent> {
  List<AdminAssignment> myAssignments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyAssignments();
  }

  Future<void> _loadMyAssignments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('assignments')
          .where('assignedMemberId', isEqualTo: widget.adminId)
          .get();

      myAssignments = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return AdminAssignment(
          dateKey: doc.id,
          date: data['date'] ?? '',
          time: data['time'] ?? '9:00 AM',
          hasLineUp: data['hasLineUp'] ?? false,
          notepadContent: data['notepadContent'] ?? '',
          notes: data['notes'] ?? '',
        );
      }).toList();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading assignments: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveLineup(String dateKey, String songs, String notes) async {
    try {
      await FirebaseFirestore.instance
          .collection('assignments')
          .doc(dateKey)
          .update({
        'notepadContent': songs,
        'notes': notes,
        'hasLineUp': songs.isNotEmpty,
      });
      
      final index = myAssignments.indexWhere((a) => a.dateKey == dateKey);
      if (index != -1) {
        setState(() {
          myAssignments[index].notepadContent = songs;
          myAssignments[index].notes = notes;
          myAssignments[index].hasLineUp = songs.isNotEmpty;
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lineup saved!'),
            backgroundColor: kobicha,
          ),
        );
      }
    } catch (e) {
      print('Error saving: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showNotepadDialog(AdminAssignment assignment) {
    TextEditingController songsController = TextEditingController(text: assignment.notepadContent);
    TextEditingController notesController = TextEditingController(text: assignment.notes);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [smokyBlack, blackBean, kobicha],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: chamoisee,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Song Line Up',
                            style: TextStyle(
                              color: chamoisee,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            assignment.date,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          Text(
                            assignment.time,
                            style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 12),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              color: smokyBlack.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: kobicha),
                            ),
                            child: TextField(
                              controller: songsController,
                              maxLines: 12,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: '''1. Way Maker - Sinach (Key: G)
https://youtube.com/watch?v=waymaker

2. Goodness of God - Bethel (Key: E)

3. What A Beautiful Name - Hillsong (Key: D)

📝 Notes:
- Band call time: 8:00 AM
- Soundcheck: 8:30 AM''',
                                hintStyle: TextStyle(color: Colors.grey),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Additional Notes',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: smokyBlack.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: kobicha),
                            ),
                            child: TextField(
                              controller: notesController,
                              maxLines: 3,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Service notes, reminders...',
                                hintStyle: TextStyle(color: Colors.grey),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: kobicha),
                              foregroundColor: Colors.grey,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              _saveLineup(
                                assignment.dateKey,
                                songsController.text,
                                notesController.text,
                              );
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kobicha,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: chamoisee),
      );
    }

    // WALA NAY CONTAINER UG SCAFFOLD - DIREKTO LANG ANG CONTENT
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          Expanded(
            child: myAssignments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today, size: 64, color: chamoisee),
                        const SizedBox(height: 16),
                        Text(
                          'No schedules assigned to you yet',
                          style: TextStyle(color: chamoisee, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Assign yourself from the Assign tab',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: myAssignments.length,
                    itemBuilder: (context, index) {
                      return _buildScheduleCard(myAssignments[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    String initials = widget.adminName.isNotEmpty 
        ? widget.adminName[0].toUpperCase() 
        : 'A';
    
    return Row(
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kobicha, chamoisee],
            ),
            borderRadius: BorderRadius.circular(22.5),
          ),
          child: Center(
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.adminName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: kobicha.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Worship Leader',
                style: TextStyle(
                  color: chamoisee,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildScheduleCard(AdminAssignment assignment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: licorice.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kobicha, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: kobicha.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Icon(Icons.star, color: chamoisee, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assignment.date,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 12, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            assignment.time,
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: assignment.hasLineUp
                        ? Colors.green.withOpacity(0.2)
                        : kobicha.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    assignment.hasLineUp ? 'Lineup Ready' : 'Pending',
                    style: TextStyle(
                      color: assignment.hasLineUp ? Colors.green : chamoisee,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: smokyBlack.withOpacity(0.3),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: GestureDetector(
              onTap: () => _showNotepadDialog(assignment),
              child: Row(
                children: [
                  Icon(Icons.edit_note, color: chamoisee, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      assignment.notepadContent.isEmpty
                          ? 'Tap to add song lineup'
                          : 'Tap to edit song lineup',
                      style: TextStyle(
                        color: assignment.notepadContent.isEmpty ? chamoisee : Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: chamoisee, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminAssignment {
  String dateKey;
  String date;
  String time;
  bool hasLineUp;
  String notepadContent;
  String notes;

  AdminAssignment({
    required this.dateKey,
    required this.date,
    required this.time,
    required this.hasLineUp,
    required this.notepadContent,
    required this.notes,
  });
}