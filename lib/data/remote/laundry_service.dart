/// Serviço da lavanderia — reservar e cancelar horário de máquina.
///
/// **Por que estas escritas não passam pela outbox.** A regra do projeto é que
/// toda escrita é otimista e enfileirada ([AGENTS.md] §6 regra 8). Reservar é
/// a exceção consciente, por dois motivos:
///
/// 1. Reservar offline não significa nada. A vaga é disputada: aceitar a
///    reserva no cache e descobrir meia hora depois, quando a fila drenar, que
///    outra pessoa levou o horário é pior do que recusar na hora.
/// 2. A resposta do servidor **é** a informação que interessa. Quem garante
///    que não há reserva dupla é o índice único no Postgres, e o app precisa do
///    resultado dessa tentativa para dizer "horário já reservado, atualize a
///    planilha".
///
/// As duas operações são RPCs `security definer`: a tabela não tem policy de
/// insert/update direto, justamente para não existir caminho que reserve em
/// nome de outra pessoa ou ignore um intervalo.
abstract interface class LaundryService {
  /// Reserva uma célula da grade para o usuário logado. Devolve o id criado.
  ///
  /// Erros esperados, já convertidos para `AppException`:
  /// - `conflict` — alguém reservou primeiro (violação do índice único), ou o
  ///   cadastro mudou embaixo da grade desenhada;
  /// - `laundrySlotBlocked` — a célula é intervalo naquele dia da semana;
  /// - `laundryPastDate` — a data já passou.
  Future<String> reserve({
    required String machineId,
    required String timeSlotId,
    required DateTime onDate,
  });

  /// Cancela uma reserva. Só o dono, ou um admin.
  Future<void> cancel(String reservationId);
}
