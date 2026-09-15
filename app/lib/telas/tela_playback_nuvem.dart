import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import '../dados/ordenacao_partes.dart';
import '../dados/repositorio_evo.dart';
import '../modelo/carregador_evolucao.dart';
import '../playback/controlador_playback.dart';
import '../tema/paleta.dart';
import 'tela_playback.dart';
import 'widgets_estado.dart';

/// Playback lido do Firestore — a mesma UI de `TelaPlayback` (asset local),
/// mas alimentada por `RepositorioEvo` em vez de `rootBundle`.
///
/// Regra de disciplina #1 do repositório (leitura só por `Stream`) vale até
/// aqui, numa tela que hoje só LÊ: combina `evolucao(id)` + `partes(id)`
/// via `rxdart` (`CombineLatestStream`, em vez de aninhar dois
/// `StreamBuilder` ou reimplementar a combinação à mão) — quando o editor
/// chegar e passar a escrever nesta mesma evolução, a tela não precisa
/// virar `FutureBuilder` de propósito nenhum: já está no formato certo.
class TelaPlaybackNuvem extends StatefulWidget {
  const TelaPlaybackNuvem({super.key, required this.repo, required this.evolucaoId});
  final RepositorioEvo repo;
  final String evolucaoId;

  @override
  State<TelaPlaybackNuvem> createState() => _TelaPlaybackNuvemState();
}

class _TelaPlaybackNuvemState extends State<TelaPlaybackNuvem>
    with SingleTickerProviderStateMixin {
  ControladorPlayback? _controlador;
  PacoteEvolucao? _ultimoPacoteProcessado;

  late final Stream<PacoteEvolucao?> _pacotes = Rx.combineLatest2<EvolucaoDoc?, List<ParteDoc>, PacoteEvolucao?>(
    widget.repo.evolucao(widget.evolucaoId),
    widget.repo.partes(widget.evolucaoId),
    (EvolucaoDoc? doc, List<ParteDoc> partes) {
      if (doc == null) return null;
      final Evolucao evolucao = Evolucao(
        nome: doc.nome,
        estadoInicial: estadoFormacaoDoJson(doc.estadoInicial),
        partes: emOrdem(partes),
      );
      return simularEvolucao(evolucao);
    },
  );

  @override
  void dispose() {
    _controlador?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.fundo,
      appBar: AppBar(title: const Text('Evo Lab — playback')),
      body: StreamBuilder<PacoteEvolucao?>(
        stream: _pacotes,
        builder: (BuildContext context, AsyncSnapshot<PacoteEvolucao?> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CentroCarregando();
          }
          if (snapshot.hasError) {
            return CentroErro(erro: snapshot.error, aoTentarDeNovo: () {});
          }
          final PacoteEvolucao? pacote = snapshot.data;
          if (pacote == null) {
            return const CentroVazio(
              icone: Icons.movie_filter_outlined,
              titulo: 'Esta evolução não existe mais',
              descricao: 'Ela pode ter sido apagada por você ou em outra sessão.',
            );
          }
          // Só recria o controlador quando o STREAM de fato emitiu um
          // pacote novo (identidade de objeto) — `build()` roda de novo
          // por qualquer motivo de rebuild da árvore (não só evento de
          // stream nesta tela), e recriar sempre reiniciaria o playback
          // (posição do playhead, play/pause) a cada rebuild não
          // relacionado. Ver a regra de disciplina #3: esta tela também
          // não deve "piscar" com base em nada que não veio do stream.
          if (!identical(pacote, _ultimoPacoteProcessado)) {
            _controlador?.dispose();
            _controlador = ControladorPlayback(pacote: pacote, vsync: this);
            _ultimoPacoteProcessado = pacote;
          }
          return CorpoPlayback(controlador: _controlador!);
        },
      ),
    );
  }
}
