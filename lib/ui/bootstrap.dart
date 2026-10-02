import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../data/api_client.dart';
import '../data/account_repository.dart';
import '../data/sync_controller.dart';
import '../data/secure_session.dart';
import '../data/native_notifications.dart';
import '../data/server_config.dart';
import '../domain/store.dart';
import 'app.dart';
import 'auth_page.dart';
import 'theme.dart';

class FlowBootstrap extends StatefulWidget {
  const FlowBootstrap({
    super.key,
    required this.directory,
    required this.localStore,
    this.secureSession,
    this.notifications,
    this.apiFactory,
  });
  final Directory directory;
  final FlowStore localStore;
  final SecureSession? secureSession;
  final NativeNotifications? notifications;
  final FlowApi Function(Uri)? apiFactory;
  @override
  State<FlowBootstrap> createState() => _FlowBootstrapState();
}

class _FlowBootstrapState extends State<FlowBootstrap> {
  SyncController? sync;
  Directory? accountDirectory;
  bool authenticating = false;
  bool restoring = true;
  late final SecureSession credentials =
      widget.secureSession ?? SecureSession();
  late final NativeNotifications notifications =
      widget.notifications ?? NativeNotifications.instance;

  @override
  void initState() {
    super.initState();
    unawaited(restoreSession());
  }

  Future<void> restoreSession() async {
    try {
      final saved = await credentials.load();
      if (saved != null) {
        if (saved.server != flowdayApiBaseUrl) {
          await credentials.clear();
          return;
        }
        final api =
            widget.apiFactory?.call(saved.server) ?? FlowApi(saved.server);
        var session = saved.session;
        try {
          final user = await api.me(session.token);
          if (user.id != session.user.id) {
            await credentials.clear();
            return;
          }
          session = AuthSession(token: session.token, user: user);
        } on ApiException catch (error) {
          if (error.status == 401 || error.status == 403) {
            await credentials.clear();
            return;
          }
          if (error.status != 0 && error.status < 500) rethrow;
        }
        if (!mounted) return;
        await authenticate(session, api);
      }
    } catch (_) {
      /* Startup remains available when the OS credential service is unavailable. */
    } finally {
      if (mounted) {
        setState(() => restoring = false);
        if (sync == null) {
          unawaited(
            notifications.attach(
              widget.localStore,
              directory: widget.directory,
            ),
          );
        }
      }
    }
  }

  Future<void> authenticate(AuthSession session, FlowApi api) async {
    if (api.baseUrl != flowdayApiBaseUrl) {
      throw const FormatException('服务器地址无效');
    }
    await widget.localStore.persist();
    if (widget.localStore.error != null) {
      throw StateError(widget.localStore.error!);
    }
    final repository = AccountRepository(
      widget.directory,
      api.baseUrl,
      session.user.id,
    );
    final baseline = await repository.loadBaseline();
    final data = await repository.load();
    final store = FlowStore(data, save: repository.save);
    final controller = SyncController(
      api: api,
      session: session,
      store: store,
      baseVersion: baseline.version,
      lastSyncedJson: baseline.json,
      saveBaseline: repository.saveBaseline,
      beforeReplace: () async {
        await repository.backup(store.data);
      },
    );
    // Without a persisted baseline, differing copies require an explicit choice.
    await controller.sync();
    if (!mounted) {
      controller.dispose();
      store.dispose();
      return;
    }
    try {
      await credentials.save(api, session);
    } catch (_) {
      controller.dispose();
      store.dispose();
      rethrow;
    }
    if (!mounted) {
      controller.dispose();
      store.dispose();
      return;
    }
    controller.setAutoSync(true);
    setState(() {
      sync = controller;
      accountDirectory = repository.directory;
      authenticating = false;
    });
    unawaited(
      notifications.attach(
        store,
        api: api,
        token: session.token,
        directory: repository.directory,
      ),
    );
  }

  Future<void> logout() async {
    final current = sync;
    if (current == null || current.busy) return;
    await current.store.persist();
    if (current.store.error != null) throw StateError(current.store.error!);
    await credentials.clear();
    try {
      await current.logout();
    } on ApiException catch (e) {
      if (e.status != 401 && e.status != 0) rethrow;
    }
    if (!mounted) return;
    setState(() {
      sync = null;
      accountDirectory = null;
      authenticating = true;
    });
    current.dispose();
    current.store.dispose();
    await notifications.attach(widget.localStore, directory: widget.directory);
  }

  @override
  void dispose() {
    sync?.dispose();
    sync?.store.dispose();
    // Keep OS schedules when the app closes; stop only in-process polling.
    notifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (restoring) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: flowTheme(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (authenticating) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: flowTheme(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: AuthPage(
          apiFactory: widget.apiFactory,
          onAuthenticated: authenticate,
          onContinueLocal: () => setState(() => authenticating = false),
        ),
      );
    }
    return FlowDayApp(
      key: ValueKey(sync?.session.user.id ?? 'local'),
      store: sync?.store ?? widget.localStore,
      sync: sync,
      directory: accountDirectory ?? widget.directory,
      onLogin: () => setState(() => authenticating = true),
      onLogout: logout,
    );
  }
}
