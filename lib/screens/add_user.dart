// add_user.dart (modified as a widget, not a full page)
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Color palette (same as before)
const Color smokyBlack = Color(0xFF110703);
const Color licorice = Color(0xFF230F08);
const Color blackBean = Color(0xFF34170D);
const Color kobicha = Color(0xFF6E3C19);
const Color chamoisee = Color(0xFFA7795E);
const Color highlightSuccess = Color(0xFF558B2F);
const Color highlightError = Color(0xFFC62828);

class MusiciansListWidget extends StatefulWidget {
  const MusiciansListWidget({super.key});

  @override
  State<MusiciansListWidget> createState() => _MusiciansListWidgetState();
}

class _MusiciansListWidgetState extends State<MusiciansListWidget> {
  final TextEditingController _nameController = TextEditingController();
  bool _isAdding = false;

  Future<bool> _addMusician(String name) async {
    try {
      await FirebaseFirestore.instance.collection('musicians').add({
        'name': name.trim(),
        'email': '',
        'phone': '',
        'instruments': [],
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'addedBy': FirebaseAuth.instance.currentUser?.uid ?? 'musician_account',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Musician added successfully!'), backgroundColor: highlightSuccess),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: highlightError),
        );
      }
      return false;
    }
  }

  void _showAddDialog() {
    _nameController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: licorice,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Add New Musician', style: TextStyle(color: chamoisee)),
            content: TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Full Name',
                labelStyle: TextStyle(color: chamoisee),
                hintText: 'e.g., John Smith',
                hintStyle: TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: kobicha)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: chamoisee, width: 2)),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: _isAdding
                    ? null
                    : () async {
                        if (_nameController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a name'), backgroundColor: highlightError),
                          );
                          return;
                        }
                        setDialogState(() => _isAdding = true);
                        bool success = await _addMusician(_nameController.text);
                        setDialogState(() => _isAdding = false);
                        if (success && mounted) {
                          Navigator.pop(context);
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                child: _isAdding
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('musicians')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('Error: ${snapshot.error}', style: const TextStyle(color: highlightError)),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: chamoisee));
            }
            final musicians = snapshot.data!.docs;
            if (musicians.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_off, size: 64, color: chamoisee.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    Text('No musicians yet.', style: TextStyle(color: chamoisee, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Tap + button to add one.', style: TextStyle(color: chamoisee, fontSize: 12)),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: musicians.length,
              itemBuilder: (context, index) {
                final doc = musicians[index];
                final data = doc.data() as Map<String, dynamic>;
                final name = data['name'] ?? 'Unknown';
                final isActive = data['isActive'] ?? true;
                final instruments = List<String>.from(data['instruments'] ?? []);
                final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: licorice.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kobicha),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: kobicha,
                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (instruments.isNotEmpty)
                          Text(
                            '🎸 ${instruments.take(2).join(', ')}${instruments.length > 2 ? '...' : ''}',
                            style: TextStyle(color: chamoisee, fontSize: 12),
                          ),
                        if (createdAt != null)
                          Text(
                            'Added: ${_formatDate(createdAt)}',
                            style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 10),
                          ),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive ? highlightSuccess.withOpacity(0.2) : highlightError.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isActive ? 'Active' : 'Inactive',
                        style: TextStyle(color: isActive ? highlightSuccess : highlightError, fontSize: 10),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        // FAB stays on top of the list
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: _showAddDialog,
            backgroundColor: highlightSuccess,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}