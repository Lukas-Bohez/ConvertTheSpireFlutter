import 'package:flutter/material.dart';

import '../../data/browser_db.dart';
import '../../widgets/empty_state.dart';

/// Full favourites manager with folders, search, grid/list toggle,
/// drag-to-reorder, and bulk editing.
class FavouritesScreen extends StatefulWidget {
  final BrowserRepository repo;
  final ValueChanged<String> onNavigate;

  const FavouritesScreen({
    super.key,
    required this.repo,
    required this.onNavigate,
  });

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  List<Map<String, dynamic>> _items = [];
  List<String> _folders = [];
  String? _activeFolder;
  String _search = '';
  bool _gridView = false;

  @override
  void initState() {
    super.initState();
    _load();
    widget.repo.addListener(_load);
  }

  @override
  void dispose() {
    widget.repo.removeListener(_load);
    super.dispose();
  }

  void _load() async {
    final favs = await widget.repo.getFavourites(folder: _activeFolder);
    final folders = await widget.repo.getFolders();
    if (mounted) {
      setState(() {
        _items = favs;
        _folders = folders;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _items;
    final q = _search.toLowerCase();
    return _items.where((f) {
      final title = (f['title'] as String? ?? '').toLowerCase();
      final url = (f['url'] as String? ?? '').toLowerCase();
      return title.contains(q) || url.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favourites'),
        actions: [
          IconButton(
            icon: Icon(_gridView ? Icons.list : Icons.grid_view),
            onPressed: () => setState(() => _gridView = !_gridView),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search favourites',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),

          // ── Folder chips ──
          if (_folders.length > 1)
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: _activeFolder == null,
                      onSelected: (_) {
                        setState(() => _activeFolder = null);
                        _load();
                      },
                    ),
                  ),
                  ..._folders.map((f) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: Text(f),
                          selected: _activeFolder == f,
                          onSelected: (_) {
                            setState(() =>
                                _activeFolder = _activeFolder == f ? null : f);
                            _load();
                          },
                        ),
                      )),
                ],
              ),
            ),

          // ── List / Grid ──
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.star_border,
                    title: 'No favourites yet',
                    subtitle:
                        'Add pages to your favourites using the star icon',
                  )
                : _gridView
                    ? _buildGrid(items)
                    : _buildList(items),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: items.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        final ids = items.map((i) => i['id'] as int).toList();
        final id = ids.removeAt(oldIndex);
        ids.insert(newIndex, id);
        widget.repo.reorderFavourites(ids);
      },
      itemBuilder: (context, index) {
        final item = items[index];
        final url = item['url'] as String;
        final title = item['title'] as String? ?? '';
        final favicon = item['favicon'] as String?;
        final folder = item['folder'] as String? ?? '';
        final host = Uri.tryParse(url)?.host ?? url;

        return Dismissible(
          key: ValueKey(item['id']),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => widget.repo.removeFavourite(url),
          child: ListTile(
            leading: _favicon(favicon),
            title: Text(title.isNotEmpty ? title : host,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            trailing: folder.isNotEmpty
                ? Chip(
                    label: Text(folder, style: const TextStyle(fontSize: 10)),
                    visualDensity: VisualDensity.compact,
                  )
                : null,
            onTap: () {
              widget.onNavigate(url);
              Navigator.pop(context);
            },
            onLongPress: () => _showEditDialog(item),
          ),
        );
      },
    );
  }

  Widget _buildGrid(List<Map<String, dynamic>> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(16).copyWith(bottom: 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.85,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final url = item['url'] as String;
        final title = item['title'] as String? ?? '';
        final favicon = item['favicon'] as String?;
        final host = Uri.tryParse(url)?.host ?? url;

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            widget.onNavigate(url);
            Navigator.pop(context);
          },
          onLongPress: () => _showEditDialog(item),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _favicon(favicon, size: 32),
                const SizedBox(height: 8),
                Text(title.isNotEmpty ? title : host,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _favicon(String? url, {double size = 24}) {
    if (url != null && url.isNotEmpty) {
      return Image.network(url,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => Icon(Icons.star, size: size));
    }
    return Icon(Icons.star, size: size);
  }

  void _showAddDialog() {
    final urlC = TextEditingController();
    final titleC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Favourite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlC,
              decoration: const InputDecoration(labelText: 'URL'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: titleC,
              decoration: const InputDecoration(labelText: 'Title (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final url = urlC.text.trim();
              if (url.isNotEmpty) {
                widget.repo.addFavourite(url, titleC.text.trim(), null);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item) {
    final id = item['id'] as int;
    final urlC = TextEditingController(text: item['url'] as String? ?? '');
    final titleC = TextEditingController(text: item['title'] as String? ?? '');
    final folderC =
        TextEditingController(text: item['folder'] as String? ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Favourite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlC,
              decoration: const InputDecoration(labelText: 'URL'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: titleC,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: folderC,
              decoration: const InputDecoration(labelText: 'Folder'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.repo.removeFavourite(item['url'] as String);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () {
              widget.repo.updateFavourite(
                id,
                url: urlC.text.trim(),
                title: titleC.text.trim(),
                folder: folderC.text.trim(),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
