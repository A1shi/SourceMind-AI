import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
const String geminiModel = 'gemini-2.5-flash';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SourceMindApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Gemini App Ready')),
      ),
    );
  }
}

class SourceMindApp extends StatelessWidget {
  const SourceMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SourceMind AI',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F7FC),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C5CE7)),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ============================================================
// MODELS
// ============================================================

class Note {
  final String id;
  String title;
  String content;

  Note({required this.id, required this.title, required this.content});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        content: '${json['content'] ?? ''}',
      );
}

class SourceDocument {
  final String id;
  final String name;
  final String type;
  final String content;

  SourceDocument({
    required this.id,
    required this.name,
    required this.type,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'content': content,
      };

  factory SourceDocument.fromJson(Map<String, dynamic> json) => SourceDocument(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Untitled source'}',
        type: '${json['type'] ?? 'TXT'}',
        content: '${json['content'] ?? ''}',
      );
}
class ChatMessage {
  final String text;
  final bool user;

  ChatMessage({
    required this.text,
    required this.user,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'user': user,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text']?.toString() ?? '',
      user: json['user'] == true,
    );
  }
}
class Notebook {
  final String id;
  final String title;
  final String description;
  final List<Note> notes;
  final List<SourceDocument> sourceDocuments;
  final List<ChatMessage> chatHistory;

  Notebook({
    required this.id,
    required this.title,
    required this.description,
    List<Note>? notes,
    List<SourceDocument>? sourceDocuments,
    List<ChatMessage>? chatHistory,
  })  : notes = notes ?? [],
        sourceDocuments = sourceDocuments ?? [],
        chatHistory = chatHistory ?? [];

  int get sources => sourceDocuments.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'sources': sources,
        'notes': notes.map((note) => note.toJson()).toList(),
        'sourceDocuments': sourceDocuments.map((source) => source.toJson()).toList(),
        'chatHistory': chatHistory.map((message) => message.toJson()).toList(),
      };

  factory Notebook.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sourceDocuments'];
    final rawNotes = json['notes'];
    final rawChatHistory = json['chatHistory'];

    return Notebook(
      id: '${json['id'] ?? DateTime.now().millisecondsSinceEpoch}',
      title: '${json['title'] ?? 'Untitled notebook'}',
      description: '${json['description'] ?? ''}',
      notes: rawNotes is List
          ? rawNotes
              .map((item) => Note.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : [],
      sourceDocuments: rawSources is List
          ? rawSources
              .map((item) => SourceDocument.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : [],
      chatHistory: rawChatHistory is List
        ? rawChatHistory
            .map(
              (item) => ChatMessage.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList()
        : [],
    );
  }
}

// ============================================================
// GEMINI SERVICE
// ============================================================

class GeminiService {
  static Future<String> generate(String prompt) async {
    if (geminiApiKey.trim().isEmpty) {
      throw Exception(
        "Gemini API key is not configured. Run the app with --dart-define=GEMINI_API_KEY='YOUR_API_KEY_HERE'",
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=$geminiApiKey',
    );

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.3,
              'maxOutputTokens': 4096,
            },
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Gemini request failed (${response.statusCode}).';
      try {
        final body = jsonDecode(response.body);
        final apiMessage = body['error']?['message'];
        if (apiMessage is String && apiMessage.isNotEmpty) message = apiMessage;
      } catch (_) {}
      throw Exception(message);
    }

    final decoded = jsonDecode(response.body);
    final candidates = decoded['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final parts = candidates.first['content']?['parts'];
      if (parts is List) {
        final text = parts
            .map((part) => part['text'])
            .whereType<String>()
            .join('\n')
            .trim();
        if (text.isNotEmpty) return text;
      }
    }

    throw Exception('SourceMindAI returned an empty response.');
  }

  static String buildNotebookContext(Notebook notebook) {
    final buffer = StringBuffer();
    buffer.writeln('NOTEBOOK: ${notebook.title}');
    if (notebook.description.isNotEmpty) {
      buffer.writeln('DESCRIPTION: ${notebook.description}');
    }

    if (notebook.notes.isNotEmpty) {
      buffer.writeln('\nNOTES:');
      for (final note in notebook.notes) {
        buffer.writeln('\n[NOTE: ${note.title}]');
        buffer.writeln(note.content);
      }
    }

    if (notebook.sourceDocuments.isNotEmpty) {
      buffer.writeln('\nSOURCES:');
      for (final source in notebook.sourceDocuments) {
        buffer.writeln('\n[SOURCE: ${source.name}]');
        buffer.writeln(source.content);
      }
    }

    // Keep mobile requests manageable. Gemini 2.5 Flash has a large context,
    // but this app should not accidentally send enormous local documents.
    final text = buffer.toString();
    return text.length <= 180000 ? text : text.substring(0, 180000);
  }
}

// ============================================================
// HOME
// ============================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;
  final List<Notebook> notebooks = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadNotebooks();
  }

  Future<void> loadNotebooks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('notebooks');

      if (savedData != null && savedData.isNotEmpty) {
        final decoded = jsonDecode(savedData);
        if (decoded is List) {
          final loaded = decoded
              .map((item) => Notebook.fromJson(Map<String, dynamic>.from(item)))
              .toList();
          if (!mounted) return;
          setState(() {
            notebooks
              ..clear()
              ..addAll(loaded);
          });
        }
      }
    } catch (e) {
      debugPrint('ERROR LOADING NOTEBOOKS: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> saveNotebooks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'notebooks',
        jsonEncode(notebooks.map((notebook) => notebook.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('ERROR SAVING NOTEBOOKS: $e');
    }
  }

  void createNotebook() {
    showDialog(
      context: context,
      builder: (_) => CreateNotebookDialog(
        onCreate: (title, description) async {
          final notebook = Notebook(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: title,
            description: description,
          );
          setState(() => notebooks.insert(0, notebook));
          await saveNotebooks();
        },
      ),
    );
  }

  void openNotebook(Notebook notebook) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotebookScreen(
          notebook: notebook,
          onChanged: () {
            setState(() {});
            saveNotebooks();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: selectedIndex,
                children: [
                  HomeContent(
                    notebooks: notebooks,
                    onCreateNotebook: createNotebook,
                    onNotebookTap: openNotebook,
                  ),
                  SearchScreen(
                    notebooks: notebooks,
                    onChanged: () {
                      setState(() {});
                      saveNotebooks();
                    },
                  ),
                  ActivityScreen(notebooks: notebooks),
                  const SettingsScreen(),
                ],
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => selectedIndex = index),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE9E5FF),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class HomeContent extends StatelessWidget {
  final List<Notebook> notebooks;
  final VoidCallback onCreateNotebook;
  final Function(Notebook) onNotebookTap;

  const HomeContent({
    super.key,
    required this.notebooks,
    required this.onCreateNotebook,
    required this.onNotebookTap,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF7C6FF2), Color(0xFF5B4BC4)]),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 25),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SourceMind', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                      Text('AI-powered learning', style: TextStyle(color: Color(0xFF777481), fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Color(0xFFE9E6F0)),
                  ),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
            child: Container(
              padding: const EdgeInsets.all(23),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF7062E8), Color(0xFF5546C0)]),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 20,
                    offset: const Offset(0, 9),
                    color: const Color(0xFF6658D8).withValues(alpha: 0.20),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text('YOUR AI STUDY SPACE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.7)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 17),
                  const Text('Think deeper.\nLearn smarter.', style: TextStyle(color: Colors.white, fontSize: 29, height: 1.12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 11),
                  Text('Organize your knowledge and let AI help you understand it.', style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 13, height: 1.45)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: onCreateNotebook,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create Notebook', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF5C4CC8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 15),
            child: Row(
              children: [
                const Expanded(child: Text('Your Notebooks', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                if (notebooks.isNotEmpty) Text('${notebooks.length}', style: const TextStyle(color: Color(0xFF6C5CE7), fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
        if (notebooks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
              child: EmptyNotebookCard(onCreateNotebook: onCreateNotebook),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: NotebookCard(notebook: notebooks[index], onTap: () => onNotebookTap(notebooks[index])),
                ),
                childCount: notebooks.length,
              ),
            ),
          ),
      ],
    );
  }
}

class EmptyNotebookCard extends StatelessWidget {
  final VoidCallback onCreateNotebook;
  const EmptyNotebookCard({super.key, required this.onCreateNotebook});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: const Color(0xFFE8E4EF))),
      child: Column(
        children: [
          Container(
            height: 70,
            width: 70,
            decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(22)),
            child: const Icon(Icons.menu_book_rounded, size: 32, color: Color(0xFF6C5CE7)),
          ),
          const SizedBox(height: 18),
          const Text('No notebooks yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          const Text('Create your first notebook to start\norganizing your learning.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF817D89), fontSize: 13, height: 1.5)),
          const SizedBox(height: 18),
          OutlinedButton.icon(onPressed: onCreateNotebook, icon: const Icon(Icons.add), label: const Text('Create one')),
        ],
      ),
    );
  }
}

class NotebookCard extends StatelessWidget {
  final Notebook notebook;
  final VoidCallback onTap;
  const NotebookCard({super.key, required this.notebook, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE8E4EF))),
          child: Row(
            children: [
              Container(height: 58, width: 58, decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(17)), child: const Icon(Icons.menu_book_rounded, color: Color(0xFF6959D8), size: 28)),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notebook.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(notebook.description.isEmpty ? 'No description' : notebook.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF85818C), fontSize: 12)),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        const Icon(Icons.description_outlined, size: 14, color: Color(0xFF918C98)),
                        const SizedBox(width: 4),
                        Text('${notebook.notes.length} notes', style: const TextStyle(color: Color(0xFF918C98), fontSize: 11)),
                        const SizedBox(width: 12),
                        const Icon(Icons.source_outlined, size: 14, color: Color(0xFF918C98)),
                        const SizedBox(width: 4),
                        Text('${notebook.sources} sources', style: const TextStyle(color: Color(0xFF918C98), fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFAAA5B2)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CREATE NOTEBOOK
// ============================================================

class CreateNotebookDialog extends StatefulWidget {
  final Future<void> Function(String, String) onCreate;
  const CreateNotebookDialog({super.key, required this.onCreate});

  @override
  State<CreateNotebookDialog> createState() => _CreateNotebookDialogState();
}

class _CreateNotebookDialogState extends State<CreateNotebookDialog> {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final title = titleController.text.trim();
    if (title.isEmpty || saving) return;
    setState(() => saving = true);
    await widget.onCreate(title, descriptionController.text.trim());
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      title: const Text('Create Notebook', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleController,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Notebook name', hintText: 'e.g. Machine Learning', prefixIcon: const Icon(Icons.menu_book_outlined), filled: true, fillColor: const Color(0xFFF7F5FA), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: descriptionController,
            maxLines: 2,
            decoration: InputDecoration(labelText: 'Description', hintText: 'What are you studying?', prefixIcon: const Icon(Icons.notes_outlined), filled: true, fillColor: const Color(0xFFF7F5FA), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: saving ? null : submit, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6758D8), foregroundColor: Colors.white), child: saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create')),
      ],
    );
  }
}

// ============================================================
// NOTEBOOK WORKSPACE
// ============================================================

class NotebookScreen extends StatefulWidget {
  final Notebook notebook;
  final VoidCallback onChanged;
  const NotebookScreen({super.key, required this.notebook, required this.onChanged});

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  void addNote() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          onSave: (title, content) {
            setState(() {
              widget.notebook.notes.insert(0, Note(id: DateTime.now().millisecondsSinceEpoch.toString(), title: title, content: content));
            });
            widget.onChanged();
          },
        ),
      ),
    );
  }

  void editNote(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          note: note,
          onSave: (title, content) {
            setState(() {
              note.title = title;
              note.content = content;
            });
            widget.onChanged();
          },
        ),
      ),
    );
  }

  void deleteNote(Note note) {
    setState(() => widget.notebook.notes.remove(note));
    widget.onChanged();
  }

  void openSources() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SourcesScreen(notebook: widget.notebook, onChanged: () { setState(() {}); widget.onChanged(); }),
      ),
    );
  }

  void openAskAI() {
  Navigator.push(
    context, 
    MaterialPageRoute(
      builder: (_) => AskAIScreen(
        notebook: widget.notebook,
        onChanged: () {
          setState(() {});
          widget.onChanged();
        },
      ),
    ),
  );
}

  void openSummary() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SummaryScreen(notebook: widget.notebook)));
  }

  void openQuiz() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => QuizScreen(notebook: widget.notebook)));
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.notebook.notes;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
        title: Text(widget.notebook.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addNote,
        backgroundColor: const Color(0xFF6758D8),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Note', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7062E8), Color(0xFF5748C4)]), borderRadius: BorderRadius.circular(25)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 27),
              const SizedBox(height: 15),
              Text(widget.notebook.title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Text(widget.notebook.description.isEmpty ? 'Your personal learning workspace' : widget.notebook.description, style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 25),
          Row(children: [const Expanded(child: Text('Notes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))), Text('${notes.length}', style: const TextStyle(color: Color(0xFF6C5CE7), fontWeight: FontWeight.w800, fontSize: 16))]),
          const SizedBox(height: 14),
          if (notes.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 35),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(23), border: Border.all(color: const Color(0xFFE8E4EF))),
              child: const Column(children: [
                Icon(Icons.edit_note_rounded, color: Color(0xFF6C5CE7), size: 55),
                SizedBox(height: 16),
                Text('No notes yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                SizedBox(height: 7),
                Text('Write your first note and keep\nyour learning organized.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF85818C), height: 1.5)),
              ]),
            )
          else
            ...notes.map((note) => Padding(padding: const EdgeInsets.only(bottom: 13), child: NoteCard(note: note, onTap: () => editNote(note), onDelete: () => deleteNote(note)))),
          const SizedBox(height: 25),
          const Text('AI Tools', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: WorkspaceAction(icon: Icons.picture_as_pdf_outlined, title: 'Sources', subtitle: '${widget.notebook.sources} sources', onTap: openSources)),
            const SizedBox(width: 12),
            Expanded(child: WorkspaceAction(icon: Icons.chat_bubble_outline_rounded, title: 'Ask AI', subtitle: 'Ask SourceMindAI', onTap: openAskAI)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: WorkspaceAction(icon: Icons.summarize_outlined, title: 'Summary', subtitle: 'AI summary', onTap: openSummary)),
            const SizedBox(width: 12),
            Expanded(child: WorkspaceAction(icon: Icons.quiz_outlined, title: 'Quiz', subtitle: 'Generate quiz', onTap: openQuiz)),
          ]),
        ],
      ),
    );
  }
}

class WorkspaceAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const WorkspaceAction({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8E4EF))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 43, width: 43, decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: const Color(0xFF6657D5))),
            const SizedBox(height: 13),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8B8692), fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

// ============================================================
// SOURCES
// ============================================================

class SourcesScreen extends StatefulWidget {
  final Notebook notebook;
  final VoidCallback onChanged;
  const SourcesScreen({super.key, required this.notebook, required this.onChanged});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  bool importing = false;

  Future<void> addSource() async {
    if (importing) return;
    setState(() => importing = true);

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt'],
      );

      if (files.isEmpty) return;

      final file = files.first;
      final name = file.name;

      final extension =
          name.contains('.') ? name.split('.').last.toLowerCase() : '';

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception('Could not read the selected file.');
      }
      String extractedText;
      String type;

      if (extension == 'pdf') {
        type = 'PDF';
        extractedText = _extractPdfText(bytes);
      } else if (extension == 'txt') {
        type = 'TXT';
        extractedText = utf8.decode(bytes, allowMalformed: true);
      } else {
        throw Exception('Only PDF and TXT files are supported.');
      }

      extractedText = extractedText.trim();
      if (extractedText.isEmpty) {
        throw Exception('No readable text was found in this file.');
      }

      final source = SourceDocument(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        type: type,
        content: extractedText,
      );

      setState(() => widget.notebook.sourceDocuments.insert(0, source));
      widget.onChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name added successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add source: $e')));
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  String _extractPdfText(Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      return PdfTextExtractor(document).extractText();
    } finally {
      document.dispose();
    }
  }

  void deleteSource(SourceDocument source) {
    setState(() => widget.notebook.sourceDocuments.remove(source));
    widget.onChanged();
  }

  void openSource(SourceDocument source) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SourceViewerScreen(source: source)));
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.notebook.sourceDocuments;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
        title: const Text('Sources', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: importing ? null : addSource, icon: const Icon(Icons.add_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: importing ? null : addSource,
        backgroundColor: const Color(0xFF6758D8),
        foregroundColor: Colors.white,
        icon: importing ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_file_rounded),
        label: Text(importing ? 'Importing...' : 'Add Source'),
      ),
      body: sources.isEmpty
          ? _EmptySources(onAdd: addSource)
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 110),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFF6C5CE7)),
                    const SizedBox(width: 12),
                    Expanded(child: Text('SourceMindAI can use these ${sources.length} source${sources.length == 1 ? '' : 's'} for answers, summaries and quizzes.', style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF575263)))),
                  ]),
                ),
                const SizedBox(height: 18),
                ...sources.map((source) => Padding(padding: const EdgeInsets.only(bottom: 12), child: SourceCard(source: source, onTap: () => openSource(source), onDelete: () => deleteSource(source)))),
              ],
            ),
    );
  }
}

class _EmptySources extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptySources({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(height: 80, width: 80, decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(25)), child: const Icon(Icons.source_rounded, color: Color(0xFF6C5CE7), size: 38)),
          const SizedBox(height: 18),
          const Text('No sources yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Add PDF or TXT study material.\nSourceMindAI will use it for your AI tools.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF85818C), height: 1.5)),
          const SizedBox(height: 20),
          ElevatedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add Source'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6758D8), foregroundColor: Colors.white)),
        ]),
      ),
    );
  }
}

class SourceCard extends StatelessWidget {
  final SourceDocument source;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const SourceCard({super.key, required this.source, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8E4EF))),
          child: Row(children: [
            Container(height: 52, width: 52, decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(15)), child: Icon(source.type == 'PDF' ? Icons.picture_as_pdf_outlined : Icons.text_snippet_outlined, color: const Color(0xFF6C5CE7))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text('${source.type} • ${source.content.length} characters', style: const TextStyle(color: Color(0xFF85818C), fontSize: 11))])),
            PopupMenuButton<String>(onSelected: (value) { if (value == 'delete') onDelete(); }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red), SizedBox(width: 10), Text('Delete')]))]),
          ]),
        ),
      ),
    );
  }
}

class SourceViewerScreen extends StatelessWidget {
  final SourceDocument source;
  const SourceViewerScreen({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)), title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8E4EF))),
          child: SelectableText(source.content, style: const TextStyle(fontSize: 15, height: 1.6)),
        ),
      ),
    );
  }
}

// ============================================================
// NOTE CARD + EDITOR
// ============================================================

class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const NoteCard({super.key, required this.note, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8E4EF))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 48, width: 48, decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.description_outlined, color: Color(0xFF6C5CE7))),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(note.content.isEmpty ? 'Empty note' : note.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF85818C), fontSize: 13, height: 1.45))])),
            PopupMenuButton<String>(onSelected: (value) { if (value == 'delete') onDelete(); }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red), SizedBox(width: 10), Text('Delete')]))]),
          ]),
        ),
      ),
    );
  }
}

class NoteEditorScreen extends StatefulWidget {
  final Note? note;
  final Function(String title, String content) onSave;
  const NoteEditorScreen({super.key, this.note, required this.onSave});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController titleController;
  late final TextEditingController contentController;
  bool get isEditing => widget.note != null;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.note?.title ?? '');
    contentController = TextEditingController(text: widget.note?.content ?? '');
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    super.dispose();
  }

  void save() {
    final title = titleController.text.trim();
    final content = contentController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a note title')));
      return;
    }
    widget.onSave(title, content);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)), title: Text(isEditing ? 'Edit Note' : 'New Note', style: const TextStyle(fontWeight: FontWeight.w800)), actions: [Padding(padding: const EdgeInsets.only(right: 10), child: TextButton(onPressed: save, child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF6758D8))))) ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(24, 15, 24, 30), children: [
        Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8E4EF))), child: TextField(controller: titleController, textCapitalization: TextCapitalization.sentences, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800), decoration: const InputDecoration(hintText: 'Note title', border: InputBorder.none, contentPadding: EdgeInsets.all(18)))),
        const SizedBox(height: 15),
        Container(constraints: const BoxConstraints(minHeight: 420), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8E4EF))), child: TextField(controller: contentController, textCapitalization: TextCapitalization.sentences, maxLines: null, minLines: 18, style: const TextStyle(fontSize: 16, height: 1.6), decoration: const InputDecoration(hintText: 'Start writing your notes here...', border: InputBorder.none, contentPadding: EdgeInsets.all(20)))),
        const SizedBox(height: 15),
        const Row(children: [Icon(Icons.auto_awesome, size: 17, color: Color(0xFF6C5CE7)), SizedBox(width: 7), Text('AI can understand these notes later.', style: TextStyle(color: Color(0xFF85818C), fontSize: 11))]),
      ]),
    );
  }
}

// ============================================================
// ASK AI
// ============================================================


class AskAIScreen extends StatefulWidget {
  final Notebook notebook;
  final VoidCallback onChanged; // Added callback

  const AskAIScreen({
    super.key,
    required this.notebook,
    required this.onChanged,
  });

  @override
  State<AskAIScreen> createState() => _AskAIScreenState();
}



class _AskAIScreenState extends State<AskAIScreen> {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  late List<ChatMessage> messages;
  bool loading = false;

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    messages = widget.notebook.chatHistory;
}

  Future<void> ask() async {
    final question = controller.text.trim();
    if (question.isEmpty || loading) return;

    controller.clear();

    setState(() {
      messages.add(ChatMessage(text: question, user: true));
      loading = true;
    });
    widget.onChanged(); // Persist changes immediately
    _scrollDown();

    try {
      final notebookContext = GeminiService.buildNotebookContext(widget.notebook);
      final prompt = '''
You are SourceMindAI helping a student learn from their notebook.
Use the notebook context below to answer the question.

NOTEBOOK CONTEXT:
$notebookContext

QUESTION:
$question
''';

      final answer = await GeminiService.generate(prompt);
      if (mounted) {
        setState(() => messages.add(ChatMessage(text: answer, user: false)));
        widget.onChanged(); // Persist answer
      }
    } catch (e) {
      if (mounted) {
        setState(() => messages.add(ChatMessage(text: 'I could not reach SourceMindAI.\n\n$e', user: false)));
        widget.onChanged();
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
        _scrollDown();
      }
    }
  }
  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.animateTo(scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)), title: const Text('Ask SourceMindAI', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Column(children: [
        Expanded(
          child: messages.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(height: 75, width: 75, decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.auto_awesome, color: Color(0xFF6C5CE7), size: 36)), const SizedBox(height: 18), const Text('Ask anything about this notebook', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), const SizedBox(height: 8), Text(widget.notebook.sources == 0 && widget.notebook.notes.isEmpty ? 'Add a source or note first.' : 'SourceMindAI will answer using your notebook content.', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF85818C)))])))
              : ListView.builder(controller: scrollController, padding: const EdgeInsets.all(18), itemCount: messages.length, itemBuilder: (_, index) => _MessageBubble(message: messages[index])),
        ),
        if (loading) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('SourceMindAI is thinking...', style: TextStyle(color: Color(0xFF85818C), fontSize: 12))),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Row(children: [
              Expanded(child: TextField(controller: controller, minLines: 1, maxLines: 4, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: 'Ask a question...', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13)))),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: loading ? null : ask, style: IconButton.styleFrom(backgroundColor: const Color(0xFF6758D8), foregroundColor: Colors.white), icon: const Icon(Icons.arrow_upward_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.84),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: message.user ? const Color(0xFF6758D8) : Colors.white, borderRadius: BorderRadius.circular(18), border: message.user ? null : Border.all(color: const Color(0xFFE8E4EF))),
        child: SelectableText(message.text, style: TextStyle(color: message.user ? Colors.white : const Color(0xFF302D38), height: 1.5, fontSize: 14)),
      ),
    );
  }
}

// ============================================================
// SUMMARY
// ============================================================

class SummaryScreen extends StatefulWidget {
  final Notebook notebook;
  const SummaryScreen({super.key, required this.notebook});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  String summary = '';
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    generateSummary();
  }

  Future<void> generateSummary() async {
    if (loading) return;
    setState(() { loading = true; error = null; });
    try {
      final contextText = GeminiService.buildNotebookContext(widget.notebook);
      final result = await GeminiService.generate('''Create a useful study summary from the following SourceMind notebook material.
Include: 1) overview, 2) key concepts, 3) important facts, and 4) quick revision points.
Do not invent information that is absent from the material.

NOTEBOOK MATERIAL:
$contextText''');
      if (mounted) setState(() => summary = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)), title: const Text('AI Summary', style: TextStyle(fontWeight: FontWeight.w800)), actions: [IconButton(onPressed: loading ? null : generateSummary, icon: const Icon(Icons.refresh_rounded))]),
      body: loading
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 14), Text('SourceMindAI is creating your summary...')]))
          : error != null
              ? _ErrorState(message: error!, onRetry: generateSummary)
              : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), child: Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8E4EF))), child: SelectableText(summary, style: const TextStyle(fontSize: 15, height: 1.6)))),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline_rounded, color: Color(0xFF6C5CE7), size: 48), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF85818C))), const SizedBox(height: 18), ElevatedButton(onPressed: onRetry, child: const Text('Try again'))])));
  }
}

// ============================================================
// QUIZ
// ============================================================

class QuizQuestion {
  final String question;
  final List<String> options;
  final int answer;
  final String explanation;

  QuizQuestion({required this.question, required this.options, required this.answer, required this.explanation});
}

class QuizScreen extends StatefulWidget {
  final Notebook notebook;
  const QuizScreen({super.key, required this.notebook});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<QuizQuestion> questions = [];
  int current = 0;
  int score = 0;
  int? selected;
  bool loading = true;
  String? error;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    generateQuiz();
  }

  Future<void> generateQuiz() async {
    setState(() { loading = true; error = null; finished = false; current = 0; score = 0; selected = null; });
    try {
      final contextText = GeminiService.buildNotebookContext(widget.notebook);
      final result = await GeminiService.generate('''Generate exactly 5 multiple-choice study questions from the notebook material below.
Return ONLY valid JSON with this structure:
{"questions":[{"question":"...","options":["...","...","...","..."],"answer":0,"explanation":"..."}]}
The answer must be a zero-based integer from 0 to 3. Do not use markdown or code fences. Questions must be answerable from the supplied material and should have one clearly best answer.

NOTEBOOK MATERIAL:
$contextText''');

      final parsed = _parseQuiz(result);
      if (parsed.isEmpty) throw Exception('SourceMindAI returned an invalid quiz format.');
      if (mounted) setState(() => questions = parsed);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<QuizQuestion> _parseQuiz(String text) {
    try {
      var cleaned = text.trim();
      
      // Extract JSON payload if surrounded by conversational text
      final startIdx = cleaned.indexOf('{');
      final endIdx = cleaned.lastIndexOf('}');
      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        cleaned = cleaned.substring(startIdx, endIdx + 1);
      }

      final decoded = jsonDecode(cleaned);
      final raw = decoded['questions'];
      if (raw is! List) return [];

      return raw.map<QuizQuestion?>((item) {
        if (item is! Map) return null;
        final opts = item['options'];
        if (opts is! List || opts.length < 4) return null;
        final answer = item['answer'];
        if (answer is! int || answer < 0 || answer >= 4) return null;
        return QuizQuestion(
          question: '${item['question'] ?? ''}',
          options: opts.take(4).map((e) => '$e').toList(),
          answer: answer,
          explanation: '${item['explanation'] ?? ''}',
        );
      }).whereType<QuizQuestion>().take(5).toList();
    } catch (_) {
      return [];
    }
  }

  void select(int index) {
    if (selected != null) return;
    setState(() {
      selected = index;
      if (index == questions[current].answer) score++;
    });
  }

  void next() {
    if (current >= questions.length - 1) {
      setState(() => finished = true);
    } else {
      setState(() { current++; selected = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)), title: const Text('AI Quiz', style: TextStyle(fontWeight: FontWeight.w800))),
      body: loading
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 14), Text('SourceMindAI is generating your quiz...')]))
          : error != null
              ? _ErrorState(message: error!, onRetry: generateQuiz)
              : finished
                  ? _QuizResult(score: score, total: questions.length, onAgain: generateQuiz)
                  : _QuizQuestionView(question: questions[current], number: current + 1, total: questions.length, selected: selected, onSelect: select, onNext: next),
    );
  }
}

class _QuizQuestionView extends StatelessWidget {
  final QuizQuestion question;
  final int number;
  final int total;
  final int? selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onNext;
  const _QuizQuestionView({required this.question, required this.number, required this.total, required this.selected, required this.onSelect, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(20, 15, 20, 30), children: [
      Row(children: [Expanded(child: Text('Question $number of $total', style: const TextStyle(fontWeight: FontWeight.w800))), Text('${((number / total) * 100).round()}%', style: const TextStyle(color: Color(0xFF6C5CE7), fontWeight: FontWeight.w800))]),
      const SizedBox(height: 10),
      ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: number / total, minHeight: 7, backgroundColor: const Color(0xFFE8E4EF), color: const Color(0xFF6C5CE7))),
      const SizedBox(height: 22),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE8E4EF))), child: Text(question.question, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.35))),
      const SizedBox(height: 16),
      ...List.generate(question.options.length, (index) {
        final isSelected = selected == index;
        final isCorrect = selected != null && index == question.answer;
        return Padding(padding: const EdgeInsets.only(bottom: 11), child: InkWell(onTap: selected == null ? () => onSelect(index) : null, borderRadius: BorderRadius.circular(17), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: isCorrect ? const Color(0xFFEAF8EF) : isSelected ? const Color(0xFFFFEEEE) : Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: isCorrect ? const Color(0xFF5AAE76) : isSelected ? Colors.redAccent : const Color(0xFFE8E4EF))), child: Row(children: [Container(height: 30, width: 30, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(10)), child: Text(String.fromCharCode(65 + index), style: const TextStyle(color: Color(0xFF6C5CE7), fontWeight: FontWeight.w800))), const SizedBox(width: 12), Expanded(child: Text(question.options[index], style: const TextStyle(fontSize: 14, height: 1.4))), if (isCorrect) const Icon(Icons.check_circle, color: Color(0xFF4B9C68)), if (isSelected && !isCorrect) const Icon(Icons.cancel, color: Colors.redAccent)]))));
      }),
      if (selected != null) ...[
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(17)), child: Text('Explanation: ${question.explanation}', style: const TextStyle(fontSize: 13, height: 1.5))),
        const SizedBox(height: 16),
        SizedBox(height: 48, child: ElevatedButton(onPressed: onNext, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6758D8), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text(number == total ? 'See Result' : 'Next Question'))),
      ],
    ]);
  }
}

class _QuizResult extends StatelessWidget {
  final int score;
  final int total;
  final VoidCallback onAgain;
  const _QuizResult({required this.score, required this.total, required this.onAgain});

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0 : ((score / total) * 100).round();
    return Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(height: 100, width: 100, decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(30)), child: const Icon(Icons.emoji_events_rounded, color: Color(0xFF6C5CE7), size: 50)), const SizedBox(height: 20), const Text('Quiz complete!', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)), const SizedBox(height: 8), Text('$score / $total correct • $percent%', style: const TextStyle(fontSize: 18, color: Color(0xFF6C5CE7), fontWeight: FontWeight.w800)), const SizedBox(height: 22), ElevatedButton.icon(onPressed: onAgain, icon: const Icon(Icons.refresh), label: const Text('Generate Another Quiz'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6758D8), foregroundColor: Colors.white))])));
  }
}

// ============================================================
// SMART SEARCH
// ============================================================

class SearchResult {
  final Notebook notebook;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  SearchResult({required this.notebook, required this.title, required this.subtitle, required this.icon, required this.onTap});
}

class SearchScreen extends StatefulWidget {
  final List<Notebook> notebooks;
  final VoidCallback onChanged;

  const SearchScreen({
    super.key,
    required this.notebooks,
    required this.onChanged,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final controller = TextEditingController();
  String query = '';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  List<SearchResult> get results {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final output = <SearchResult>[];

    for (final notebook in widget.notebooks) {
      if ('${notebook.title} ${notebook.description}'.toLowerCase().contains(q)) {
        output.add(SearchResult(notebook: notebook, title: notebook.title, subtitle: 'Notebook • ${notebook.notes.length} notes • ${notebook.sources} sources', icon: Icons.menu_book_rounded, onTap: () => _openNotebook(notebook)));
      }
      for (final note in notebook.notes) {
        if ('${note.title} ${note.content}'.toLowerCase().contains(q)) {
          output.add(SearchResult(notebook: notebook, title: note.title, subtitle: 'Note in ${notebook.title}', icon: Icons.description_outlined, onTap: () => _openNotebook(notebook)));
        }
      }
      for (final source in notebook.sourceDocuments) {
        if ('${source.name} ${source.content}'.toLowerCase().contains(q)) {
          output.add(SearchResult(notebook: notebook, title: source.name, subtitle: '${source.type} source in ${notebook.title}', icon: source.type == 'PDF' ? Icons.picture_as_pdf_outlined : Icons.text_snippet_outlined, onTap: () => _openNotebook(notebook)));
        }
      }
    }
    return output;
  }

  void _openNotebook(Notebook notebook) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => NotebookScreen(
        notebook: notebook,
        onChanged: () {
          setState(() {});
          widget.onChanged();
        },
      ),
    ),
  );
}
  @override
  Widget build(BuildContext context) {
    final items = results;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 25, 24, 30),
          children: [
            const Text('Search', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              'Find anything across your notebooks, notes and sources.',
              style: TextStyle(color: Color(0xFF85818C)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          controller.clear();
                          setState(() => query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                hintText: 'Search your knowledge...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (query.trim().isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE8E4EF)),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.manage_search_rounded, color: Color(0xFF6C5CE7), size: 42),
                    SizedBox(height: 12),
                    Text('Start searching', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    SizedBox(height: 6),
                    Text(
                      'Try a notebook name, note title or a word from a source.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF85818C), height: 1.4),
                    ),
                  ],
                ),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Column(
                  children: [
                    Icon(Icons.search_off_rounded, color: Color(0xFF6C5CE7), size: 45),
                    SizedBox(height: 12),
                    Text('No matches found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ],
                ),
              )
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: item.onTap,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE8E4EF)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              height: 45,
                              width: 45,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0EDFF),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(item.icon, color: const Color(0xFF6C5CE7)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF85818C),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFFAAA5B2)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ACTIVITY / DASHBOARD
// ============================================================

class ActivityScreen extends StatelessWidget {
  final List<Notebook> notebooks;
  const ActivityScreen({super.key, required this.notebooks});

  @override
  Widget build(BuildContext context) {
    final notebookCount = notebooks.length;
    final noteCount = notebooks.fold<int>(0, (sum, n) => sum + n.notes.length);
    final sourceCount = notebooks.fold<int>(0, (sum, n) => sum + n.sources);
    final chars = notebooks.fold<int>(0, (sum, n) => sum + n.notes.fold<int>(0, (s, note) => s + note.content.length) + n.sourceDocuments.fold<int>(0, (s, source) => s + source.content.length));

    return Scaffold(backgroundColor: const Color(0xFFF8F7FC), body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(24, 25, 24, 30), children: [
      const Text('Learning Dashboard', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('A quick view of your SourceMind workspace.', style: TextStyle(color: Color(0xFF85818C))),
      const SizedBox(height: 22),
      Row(children: [Expanded(child: _StatCard(icon: Icons.menu_book_rounded, label: 'Notebooks', value: '$notebookCount')), const SizedBox(width: 12), Expanded(child: _StatCard(icon: Icons.description_outlined, label: 'Notes', value: '$noteCount'))]),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: _StatCard(icon: Icons.source_rounded, label: 'Sources', value: '$sourceCount')), const SizedBox(width: 12), Expanded(child: _StatCard(icon: Icons.text_fields_rounded, label: 'Characters', value: _formatNumber(chars)))]),
      const SizedBox(height: 25),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7062E8), Color(0xFF5748C4)]), borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.auto_awesome, color: Colors.white), const SizedBox(height: 12), const Text('Your AI learning space', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)), const SizedBox(height: 7), Text(sourceCount == 0 ? 'Add your first source to unlock source-grounded AI tools.' : 'You have $sourceCount source${sourceCount == 1 ? '' : 's'} ready for SourceMindAI-powered study tools.', style: TextStyle(color: Colors.white.withValues(alpha: 0.82), height: 1.4))])),
      const SizedBox(height: 25),
      const Text('Notebook Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      if (notebooks.isEmpty) Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8E4EF))), child: const Text('Create a notebook to start tracking your learning.', style: TextStyle(color: Color(0xFF85818C)))) else ...notebooks.map((n) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8E4EF))), child: Row(children: [Expanded(child: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))), Text('${n.notes.length} notes • ${n.sources} sources', style: const TextStyle(color: Color(0xFF85818C), fontSize: 11))])))),
    ])));
  }

  static String _formatNumber(int number) {
    if (number < 1000) return '$number';
    if (number < 1000000) return '${(number / 1000).toStringAsFixed(number % 1000 == 0 ? 0 : 1)}K';
    return '${(number / 1000000).toStringAsFixed(1)}M';
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8E4EF))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 42, width: 42, decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: const Color(0xFF6C5CE7))), const SizedBox(height: 13), Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(label, style: const TextStyle(color: Color(0xFF85818C), fontSize: 11))]));
  }
}

// ============================================================
// SETTINGS
// ============================================================

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final keyConfigured = geminiApiKey.isNotEmpty;
    return Scaffold(backgroundColor: const Color(0xFFF8F7FC), body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(24, 25, 24, 30), children: [
      const Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('SourceMind configuration', style: TextStyle(color: Color(0xFF85818C))),
      const SizedBox(height: 22),
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8E4EF))), child: Row(children: [Container(height: 45, width: 45, decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.auto_awesome, color: Color(0xFF6C5CE7))), const SizedBox(width: 13), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('SourceMindAI', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 4), Text('Used for Ask AI, summaries and quizzes.', style: TextStyle(color: Color(0xFF85818C), fontSize: 11))])), Icon(keyConfigured ? Icons.check_circle : Icons.warning_rounded, color: keyConfigured ? Colors.green : Colors.orange)])),
      const SizedBox(height: 14),
      const _SettingsTile(icon: Icons.security_outlined, title: 'Privacy', subtitle: 'Your local notebook data stays on the device in this demo.'),
      const SizedBox(height: 10),
      const _SettingsTile(icon: Icons.info_outline_rounded, title: 'About SourceMind', subtitle: 'AI-powered learning and document reasoning.'),
    ])));
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SettingsTile({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8E4EF))), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xFF6C5CE7)), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: Color(0xFF85818C), fontSize: 11, height: 1.4))]))]));
  }
}
