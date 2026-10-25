import 'package:flutter/foundation.dart';
import '../domain/hospital_history.dart';

class HospitalHistoryViewModel extends ChangeNotifier {
  HospitalHistoryViewModel(this.repository, this.clinic, this.isCurrent);
  final HospitalHistoryRepository repository;
  final String clinic;
  final bool Function() isCurrent;
  List<Map<String, dynamic>> stays = [];
  HospitalHistoryDetail? detail;
  Map<String, dynamic>? next;
  String query = '';
  String? selected, error;
  bool busy = false, _disposed = false;
  int _generation = 0;
  /// Clears visible history and selection, invalidating in-flight responses.
  void clear() {
    _generation++;
    stays = [];
    detail = null;
    next = null;
    selected = null;
    query = '';
    error = null;
    busy = false;
    if (!_disposed) notifyListeners();
  }

  /// Loads history or the selected stay, optionally appending the next page.
  ///
  /// Omitted [search] and [stay] retain the current query and selection; use
  /// [back] to return to the list. Stale responses are ignored. Read failures
  /// or repeated page rows clear results and set [error] instead of propagating;
  /// loss of the current context clears all history state.
  Future<void> load({String? search, bool more = false, String? stay}) async {
    if (_disposed) return;
    if (!isCurrent()) {
      clear();
      return;
    }
    if (more && (busy || next == null)) return;
    final selection = stay ?? selected;
    final requestQuery = search ?? query;
    final before = more ? next : null;
    final generation = ++_generation;
    query = requestQuery;
    selected = selection;
    busy = true;
    error = null;
    if (!more) {
      stays = [];
      detail = null;
      next = null;
    }
    notifyListeners();
    try {
      if (selection == null) {
        final page = await repository.closedHistory(
          clinic,
          requestQuery,
          before,
        );
        if (_disposed || generation != _generation) return;
        if (!isCurrent()) {
          clear();
          return;
        }
        if (more &&
            page.stays.any((r) => stays.any((old) => old['id'] == r['id']))) {
          throw StateError('history_page_changed');
        }
        stays = [if (more) ...stays, ...page.stays];
        next = page.next;
      } else {
        final page = await repository.closedDetail(clinic, selection, before);
        if (_disposed || generation != _generation) return;
        if (!isCurrent()) {
          clear();
          return;
        }
        if (more &&
            page.tasks.any(
              (r) => detail!.tasks.any((old) => old['id'] == r['id']),
            )) {
          throw StateError('history_page_changed');
        }
        detail = HospitalHistoryDetail(
          page.stay,
          [if (more) ...detail!.tasks, ...page.tasks],
          page.events,
          page.next,
        );
        next = page.next;
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        stays = [];
        detail = null;
        next = null;
        error =
            'No se pudo consultar el historial. Actualiza tus permisos y conexión; verifica que esté instalada la actualización de hospitalización.';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  /// Returns to the first history page while retaining the search query.
  Future<void> back() async {
    selected = null;
    await load();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    stays = [];
    detail = null;
    super.dispose();
  }
}
