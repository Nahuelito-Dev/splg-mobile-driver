import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'home_viewmodel.dart';

class HomeView extends StackedView<HomeViewModel> {
  const HomeView({super.key});

  @override
  Widget builder(BuildContext context, HomeViewModel viewModel, Widget? child) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        actions: [
          // Botón para centrar en la ubicación del usuario
          if (viewModel.hasLocationPermission &&
              viewModel.currentLocation != null)
            IconButton(
              onPressed: viewModel.centerOnUserLocation,
              icon: const Icon(Icons.my_location),
              tooltip: 'Centrar en mi ubicación',
            ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withAlpha(30),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(
                    Icons.local_shipping,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chofer prueba',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: const Text('Cuenta'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navegar a la vista de cuenta
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Historial'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navegar a la vista de historial
              },
            ),
            Divider(
              color: Theme.of(context).colorScheme.outline.withAlpha(30),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Ayuda'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navegar a la vista de ayuda
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacidad'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navegar a la vista de privacidad
              },
            ),
            Divider(
              color: Theme.of(context).colorScheme.outline.withAlpha(30),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Desconectarse'),
              onTap: () {
                Navigator.pop(context);
                viewModel.logout();
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: viewModel.isBusy
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : _buildBody(context, viewModel),
      ),
    );
  }

  Widget _buildBody(BuildContext context, HomeViewModel viewModel) {
    // Si no hay permisos, mostrar mensaje
    if (!viewModel.hasLocationPermission) {
      return _buildPermissionDeniedView(context, viewModel);
    }

    // Mostrar el mapa
    return Stack(
      children: [
        GoogleMap(
          mapType: MapType.terrain,
          initialCameraPosition: HomeViewModel.initialPosition,
          onMapCreated: viewModel.onMapCreated,
          markers: viewModel.markers,
          myLocationEnabled: false, // Usamos nuestro propio marcador
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
          compassEnabled: true,
          mapToolbarEnabled: false,
        ),
        // Indicador de tracking activo
        if (viewModel.dataReady)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.navigation, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Seguimiento activo',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        // Botón conectarse / desconectarse
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: ElevatedButton(
              onPressed:
                  viewModel.isConnected ? viewModel.disconnect : viewModel.connect,
              style: ElevatedButton.styleFrom(
                backgroundColor: viewModel.isConnected ? Colors.green : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                elevation: 4,
              ),
              child: Text(
                viewModel.isConnected ? 'Conectado' : 'Conectarse',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionDeniedView(
      BuildContext context, HomeViewModel viewModel) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off,
              size: 80,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Permisos de ubicación requeridos',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              viewModel.permissionMessage ??
                  'No se pueden obtener los permisos de ubicación',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: viewModel.requestLocationPermission,
              icon: const Icon(Icons.location_on),
              label: const Text('Solicitar permisos'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: viewModel.openSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Abrir configuración'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  HomeViewModel viewModelBuilder(BuildContext context) => HomeViewModel();

  @override
  void onViewModelReady(HomeViewModel viewModel) {
    viewModel.initialize();
    super.onViewModelReady(viewModel);
  }
}
