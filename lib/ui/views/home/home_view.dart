import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/ui/widgets/driver_menu_drawer.dart';

import 'home_viewmodel.dart';

/// Inicio del chofer: mapa a pantalla completa, botones flotantes (menú y
/// estado) arriba a la izquierda, el total de hoy arriba a la derecha y abajo
/// la hoja con "Conectarse" / "Desconectarse".
class HomeView extends StackedView<HomeViewModel> {
  const HomeView({super.key});

  /// Sólo para tests: reemplaza el mapa de Google por un placeholder.
  @visibleForTesting
  static Widget Function(BuildContext, HomeViewModel)? debugMapBuilder;

  /// Sólo para tests: fabrica el ViewModel (con el estado que se quiera ver).
  @visibleForTesting
  static HomeViewModel Function()? debugViewModelFactory;

  @override
  Widget builder(BuildContext context, HomeViewModel viewModel, Widget? child) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      drawer: DriverMenuDrawer(onLogout: viewModel.logout),
      body: viewModel.isBusy
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context, viewModel),
    );
  }

  Widget _buildBody(BuildContext context, HomeViewModel viewModel) {
    if (!viewModel.hasLocationPermission) {
      return SafeArea(child: _buildPermissionDeniedView(context, viewModel));
    }

    return Stack(
      children: [
        Positioned.fill(
          child: HomeView.debugMapBuilder?.call(context, viewModel) ??
              GoogleMap(
                mapType: MapType.terrain,
                initialCameraPosition: HomeViewModel.initialPosition,
                onMapCreated: viewModel.onMapCreated,
                markers: viewModel.markers,
                myLocationEnabled: false, // Usamos nuestro propio marcador
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
                mapToolbarEnabled: false,
              ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Builder(
                      builder: (ctx) => SplgFloatingButton(
                        key: const Key('home-menu'),
                        tooltip: 'Menú',
                        icon: SplgIcons.menu,
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    ),
                    Builder(
                      builder: (ctx) => SplgFloatingButton(
                        key: const Key('home-status'),
                        tooltip: 'Estado',
                        label: viewModel.statusLabel,
                        icon: SplgIcons.online,
                        color: !viewModel.isOnline
                            ? Theme.of(context).colorScheme.inverseSurface
                            : (viewModel.isConnected
                                ? context.brasa.success
                                : context.brasa.warn),
                        onPressed: () => _showStatus(ctx, viewModel),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (viewModel.todayCount > 0)
                  _TodayTotal(
                    total: viewModel.todayTotal,
                    count: viewModel.todayCount,
                  ),
              ],
            ),
          ),
        ),
        if (viewModel.hasLocationPermission &&
            viewModel.currentLocation != null)
          Positioned(
            left: 8,
            bottom: context.sp(70) + 24,
            child: SplgFloatingButton(
              key: const Key('home-locate'),
              tooltip: 'Centrar en mi ubicación',
              label: 'Mi ubicación',
              icon: SplgIcons.locate,
              onPressed: viewModel.centerOnUserLocation,
            ),
          ),
        if (viewModel.search != HomeSearch.idle)
          Center(child: _SearchCard(search: viewModel.search)),
        Align(
          alignment: Alignment.bottomCenter,
          child: _ConnectSheet(viewModel: viewModel),
        ),
      ],
    );
  }

  void _showStatus(BuildContext context, HomeViewModel viewModel) {
    final text = !viewModel.isOnline
        ? 'Estás desconectado: no vas a recibir pedidos.'
        : (viewModel.isConnected
            ? 'Estás en línea: podés recibir pedidos.'
            : 'Reconectando… seguís en línea.');
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
      ));
  }

  Widget _buildPermissionDeniedView(
      BuildContext context, HomeViewModel viewModel) {
    final type = SplgType.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(SplgIcons.location,
                size: 80, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 24),
            Text(
              'Permisos de ubicación requeridos',
              style: type.title.copyWith(fontSize: context.sp(14)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              viewModel.permissionMessage ??
                  'No se pueden obtener los permisos de ubicación',
              style: type.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SplgButton(
              title: 'Solicitar permisos',
              onPressed: viewModel.requestLocationPermission,
            ),
            const SizedBox(height: 12),
            SplgButton(
              title: 'Abrir configuración',
              style: SplgButtonStyle.outlined,
              onPressed: viewModel.openSettings,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              child: const Text('Abrir el menú'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  HomeViewModel viewModelBuilder(BuildContext context) =>
      HomeView.debugViewModelFactory?.call() ?? HomeViewModel();

  @override
  void onViewModelReady(HomeViewModel viewModel) {
    viewModel.initialize();
    super.onViewModelReady(viewModel);
  }
}

/// "Total de hoy": pestaña que se despliega desde el borde derecho. Sólo se
/// muestra si ya hubo entregas hoy.
class _TodayTotal extends StatefulWidget {
  const _TodayTotal({required this.total, required this.count});

  final num total;
  final int count;

  @override
  State<_TodayTotal> createState() => _TodayTotalState();
}

class _TodayTotalState extends State<_TodayTotal> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final strong = context.brasa.primaryStrong;
    final type = SplgType.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: strong,
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(16)),
            child: InkWell(
              key: const Key('home-today'),
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(16)),
              onTap: () => setState(() => _open = !_open),
              child: SizedBox(
                width: 55,
                height: 65,
                child: Icon(_open ? SplgIcons.next : SplgIcons.back,
                    color: Colors.white),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: _open ? 190 : 0,
            height: 65,
            color: strong,
            padding: _open ? const EdgeInsets.only(right: 12) : EdgeInsets.zero,
            child: _open
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total de hoy',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.caption.copyWith(color: Colors.white)),
                      Text(formatMoney(widget.total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.value.copyWith(color: Colors.white)),
                      Text(
                          widget.count == 1
                              ? '1 entrega'
                              : '${widget.count} entregas',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.caption.copyWith(color: Colors.white)),
                    ],
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// "Buscando pedidos…" y "Sin pedidos disponibles", sobre el mapa.
class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.search});

  final HomeSearch search;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final searching = search == HomeSearch.searching;
    return IgnorePointer(
      child: Container(
        key: Key(searching ? 'search-searching' : 'search-empty'),
        width: context.sp(150),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: searching ? SplgGradients.button : null,
          color:
              searching ? null : Theme.of(context).colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            searching
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: Colors.white),
                  )
                : const Icon(SplgIcons.search, size: 44, color: Colors.white),
            const SizedBox(height: 14),
            Text(
              searching ? 'Buscando pedidos…' : 'Sin pedidos disponibles',
              textAlign: TextAlign.center,
              style: type.title
                  .copyWith(color: Colors.white, fontSize: context.sp(13)),
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? 'Estamos buscando algún pedido cercano para vos.'
                  : '¡Te avisaremos cuando haya uno!',
              textAlign: TextAlign.center,
              style: type.body.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja inferior con el botón de conexión.
class _ConnectSheet extends StatelessWidget {
  const _ConnectSheet({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final online = viewModel.showsDisconnect;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SplgButton(
                title: online ? 'Desconectarse' : 'Conectarse',
                style: online ? SplgButtonStyle.danger : SplgButtonStyle.filled,
                loading: viewModel.isConnecting,
                onPressed: online ? viewModel.disconnect : viewModel.connect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
