import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';

import 'package:splg_driver/ui/widgets/driver_header.dart';

const helpEntries = [
  SplgAccordionEntry(
    title: '¿Cómo me pongo en línea?',
    body: 'En Inicio tocá "Conectarse". Mientras estés en línea la '
        'distribuidora te ve en el mapa y te puede ofrecer pedidos. Tocá '
        '"Desconectarse" cuando termines.',
  ),
  SplgAccordionEntry(
    title: '¿Cómo recibo los pedidos?',
    body: 'Te llegan como una oferta con la dirección y el detalle. '
        'Tenés unos segundos para aceptarla o rechazarla.',
  ),
  SplgAccordionEntry(
    title: '¿Dónde veo mis entregas y lo que cobré?',
    body: 'En "Mis entregas" está el historial con fecha, monto y estado. '
        'En "Estadísticas" ves el total del día y de la semana.',
  ),
  SplgAccordionEntry(
    title: '¿Cómo cambio mi contraseña?',
    body: 'Entrá a Mi perfil y elegí "Cambiar contraseña". Si la olvidaste, '
        'en la pantalla de inicio de sesión tocá "¿Olvidaste tu contraseña?" '
        'y te mandamos un correo.',
  ),
  SplgAccordionEntry(
    title: 'Mis datos o mi vehículo están mal',
    body: 'Los datos personales y el vehículo los carga tu distribuidora. '
        'Pedile el cambio a ella.',
  ),
  SplgAccordionEntry(
    title: 'Tengo un problema con la app',
    body: 'Escribinos a soporte@splg.app contando qué pasó y, si podés, '
        'con una captura de pantalla.',
  ),
];

class HelpView extends StatefulWidget {
  const HelpView({super.key});

  @override
  State<HelpView> createState() => _HelpViewState();
}

class _HelpViewState extends State<HelpView> {
  String _query = '';

  List<SplgAccordionEntry> get _entries {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return helpEntries;
    return [
      for (final e in helpEntries)
        if (e.title.toLowerCase().contains(q) ||
            e.body.toLowerCase().contains(q))
          e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: const DriverHeader(title: 'Ayuda'),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: SplgSearchField(
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('No encontramos nada con esa búsqueda.',
                      textAlign: TextAlign.center,
                      style: SplgType.of(context).body),
                )
              else
                // La clave fuerza a reconstruir el acordeón al cambiar el filtro.
                SplgAccordion(
                    key: ValueKey(_query.trim().toLowerCase()),
                    entries: entries),
            ],
          ),
        ),
      ),
    );
  }
}
