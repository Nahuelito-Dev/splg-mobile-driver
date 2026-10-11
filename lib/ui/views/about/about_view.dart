import 'package:flutter/material.dart';
import 'package:splg_lib/splg_lib.dart';

import 'package:splg_driver/ui/widgets/driver_header.dart';

const aboutEntries = [
  SplgAccordionEntry(
    title: '¿Qué es SPLG?',
    body: 'SPLG es el sistema de pedidos y logística de garrafas: los '
        'clientes piden desde su app, la distribuidora administra todo desde '
        'el panel y los choferes entregan con esta app.',
  ),
  SplgAccordionEntry(
    title: '¿Cómo funciona para el chofer?',
    body: 'Tu distribuidora te da de alta y te asigna un vehículo. Te '
        'conectás, recibís ofertas de pedidos cercanos, entregás y el '
        'sistema registra la entrega.',
  ),
  SplgAccordionEntry(
    title: '¿Quién desarrolla la app?',
    body: 'SPLG es un proyecto de tesis. Para consultas escribí a '
        'soporte@splg.app.',
  ),
];

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        appBar: DriverHeader(title: 'Acerca de nosotros', bell: false),
        body: SafeArea(
          child: SingleChildScrollView(
            child: SplgAccordion(
                entries: aboutEntries, initiallyOpen: 0, iconUp: true),
          ),
        ),
      );
}
