import 'package:flutter/material.dart';

import '../services/bulk_import_service.dart';

/// Screen for bulk-importing a track list from text or file.
class BulkImportScreen extends StatefulWidget {
  final BulkImportService importService;
  final Future<void> Function(List<String> queries, String format) onProcess;

  const BulkImportScreen({
    super.key,
    required this.importService,
    required this.onProcess,
  });

  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen>
    with AutomaticKeepAliveClientMixin {
  final _textController = TextEditingController();
  bool _processing = false;
  List<String>? _parsedQueries;
  String? _error;
  String _selectedFormat = 'mp3';

  @override
  bool get wantKeepAlive => true;

  Future<void> _importFromText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final queries = widget.importService.parseText(text);
      setState(() => _parsedQueries = queries);
      await widget.onProcess(queries, _selectedFormat);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _processing = false);
    }
  }

  Future<void> _importFromFile() async {
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final queries = await widget.importService.importFromFile();
      if (queries.isEmpty) {
        setState(() => _processing = false);
        return;
      }
      setState(() => _parsedQueries = queries);
      await widget.onProcess(queries, _selectedFormat);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _textController,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Paste track list here\nFormat: Artist - Song',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Format: '),
              DropdownButton<String>(
                value: _selectedFormat,
                items: const [
                  DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                  DropdownMenuItem(value: 'm4a', child: Text('M4A')),
                  DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _selectedFormat = v);
                },
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.text_fields),
                label: const Text('Import from Text'),
                onPressed: _processing ? null : _importFromText,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.file_upload),
                label: const Text('Import from File'),
                onPressed: _processing ? null : _importFromFile,
              ),
            ],
          ),
            if (_processing) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_parsedQueries != null && !_processing) ...[
              const SizedBox(height: 16),
              Text('Parsed ${_parsedQueries!.length} tracks',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _parsedQueries!.length,
                  itemBuilder: (context, i) {
                    return ListTile(
                      dense: true,
                      leading: Text('${i + 1}'),
                      title: Text(_parsedQueries![i]),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
    );
  }
}
