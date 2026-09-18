import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veredas/core/error/error_mapper.dart';
import 'package:veredas/data/remote/laundry_service.dart';

/// Implementação do [LaundryService] sobre as RPCs do Supabase.
class SupabaseLaundryService implements LaundryService {
  SupabaseLaundryService(this._client);

  final SupabaseClient _client;

  @override
  Future<String> reserve({
    required String machineId,
    required String timeSlotId,
    required DateTime onDate,
  }) async {
    try {
      final result = await _client.rpc(
        'reserve_laundry_slot',
        params: {
          'p_machine_id': machineId,
          'p_time_slot_id': timeSlotId,
          // A coluna é `date`: mandar um timestamp completo faria o Postgres
          // truncar pelo fuso do servidor, o que move a reserva um dia quando
          // a hora local está perto da meia-noite.
          'p_on_date': _dateOnly(onDate),
        },
      );
      return result.toString();
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> cancel(String reservationId) async {
    try {
      await _client.rpc(
        'cancel_laundry_reservation',
        params: {'p_id': reservationId},
      );
    } catch (e) {
      throw mapError(e);
    }
  }

  static String _dateOnly(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
