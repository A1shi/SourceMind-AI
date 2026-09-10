import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AskAgentResponse {
  final String answer;
  final String sourceType;
  final List<dynamic> sources;
  final bool isSuccess;
  final String? errorMessage;

  AskAgentResponse({
    required this.answer,
    this.sourceType = 'general_knowledge',
    this.sources = const [],
    this.isSuccess = true,
    this.errorMessage,
  });

  factory AskAgentResponse.fromJson(Map<String, dynamic> json) {
    return AskAgentResponse(
      answer: json['answer'] ?? 'No answer received.',
      sourceType: json['source_type'] ?? 'general_knowledge',
      sources: json['sources'] ?? [],
      isSuccess: true,
    );
  }

  factory AskAgentResponse.error(String message) {
    return AskAgentResponse(
      answer: message,
      isSuccess: false,
      errorMessage: message,
    );
  }
}

class ApiService {
  /// Automatically resolves the correct backend host URL depending on platform
  static String get baseUrl {
    if (kIsWeb) {
      return "http://localhost:8000";
    } else if (Platform.isAndroid) {
      return "http://10.0.2.2:8000"; // Android Emulator loopback
    } else {
      return "http://127.0.0.1:8000"; // iOS Simulator / Desktop
    }
  }

  /// Sends a user question and notebook ID to the agent AI endpoint.
  static Future<AskAgentResponse> askQuestion({
    required String question,
    required String notebookId,
  }) async {
    final url = Uri.parse('$baseUrl/agent/ask');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'question': question.trim(),
              'notebook_id': notebookId.trim(),
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return AskAgentResponse.fromJson(data);
      } else if (response.statusCode == 429) {
        return AskAgentResponse.error(
            'Quota exceeded. Please wait a moment before trying again.');
      } else {
        return AskAgentResponse.error(
            'Server error (${response.statusCode}). Please try again later.');
      }
    } on TimeoutException {
      return AskAgentResponse.error(
          'Request timed out. The backend server took too long to respond.');
    } catch (e) {
      return AskAgentResponse.error(
          'Unable to reach the server. Please check your internet connection.');
    }
  }

  /// Sends a user-created text note to be chunked and indexed into ChromaDB.
  static Future<bool> saveNote({
    required String title,
    required String content,
    required String notebookId,
  }) async {
    final url = Uri.parse('$baseUrl/documents/notes');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'title': title.trim(),
              'content': content.trim(),
              'notebook_id': notebookId.trim(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Uploads a PDF or TXT file to be chunked and indexed into ChromaDB.
  static Future<bool> uploadDocument({
    required File file,
    required String notebookId,
  }) async {
    final url = Uri.parse('$baseUrl/documents/upload?notebook_id=$notebookId');

    try {
      final request = http.MultipartRequest('POST', url)
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}