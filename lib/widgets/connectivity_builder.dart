import 'dart:async';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// Helper to query internet connectivity.
Future<bool> get isConnected async {
  try {
    return await InternetConnection().hasInternetAccess;
  } catch (_) {
    return false;
  }
}

class FutureBuilder2<T> extends FutureBuilder<T> {
  final String callerName;
  FutureBuilder2({
    super.key,
    super.future,
    super.initialData,
    required AsyncWidgetBuilder<T> builder,
    this.callerName = 'Unknown',
  }) : super(builder: (BuildContext context, AsyncSnapshot<T> snapshot) {
          if (snapshot.hasError) {
            FlutterError.reportError(FlutterErrorDetails(
                context: ErrorDescription('from $callerName'),
                exception: snapshot.error!,
                stack: snapshot.stackTrace));
          }
          return builder(context, snapshot);
        });
}

class ConnectivityFutureBuilder extends StatefulWidget {
  final Widget child;
  final Widget noInternetIconButton;
  const ConnectivityFutureBuilder(this.child, this.noInternetIconButton,
      {super.key});

  @override
  State<ConnectivityFutureBuilder> createState() =>
      _ConnectivityFutureBuilderState();
}

class _ConnectivityFutureBuilderState extends State<ConnectivityFutureBuilder> {
  late final StreamSubscription<InternetStatus> _subscription;
  late final AppLifecycleListener _listener;
  bool _hasInternet = true;

  @override
  void initState() {
    super.initState();
    if (mounted) {
      isConnected.then((value) {
        if (mounted) setState(() => _hasInternet = value);
      });
      _subscription = InternetConnection().onStatusChange.listen((status) {
        if (status == InternetStatus.connected) {
          if (mounted) setState(() => _hasInternet = true);
        } else {
          if (mounted) setState(() => _hasInternet = false);
        }
      });
      _listener = AppLifecycleListener(
        onResume: _subscription.resume,
        onHide: _subscription.pause,
        onPause: _subscription.pause,
      );
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _hasInternet
        ? widget.child
        : widget.noInternetIconButton;
  }
}
